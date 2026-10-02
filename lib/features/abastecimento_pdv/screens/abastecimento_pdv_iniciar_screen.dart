import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/abastecimento_pdv_provider.dart';

// Fase 2 PDV (02/10/2026) — Tela 1 do fluxo: "Abastecer neste posto".
// Pega a localização do motorista (bloqueante — sem ela não dá nem pra
// listar revendas por proximidade), lista as revendas com PDV ativo por
// perto e, ao confirmar, chama iniciar_abastecimento_pdv — que faz o
// double-check de geofencing (raio de 500m, configurável por cliente) no
// servidor. Se aprovado, segue pra Tela 2 (código + OTP).
class AbastecimentoPdvIniciarScreen extends ConsumerStatefulWidget {
  const AbastecimentoPdvIniciarScreen({super.key});

  @override
  ConsumerState<AbastecimentoPdvIniciarScreen> createState() =>
      _AbastecimentoPdvIniciarScreenState();
}

class _AbastecimentoPdvIniciarScreenState
    extends ConsumerState<AbastecimentoPdvIniciarScreen> {
  LocalizacaoPdv? _localizacao;
  bool _obtendoLocalizacao = true;
  String? _revendaSelecionadaId;
  bool _confirmando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarLocalizacao();
  }

  Future<void> _carregarLocalizacao() async {
    setState(() {
      _obtendoLocalizacao = true;
      _erro = null;
    });
    final loc = await obterLocalizacaoBloqueantePdv();
    if (!mounted) return;
    setState(() {
      _localizacao = loc;
      _obtendoLocalizacao = false;
    });
  }

  Future<void> _confirmar() async {
    final loc = _localizacao;
    if (loc == null || loc.lat == null || loc.lon == null) return;
    if (_revendaSelecionadaId == null) {
      setState(() => _erro = 'Selecione o posto onde você está.');
      return;
    }

    setState(() {
      _confirmando = true;
      _erro = null;
    });
    try {
      final resultado = await AbastecimentoPdvService.iniciar(
        revendaEmpresaId: _revendaSelecionadaId!,
        lat: loc.lat!,
        lon: loc.lon!,
      );
      if (!mounted) return;

      switch (resultado.status) {
        case 'aguardando_pdv':
          context.push(
            '/abastecimento-pdv/otp',
            extra: {
              'id': resultado.id,
              'codigoAbastecimento': resultado.codigoAbastecimento,
              'otpAtual': resultado.otpAtual,
              'otpValidoAteTransacao': resultado.otpValidoAteTransacao,
              'nomeRevenda': resultado.nomeRevenda,
            },
          );
          break;
        case 'geolocalizacao_reprovada':
          setState(
            () => _erro =
                'Você está a ${resultado.distanciaMetros?.toStringAsFixed(0) ?? '?'} m do posto — '
                'o limite permitido é ${resultado.raioPermitidoMetros?.toStringAsFixed(0) ?? '500'} m. '
                'Chegue mais perto da bomba e tente de novo.',
          );
          break;
        case 'nao_vinculado':
          setState(() => _erro = 'Seu usuário não está vinculado a um cadastro de motorista.');
          break;
        case 'veiculo_nao_identificado':
        case 'veiculo_nao_autorizado':
          setState(() => _erro = 'Não encontrei um veículo autorizado vinculado a você.');
          break;
        case 'revenda_invalida':
        case 'posto_sem_coordenadas':
        case 'revenda_sem_pdv_ativo':
          setState(() => _erro = 'Esse posto não está com o PDV disponível no momento. Tente outro ou abasteça por outro canal.');
          break;
        default:
          setState(() => _erro = 'Não consegui iniciar o abastecimento agora. Tente de novo em instantes.');
      }
    } catch (e) {
      setState(() => _erro = 'Não consegui iniciar o abastecimento agora. Tente de novo em instantes.');
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Abastecer neste posto'),
      ),
      drawer: const AppDrawer(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_obtendoLocalizacao) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Obtendo sua localização...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    final loc = _localizacao;
    if (loc == null || loc.erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 48, color: AppTheme.statusInativo),
              const SizedBox(height: 16),
              Text(
                loc?.erro ?? 'Não consegui obter sua localização.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _carregarLocalizacao,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }

    final revendasAsync = ref.watch(
      revendasPdvProximasProvider((lat: loc.lat!, lon: loc.lon!)),
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(revendasPdvProximasProvider((lat: loc.lat!, lon: loc.lon!)));
        await ref.read(revendasPdvProximasProvider((lat: loc.lat!, lon: loc.lon!)).future);
      },
      child: revendasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: const [
            Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Não consegui buscar os postos perto de você agora. Puxe pra baixo pra tentar de novo.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        data: (revendas) {
          if (revendas.isEmpty) {
            return ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Nenhum posto com PDV ativo encontrado perto de você no momento.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Selecione o posto onde você está. Sua localização será conferida ao confirmar — fique perto da bomba.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              ...revendas.map(
                (r) => Card(
                  child: RadioListTile<String>(
                    value: r.revendaEmpresaId,
                    groupValue: _revendaSelecionadaId,
                    onChanged: (v) => setState(() => _revendaSelecionadaId = v),
                    title: Text(r.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [
                        if (r.municipio != null) '${r.municipio}${r.uf != null ? '/${r.uf}' : ''}',
                        '${(r.distanciaMetros / 1000).toStringAsFixed(1)} km daqui',
                      ].join(' · '),
                    ),
                  ),
                ),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, style: const TextStyle(color: AppTheme.statusInativo)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _confirmando ? null : _confirmar,
                child: _confirmando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Confirmar abastecimento neste posto'),
              ),
            ],
          );
        },
      ),
    );
  }
}
