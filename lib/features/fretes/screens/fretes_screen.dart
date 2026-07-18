import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_drawer.dart';
import '../fretes_veiculos_constantes.dart';
import '../providers/fretes_provider.dart';

final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

const _labelStatus = {
  'disponivel': 'Disponível',
  'aguardando_confirmacao': 'Aguardando sua confirmação',
  'aceito': 'Aceito',
  'em_andamento': 'Em andamento',
  'concluido': 'Concluído',
  'cancelado': 'Cancelado',
  'recusado': 'Recusado',
};

// Fretes (Fase Fretes) — "Uber de frete": mercado aberto com negociação de
// valor, ou frete atribuído direto (próprio/parceiro) só pra confirmar.
class FretesScreen extends StatefulWidget {
  const FretesScreen({super.key});

  @override
  State<FretesScreen> createState() => _FretesScreenState();
}

class _FretesScreenState extends State<FretesScreen> {
  bool _carregando = true;
  String? _erro;
  List<Frete> _mercado = [];
  List<(Negociacao, Frete)> _negociando = [];
  List<Frete> _atribuidos = [];
  // Fase Fretes-Dados-Completos — pedido do Daniel: "pode ser que o
  // endereço de coleta esteja longe dele" — pega a localização atual uma
  // vez ao abrir a lista pra mostrar "X km até a coleta" em cada card,
  // antes mesmo do motorista abrir o frete pra decidir.
  Position? _minhaPosicao;

  // Fase Fretes-Dados-Completos-2 — pedido do Daniel (inspirado em telas de
  // outras plataformas de frete): "veja fretes... filtros personalizados de
  // acordo com o seu veículo". Filtro é só de tela (não vai pro servidor) —
  // um frete "combina" se ele não restringiu nada, ou se restringiu algo
  // que está entre o que o motorista marcou que tem.
  final Set<String> _filtroVeiculos = {};
  final Set<String> _filtroCarrocerias = {};

  List<Frete> get _mercadoFiltrado => _mercado.where((f) {
        final combinaVeiculo = f.veiculosAceitos.isEmpty ||
            _filtroVeiculos.isEmpty ||
            f.veiculosAceitos.any(_filtroVeiculos.contains);
        final combinaCarroceria = f.carroceriasAceitas.isEmpty ||
            _filtroCarrocerias.isEmpty ||
            f.carroceriasAceitas.any(_filtroCarrocerias.contains);
        return combinaVeiculo && combinaCarroceria;
      }).toList();

  Future<void> _abrirFiltros() async {
    final selecionados = await showModalBottomSheet<(Set<String>, Set<String>)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PainelFiltros(veiculosIniciais: _filtroVeiculos, carroceriasIniciais: _filtroCarrocerias),
    );
    if (selecionados == null) return;
    setState(() {
      _filtroVeiculos
        ..clear()
        ..addAll(selecionados.$1);
      _filtroCarrocerias
        ..clear()
        ..addAll(selecionados.$2);
    });
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final mercado = await buscarFretesMercado();
      final negociando = await buscarMinhasNegociacoes();
      final atribuidos = await buscarMeusFretesAtribuidos();
      final posicao = await obterLocalizacaoAtual();
      if (!mounted) return;
      final idsNegociando = negociando.map((n) => n.$2.id).toSet();
      setState(() {
        _mercado = mercado.where((f) => !idsNegociando.contains(f.id)).toList();
        _negociando = negociando;
        _atribuidos = atribuidos;
        _minhaPosicao = posicao;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is PostgrestException ? e.message : 'Não consegui carregar os fretes agora.';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fretes')),
      drawer: const AppDrawer(),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_atribuidos.isNotEmpty) ...[
                    const _TituloSecao('Meus fretes'),
                    ..._atribuidos.map((f) => _CardFrete(frete: f, minhaPosicao: _minhaPosicao, onTap: () => _abrir(f.id))),
                    const SizedBox(height: 20),
                  ],
                  if (_negociando.isNotEmpty) ...[
                    const _TituloSecao('Em negociação'),
                    ..._negociando.map(
                      (par) => _CardFrete(
                        frete: par.$2,
                        minhaPosicao: _minhaPosicao,
                        subtitulo: 'Rodada ${par.$1.rodadaAtual} · ${_labelNegociacao(par.$1.status)}',
                        onTap: () => _abrir(par.$2.id),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _TituloSecao('Disponíveis pra negociar'),
                      OutlinedButton.icon(
                        onPressed: _abrirFiltros,
                        icon: const Icon(Icons.tune, size: 16),
                        label: Text(
                          (_filtroVeiculos.isEmpty && _filtroCarrocerias.isEmpty)
                              ? 'Filtros'
                              : 'Filtros (${_filtroVeiculos.length + _filtroCarrocerias.length})',
                        ),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  if (_mercadoFiltrado.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        _mercado.isEmpty ? 'Nenhum frete disponível no momento.' : 'Nenhum frete combina com o filtro selecionado.',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  ..._mercadoFiltrado.map((f) => _CardFrete(frete: f, minhaPosicao: _minhaPosicao, onTap: () => _abrir(f.id))),
                ],
              ),
            ),
    );
  }

  String _labelNegociacao(String status) {
    switch (status) {
      case 'aberta':
        return 'aguardando resposta';
      case 'aceita':
        return 'aceita';
      case 'recusada':
        return 'recusada';
      case 'retirada':
        return 'retirada';
      case 'perdida':
        return 'perdida pra outro motorista';
      default:
        return status;
    }
  }

  void _abrir(String freteId) async {
    await context.push('/fretes/$freteId');
    if (mounted) _carregar();
  }
}

class _TituloSecao extends StatelessWidget {
  final String texto;
  const _TituloSecao(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }
}

class _CardFrete extends StatelessWidget {
  final Frete frete;
  final String? subtitulo;
  final Position? minhaPosicao;
  final VoidCallback onTap;

  const _CardFrete({required this.frete, this.subtitulo, this.minhaPosicao, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final posicao = minhaPosicao;
    final distanciaAteColeta =
        posicao == null ? null : distanciaKm(posicao.latitude, posicao.longitude, frete.origemLat, frete.origemLon);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(frete.titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  Text(
                    _formatoMoeda.format(frete.valorOferecido),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.frota700, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${frete.origemLabel} → ${frete.destinoLabel}', style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
              if (distanciaAteColeta != null) ...[
                const SizedBox(height: 4),
                Text(
                  '📍 ${distanciaAteColeta.toStringAsFixed(0)} km até a coleta',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.frota700, fontWeight: FontWeight.w600),
                ),
              ],
              if (frete.coleta.data != null) ...[
                const SizedBox(height: 4),
                Text(
                  '🗓️ Coleta: ${frete.coleta.data}${frete.coleta.hora != null ? ' às ${frete.coleta.hora!.substring(0, 5)}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
              ],
              if (frete.veiculosAceitos.isNotEmpty || frete.carroceriasAceitas.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    ...frete.veiculosAceitos.map((v) => _tagFrete(v, Colors.blue)),
                    ...frete.carroceriasAceitas.map((c) => _tagFrete(c, Colors.black54)),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text(
                subtitulo ?? _labelStatus[frete.status] ?? frete.status,
                style: const TextStyle(fontSize: 11.5, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _tagFrete(String texto, Color cor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(texto, style: TextStyle(fontSize: 10, color: cor)),
    );

// Fase Fretes-Dados-Completos-2 — bottom sheet de filtro por veículo/
// carroceria: estado só de tela (o motorista escolhe toda vez que abre,
// não fica salvo — evita precisar de mais um campo de cadastro/perfil).
class _PainelFiltros extends StatefulWidget {
  final Set<String> veiculosIniciais;
  final Set<String> carroceriasIniciais;
  const _PainelFiltros({required this.veiculosIniciais, required this.carroceriasIniciais});

  @override
  State<_PainelFiltros> createState() => _PainelFiltrosState();
}

class _PainelFiltrosState extends State<_PainelFiltros> {
  late final Set<String> _veiculos = {...widget.veiculosIniciais};
  late final Set<String> _carrocerias = {...widget.carroceriasIniciais};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Filtrar fretes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  TextButton(
                    onPressed: () => setState(() {
                      _veiculos.clear();
                      _carrocerias.clear();
                    }),
                    child: const Text('Limpar'),
                  ),
                ],
              ),
              const Text(
                'Mostra fretes que aceitam o seu tipo de veículo/carroceria, além dos que não restringiram nada.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              ...gruposVeiculoFrete.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key, style: const TextStyle(fontSize: 11, color: Colors.black45)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: e.value
                            .map((v) => FilterChip(
                                  label: Text(v, style: const TextStyle(fontSize: 12)),
                                  selected: _veiculos.contains(v),
                                  onSelected: (sel) => setState(() => sel ? _veiculos.add(v) : _veiculos.remove(v)),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text('Carroceria', style: TextStyle(fontSize: 11, color: Colors.black45)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: carroceriasFrete
                    .map((c) => FilterChip(
                          label: Text(c, style: const TextStyle(fontSize: 12)),
                          selected: _carrocerias.contains(c),
                          onSelected: (sel) => setState(() => sel ? _carrocerias.add(c) : _carrocerias.remove(c)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, (_veiculos, _carrocerias)),
                child: const Text('Aplicar filtro'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
