import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_drawer.dart';
import '../providers/roteirizacao_provider.dart';
import '../utils/cores_bandeira.dart';
import '../utils/roteirizacao_algoritmo.dart';
import '../utils/roteirizacao_constantes.dart';

// Fase Roteirização-Google-Maps — pedido do Daniel: "ao clicar no card do
// posto, o usuario seja direcionado para o google maps para visualizacao
// do posto". Formato de URL universal do Google Maps (funciona tanto
// abrindo o app nativo, se instalado, quanto o navegador) — mesmo padrão
// já usado no motor de testes de outras telas do projeto.
Future<void> _abrirNoGoogleMaps(double lat, double lon) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$lat,$lon',
  );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

final _formatoKm = NumberFormat('#,##0.0', 'pt_BR');
final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

const _motivoLabel = {
  'otimizado': 'Melhor custo-benefício',
  'estrategico': 'Vale a pena esticar até aqui',
  'emergencia': 'Parada obrigatória (tanque no limite)',
  // Fase Seleção-Manual-de-Postos (28/07/2026) — parada escolhida pelo
  // próprio motorista (não pelo algoritmo), ver calcularAbastecimentoParaSelecao.
  'manual': 'Selecionada por você',
};

const _gradeCor = {
  'A': AppTheme.statusAtivo,
  'B': AppTheme.frota500,
  'C': AppTheme.statusAtencao,
  'D': AppTheme.statusInativo,
};

// Roteirização self-service (Fase 17/07) — pedido do Daniel: "trazer as
// consultas de roteirização assim como tem no pwa cliente". Fase 17/07-3
// ampliou pra trazer o mesmo motor de otimização do painel web: cor do
// marcador por bandeira, filtro de combustível, combustível já no tanque e
// preço/custo sugeridos de cada parada.
class RoteirizacaoScreen extends StatefulWidget {
  const RoteirizacaoScreen({super.key});

  @override
  State<RoteirizacaoScreen> createState() => _RoteirizacaoScreenState();
}

class _RoteirizacaoScreenState extends State<RoteirizacaoScreen> {
  final _origemCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  final _combustivelInicialCtrl = TextEditingController();
  SugestaoLocal? _origem;
  SugestaoLocal? _destino;
  String? _combustivel;

  bool _carregando = false;
  String? _erro;
  ResultadoRota? _resultado;
  List<PracaPedagioNaRota> _pracasPedagio = [];

  // Fase Seleção-Manual-de-Postos (28/07/2026) — pedido do Daniel: a mesma
  // interatividade que o gestor de frota ganhou no painel web ("clicar nos
  // postos desejados... a partir da seleção eles já vão compondo a rota e o
  // custo total") também pro motorista aqui no PWA. `_candidatos` guarda
  // TODOS os postos do corredor (não só os sugeridos); `_selecionados`
  // começa com a sugestão do algoritmo guloso (otimizarAbastecimento) e o
  // motorista ajusta tocando no mapa ou na lista — litros/custo recalculam
  // na hora via calcularAbastecimentoParaSelecao (função pura, sem round-trip).
  List<CandidatoAbastecimento> _candidatos = [];
  Set<String> _selecionados = {};

  bool _carregandoVeiculos = true;
  List<VeiculoRoteirizacao> _veiculos = [];
  VeiculoRoteirizacao? _veiculoSelecionado;

  @override
  void initState() {
    super.initState();
    _carregarVeiculos();
  }

  Future<void> _carregarVeiculos() async {
    final veiculos = await buscarMeusVeiculos();
    if (!mounted) return;
    setState(() {
      _veiculos = veiculos;
      _veiculoSelecionado = veiculos.isNotEmpty ? veiculos.first : null;
      _carregandoVeiculos = false;
      if (_veiculoSelecionado != null && _veiculoSelecionado!.tanque > 0) {
        _combustivelInicialCtrl.text = _veiculoSelecionado!.tanque
            .toStringAsFixed(0);
      }
    });
  }

  @override
  void dispose() {
    _origemCtrl.dispose();
    _destinoCtrl.dispose();
    _combustivelInicialCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarLocal({required bool origem}) async {
    final controller = origem ? _origemCtrl : _destinoCtrl;
    final termo = controller.text.trim();
    if (termo.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite pelo menos 3 letras pra buscar.')),
      );
      return;
    }
    setState(() => _carregando = true);
    final sugestoes = await geocodificar(termo);
    if (!mounted) return;
    setState(() => _carregando = false);

    if (sugestoes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum local encontrado. Tente outro termo (cidade + estado).',
          ),
        ),
      );
      return;
    }

    final escolhido = await showModalBottomSheet<SugestaoLocal>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: sugestoes
              .map(
                (s) => ListTile(
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: AppTheme.frota600,
                  ),
                  title: Text(s.label),
                  onTap: () => Navigator.pop(ctx, s),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (escolhido == null || !mounted) return;
    setState(() {
      controller.text = escolhido.label;
      if (origem) {
        _origem = escolhido;
      } else {
        _destino = escolhido;
      }
    });
  }

  Future<void> _calcular() async {
    if (_origem == null || _destino == null) {
      setState(() => _erro = 'Escolha a origem e o destino antes de calcular.');
      return;
    }
    if (_veiculoSelecionado == null) {
      setState(() => _erro = 'Selecione a placa do veículo antes de calcular.');
      return;
    }
    if (_veiculoSelecionado!.tanque <= 0 ||
        _veiculoSelecionado!.autonomia <= 0) {
      setState(
        () => _erro =
            'O cadastro dessa placa não tem tanque/autonomia — fale com sua empresa.',
      );
      return;
    }
    if (_combustivel == null) {
      setState(
        () => _erro = 'Selecione o combustível dessa viagem antes de calcular.',
      );
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
      _resultado = null;
      _candidatos = [];
      _selecionados = {};
      _pracasPedagio = [];
    });

    final origemPonto = PontoRota(lat: _origem!.lat, lon: _origem!.lon);
    final destinoPonto = PontoRota(lat: _destino!.lat, lon: _destino!.lon);
    final resultado = await calcularRota(origemPonto, destinoPonto);

    if (!mounted) return;
    if (resultado == null) {
      setState(() {
        _carregando = false;
        _erro =
            'Não consegui calcular a rota agora. Tente de novo em instantes.';
      });
      return;
    }

    final candidatos = await buscarCandidatosAbastecimento(
      coordenadas: resultado.coordenadas,
      combustivel: _combustivel!,
    );
    final pracasPedagio = await buscarPracasPedagioNaRota(
      resultado.coordenadas,
    );

    final combustivelInicial = double.tryParse(
      _combustivelInicialCtrl.text.replaceAll(',', '.'),
    );

    final paradas = otimizarAbastecimento(
      candidatos: candidatos,
      capacidadeTanqueL: _veiculoSelecionado!.tanque,
      autonomiaKmPorL: _veiculoSelecionado!.autonomia,
      distanciaTotalRotaKm: resultado.distanciaKm,
      // Perfil "Equilíbrio" do painel web — pondera preço, qualidade do
      // posto e desvio da rota (sem expor os 4 perfis nesta tela mais
      // simples do motorista).
      pesos: const PesosOtimizacao(preco: 0.5, score: 0.3, desvio: 0.2),
      combustivelInicialL: combustivelInicial,
    );

    if (!mounted) return;
    setState(() {
      _carregando = false;
      _resultado = resultado;
      _candidatos = candidatos;
      // A sugestão do algoritmo vira o ponto de partida da seleção — o
      // motorista ajusta a partir daí (toca pra marcar/desmarcar postos).
      _selecionados = paradas.map((p) => p.posto.cnpj).toSet();
      _pracasPedagio = pracasPedagio;
    });

    // Alimenta a missão "rotas_calculadas" (gamificação) — não bloqueia a
    // tela nem mostra erro se falhar.
    unawaited(registrarRotaCalculada());
  }

  // Recalcula litros/custo/viabilidade a cada toque — 100% no client (função
  // pura), sem round-trip ao servidor. Também recalcula se o motorista mudar
  // o combustível já no tanque depois de já ter um resultado.
  ResultadoSelecaoManual get _selecao {
    if (_resultado == null || _veiculoSelecionado == null) {
      return const ResultadoSelecaoManual(paradas: [], alertas: []);
    }
    final combustivelInicial = double.tryParse(
      _combustivelInicialCtrl.text.replaceAll(',', '.'),
    );
    return calcularAbastecimentoParaSelecao(
      candidatosSelecionados: _candidatos
          .where((c) => _selecionados.contains(c.cnpj))
          .toList(),
      capacidadeTanqueL: _veiculoSelecionado!.tanque,
      autonomiaKmPorL: _veiculoSelecionado!.autonomia,
      distanciaTotalRotaKm: _resultado!.distanciaKm,
      combustivelInicialL: combustivelInicial,
    );
  }

  void _alternarPosto(String cnpj) {
    setState(() {
      if (_selecionados.contains(cnpj)) {
        _selecionados.remove(cnpj);
      } else {
        _selecionados.add(cnpj);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selecao = _selecao;
    final paradasAtuais = selecao.paradas;
    final litrosTotal = paradasAtuais.fold<int>(
      0,
      (s, p) => s + p.litrosSugeridos,
    );
    final custoTotal = paradasAtuais.fold<double>(
      0,
      (s, p) => s + p.custoAbastecimento,
    );
    final custoPedagio = custoPedagioTotal(
      _pracasPedagio,
      categoriaPedagioDoVeiculo(_veiculoSelecionado),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Roteirização'),
      ),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Informe sua origem, destino e o combustível da viagem pra ver a distância, o tempo estimado e onde vale a pena abastecer no caminho.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          _SeletorVeiculo(
            carregando: _carregandoVeiculos,
            veiculos: _veiculos,
            selecionado: _veiculoSelecionado,
            onSelecionar: (v) => setState(() {
              _veiculoSelecionado = v;
              if (v != null && v.tanque > 0)
                _combustivelInicialCtrl.text = v.tanque.toStringAsFixed(0);
            }),
          ),
          const SizedBox(height: 16),
          _CampoLocal(
            label: 'Origem',
            controller: _origemCtrl,
            onBuscar: () => _buscarLocal(origem: true),
          ),
          const SizedBox(height: 12),
          _CampoLocal(
            label: 'Destino',
            controller: _destinoCtrl,
            onBuscar: () => _buscarLocal(origem: false),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _combustivel,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Combustível'),
                  items: produtosPosto
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(p, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _combustivel = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _combustivelInicialCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  // Recalcula litros/custo ao vivo se o motorista ajustar o
                  // combustível já no tanque depois de já ter um resultado.
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Combustível no tanque (L)',
                    helperText: 'padrão: tanque cheio',
                    helperMaxLines: 2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_erro != null) ...[
            Text(_erro!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            onPressed: _carregando ? null : _calcular,
            icon: const Icon(Icons.alt_route),
            label: Text(_carregando ? 'Calculando...' : 'Calcular rota'),
          ),
          if (_resultado != null) ...[
            const SizedBox(height: 24),
            _CartaoResultado(
              resultado: _resultado!,
              candidatos: _candidatos,
              selecionados: _selecionados,
              paradasAtuais: paradasAtuais,
              pracasPedagio: _pracasPedagio,
              onTogglePosto: _alternarPosto,
            ),
          ],
          if (_resultado != null) ...[
            const SizedBox(height: 16),
            _CartaoCustoTotal(
              litrosTotal: litrosTotal,
              custoTotal: custoTotal,
              numParadas: paradasAtuais.length,
              custoPedagio: custoPedagio,
            ),
          ],
          // Fase Seleção-Manual-de-Postos — avisos não bloqueantes quando o
          // tanque não cobre a distância até a próxima parada escolhida (ou
          // até o destino), pra alertar sem travar a tela.
          if (selecao.alertas.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚠️ Verifique as paradas escolhidas:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final alerta in selecao.alertas)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• $alerta',
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_pracasPedagio.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Pedágios na rota (${_pracasPedagio.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            for (final praca in _pracasPedagio) _CartaoPedagio(praca: praca),
          ],
          if (_resultado != null && _candidatos.isEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Nenhum posto com preço registrado pra "$_combustivel" dentro do corredor da rota.',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
          if (_candidatos.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Postos no corredor da rota',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              'Toque num posto (aqui ou no mapa) pra marcar ou desmarcar como parada de abastecimento. '
              'A sugestão inicial já vem marcada — ajuste do seu jeito.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            _ListaCandidatos(
              candidatos: _candidatos,
              selecionados: _selecionados,
              paradasAtuais: paradasAtuais,
              onToggle: _alternarPosto,
            ),
          ],
          if (paradasAtuais.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Suas paradas, na ordem da viagem',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              'Toque num cartão pra ver o posto no Google Maps.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < paradasAtuais.length; i++)
              _CartaoParada(numero: i + 1, parada: paradasAtuais[i]),
          ],
        ],
      ),
    );
  }
}

// Seletor de placa (Fase 17/07-2) — pedido do Daniel: "para a placa, o
// usuario deve selecionar a sua placa na lista ou se tiver vinculo de placa
// e motorista, respeitar o vinculo, capacidade do tanque é do cadastro da
// placa". Com vínculo ativo mostra a placa travada (sem dropdown); sem
// vínculo, lista as placas ativas da empresa pra escolher.
class _SeletorVeiculo extends StatelessWidget {
  final bool carregando;
  final List<VeiculoRoteirizacao> veiculos;
  final VeiculoRoteirizacao? selecionado;
  final ValueChanged<VeiculoRoteirizacao?> onSelecionar;

  const _SeletorVeiculo({
    required this.carregando,
    required this.veiculos,
    required this.selecionado,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'Carregando seu veículo...',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    if (veiculos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: const Text(
          'Não encontramos nenhum veículo cadastrado pra você calcular a autonomia. '
          'Fale com sua empresa pra vincular uma placa.',
          style: TextStyle(fontSize: 12.5, color: Colors.black87),
        ),
      );
    }

    final vinculoAtivo = veiculos.length == 1 && veiculos.first.vinculoAtivo;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  color: AppTheme.frota600,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  vinculoAtivo
                      ? 'Sua placa (vínculo ativo)'
                      : 'Selecione sua placa',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (vinculoAtivo)
              _InfoVeiculo(veiculo: veiculos.first)
            else
              DropdownButtonFormField<VeiculoRoteirizacao>(
                initialValue: selecionado,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: veiculos
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          '${v.placa}${v.modelo != null ? ' — ${v.modelo}' : ''}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: onSelecionar,
              ),
            if (!vinculoAtivo && selecionado != null) ...[
              const SizedBox(height: 8),
              _InfoVeiculo(veiculo: selecionado!),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoVeiculo extends StatelessWidget {
  final VeiculoRoteirizacao veiculo;

  const _InfoVeiculo({required this.veiculo});

  @override
  Widget build(BuildContext context) {
    final autonomiaKm = veiculo.autonomiaKm;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        Text('Placa: ${veiculo.placa}', style: const TextStyle(fontSize: 12.5)),
        if (veiculo.tanque > 0)
          Text(
            'Tanque: ${veiculo.tanque.toStringAsFixed(0)} L',
            style: const TextStyle(fontSize: 12.5),
          ),
        if (veiculo.autonomia > 0)
          Text(
            'Autonomia: ${veiculo.autonomia.toStringAsFixed(1)} km/l',
            style: const TextStyle(fontSize: 12.5),
          ),
        if (autonomiaKm > 0)
          Text(
            'Alcance: ~${autonomiaKm.toStringAsFixed(0)} km',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
      ],
    );
  }
}

class _CampoLocal extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onBuscar;

  const _CampoLocal({
    required this.label,
    required this.controller,
    required this.onBuscar,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onBuscar(),
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Digite a cidade e busque...',
        suffixIcon: IconButton(
          icon: const Icon(Icons.search),
          onPressed: onBuscar,
        ),
      ),
    );
  }
}

class _CartaoResultado extends StatelessWidget {
  final ResultadoRota resultado;
  // Fase Seleção-Manual-de-Postos (28/07/2026) — o mapa agora mostra TODOS
  // os candidatos do corredor (não só as paradas escolhidas): selecionados
  // aparecem coloridos por bandeira, os demais em cinza apagado — igual ao
  // MapaRota.tsx do painel web. Tocar num marcador abre um cartão com o
  // botão de marcar/desmarcar (onTogglePosto).
  final List<CandidatoAbastecimento> candidatos;
  final Set<String> selecionados;
  final List<ParadaSugerida> paradasAtuais;
  final List<PracaPedagioNaRota> pracasPedagio;
  final ValueChanged<String> onTogglePosto;

  const _CartaoResultado({
    required this.resultado,
    required this.candidatos,
    required this.selecionados,
    required this.paradasAtuais,
    this.pracasPedagio = const [],
    required this.onTogglePosto,
  });

  @override
  Widget build(BuildContext context) {
    final horas = resultado.duracaoMin ~/ 60;
    final minutos = (resultado.duracaoMin % 60).round();
    final tempoTexto = horas > 0 ? '${horas}h ${minutos}min' : '${minutos}min';

    final pontosRota = resultado.coordenadas
        .map((p) => LatLng(p.lat, p.lon))
        .toList();
    final origem = pontosRota.first;
    final destino = pontosRota.last;
    final limites = LatLngBounds.fromPoints(pontosRota);

    // Bandeiras distintas entre as paradas selecionadas — vira a legenda de
    // cores do mapa (mesma cor calculada por corPorBandeira, igual ao web).
    final legenda = <String, CorMarcador>{};
    for (final c in candidatos) {
      if (!selecionados.contains(c.cnpj)) continue;
      final label = formatarLabelBandeira(c.bandeira);
      legenda[label] = corPorBandeira(c.bandeira);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Metrica(
                    icone: Icons.straighten,
                    valor: '${_formatoKm.format(resultado.distanciaKm)} km',
                    label: 'Distância',
                  ),
                ),
                Expanded(
                  child: _Metrica(
                    icone: Icons.schedule,
                    valor: tempoTexto,
                    label: 'Tempo estimado',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Mapa OSM de verdade (tiles públicos, sem chave de API) —
            // marcadores dos postos coloridos por bandeira, igual ao
            // planejador do painel web (Ipiranga=amarelo, Shell/Raízen=
            // vermelho, BR/Petrobras/Vibra=verde).
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 320,
                child: FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: limites,
                      padding: const EdgeInsets.all(32),
                    ),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.fni.estradaquecuida',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: pontosRota,
                          color: AppTheme.frota500,
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: origem,
                          width: 36,
                          height: 36,
                          child: const Icon(
                            Icons.trip_origin,
                            color: AppTheme.statusAtivo,
                            size: 28,
                          ),
                        ),
                        Marker(
                          point: destino,
                          width: 36,
                          height: 36,
                          child: const Icon(
                            Icons.location_on,
                            color: AppTheme.statusInativo,
                            size: 34,
                          ),
                        ),
                        for (final candidato in candidatos)
                          Marker(
                            point: LatLng(candidato.lat, candidato.lon),
                            width: selecionados.contains(candidato.cnpj)
                                ? 30
                                : 20,
                            height: selecionados.contains(candidato.cnpj)
                                ? 30
                                : 20,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _abrirDetalhePosto(
                                context,
                                candidato,
                                selecionados.contains(candidato.cnpj),
                                onTogglePosto,
                              ),
                              child: Icon(
                                Icons.local_gas_station,
                                color: selecionados.contains(candidato.cnpj)
                                    ? coresHexBandeira[corPorBandeira(
                                        candidato.bandeira,
                                      )]
                                    : Colors.grey.shade400,
                                size: selecionados.contains(candidato.cnpj)
                                    ? 26
                                    : 17,
                              ),
                            ),
                          ),
                        // Fase Motorista-Pedagios — praças de pedágio na
                        // rota traçada, mesmo emoji/estilo do PWA Cliente.
                        for (final praca in pracasPedagio)
                          Marker(
                            point: LatLng(praca.lat, praca.lon),
                            width: 26,
                            height: 26,
                            child: const Text(
                              '🎫',
                              style: TextStyle(fontSize: 20),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 9, color: Colors.black38),
            ),
            if (legenda.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: legenda.entries
                    .map(
                      (e) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: coresHexBandeira[e.value],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(e.key, style: const TextStyle(fontSize: 11.5)),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CartaoCustoTotal extends StatelessWidget {
  final int litrosTotal;
  final double custoTotal;
  final int numParadas;
  final double custoPedagio;

  const _CartaoCustoTotal({
    required this.litrosTotal,
    required this.custoTotal,
    required this.numParadas,
    this.custoPedagio = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: 12,
      children: [
        SizedBox(
          width: 160,
          child: _Metrica(
            icone: Icons.local_gas_station_outlined,
            valor: '$litrosTotal L',
            label: 'Litros totais',
          ),
        ),
        SizedBox(
          width: 160,
          child: _Metrica(
            icone: Icons.payments_outlined,
            valor: _formatoMoeda.format(custoTotal),
            label: 'Custo estimado',
          ),
        ),
        SizedBox(
          width: 160,
          child: _Metrica(
            icone: Icons.alt_route,
            valor: '$numParadas',
            label: 'Paradas',
          ),
        ),
        // Fase Motorista-Pedagios — pedido do Daniel: "no resumo de custo
        // total, colocar o valor total de pedágio também".
        SizedBox(
          width: 160,
          child: _Metrica(
            icone: Icons.confirmation_number_outlined,
            valor: _formatoMoeda.format(custoPedagio),
            label: '🎫 Pedágio',
          ),
        ),
      ],
    );
  }
}

class _CartaoPedagio extends StatelessWidget {
  final PracaPedagioNaRota praca;

  const _CartaoPedagio({required this.praca});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Text('🎫', style: TextStyle(fontSize: 18)),
        title: Text(
          praca.nome,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${praca.rodovia ?? praca.concessionaria ?? '—'} · km ${_formatoKm.format(praca.kmNaRota)}',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: Text(
          praca.valorCarro != null
              ? _formatoMoeda.format(praca.valorCarro!)
              : '—',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _Metrica extends StatelessWidget {
  final IconData icone;
  final String valor;
  final String label;

  const _Metrica({
    required this.icone,
    required this.valor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, color: AppTheme.frota600, size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                valor,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.black54, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartaoParada extends StatelessWidget {
  final int numero;
  final ParadaSugerida parada;

  const _CartaoParada({required this.numero, required this.parada});

  @override
  Widget build(BuildContext context) {
    final posto = parada.posto;
    final cor = coresHexBandeira[corPorBandeira(posto.bandeira)];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirNoGoogleMaps(posto.lat, posto.lon),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: cor,
                child: Text(
                  '$numero',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      posto.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      [
                        formatarLabelBandeira(posto.bandeira),
                        if (posto.municipio != null) posto.municipio!,
                      ].join(' • '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _motivoLabel[parada.motivo] ?? parada.motivo,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        Text(
                          '${_formatoKm.format(posto.km)} km',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '${parada.litrosSugeridos} L',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '${posto.preco.toStringAsFixed(3)}/L',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          _formatoMoeda.format(parada.custoAbastecimento),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chega com ${parada.pctChegada.toStringAsFixed(0)}% do tanque · sai com ${parada.pctApos.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: const [
                        Icon(
                          Icons.map_outlined,
                          size: 13,
                          color: Colors.black45,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Toque para ver no Google Maps',
                          style: TextStyle(fontSize: 11, color: Colors.black45),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Fase Seleção-Manual-de-Postos (28/07/2026) — bottom sheet aberto ao tocar
// num marcador do mapa: mostra os dados do posto candidato e o botão pra
// marcar/desmarcar como parada, mesmo padrão do popup do MapaRota.tsx no
// painel web.
void _abrirDetalhePosto(
  BuildContext context,
  CandidatoAbastecimento candidato,
  bool selecionado,
  ValueChanged<String> onToggle,
) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    candidato.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                _GradeBadge(grade: candidato.grade),
              ],
            ),
            Text(
              [
                formatarLabelBandeira(candidato.bandeira),
                if (candidato.municipio != null) candidato.municipio!,
              ].join(' • '),
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                Text(
                  '${_formatoKm.format(candidato.km)} km',
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  'R\$ ${candidato.preco.toStringAsFixed(3)}/L',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  onToggle(candidato.cnpj);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: selecionado
                      ? Colors.grey.shade200
                      : AppTheme.frota600,
                  foregroundColor: selecionado ? Colors.black87 : Colors.white,
                ),
                child: Text(
                  selecionado ? '− Remover parada' : '+ Selecionar como parada',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Badge de grade (A/B/C/D) — mesma escala de cor do painel web (GRADE_COR
// em FormRoteirizacao.tsx).
class _GradeBadge extends StatelessWidget {
  final String grade;

  const _GradeBadge({required this.grade});

  @override
  Widget build(BuildContext context) {
    final cor = _gradeCor[grade] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        grade,
        style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

// Lista tocável de TODOS os postos do corredor (não só os selecionados) —
// pedido do Daniel no painel web, agora também aqui: "usuario clicando nos
// postos desejados e selecionando-os". Ordenada por km pra acompanhar a
// ordem da viagem.
class _ListaCandidatos extends StatelessWidget {
  final List<CandidatoAbastecimento> candidatos;
  final Set<String> selecionados;
  final List<ParadaSugerida> paradasAtuais;
  final ValueChanged<String> onToggle;

  const _ListaCandidatos({
    required this.candidatos,
    required this.selecionados,
    required this.paradasAtuais,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Achado real (02/08/2026, pedido do Daniel: "os postos selecionados
    // aparecem lá no final da fila") — antes ordenava só por km, então os
    // selecionados ficavam perdidos no meio de dezenas de candidatos ao
    // longo do corredor. Porta fiel de candidatosOrdenados em
    // FormRoteirizacao.tsx (web): selecionado primeiro, e dentro de cada
    // grupo mantém a ordem por km da rota.
    final ordenados = [...candidatos]
      ..sort((a, b) {
        final aSel = selecionados.contains(a.cnpj);
        final bSel = selecionados.contains(b.cnpj);
        if (aSel != bSel) return aSel ? -1 : 1;
        return a.km.compareTo(b.km);
      });
    return Column(
      children: [
        for (final c in ordenados)
          _CartaoCandidato(
            candidato: c,
            selecionado: selecionados.contains(c.cnpj),
            parada: _paradaDoPosto(c.cnpj),
            onTap: () => onToggle(c.cnpj),
          ),
      ],
    );
  }

  ParadaSugerida? _paradaDoPosto(String cnpj) {
    for (final p in paradasAtuais) {
      if (p.posto.cnpj == cnpj) return p;
    }
    return null;
  }
}

class _CartaoCandidato extends StatelessWidget {
  final CandidatoAbastecimento candidato;
  final bool selecionado;
  final ParadaSugerida? parada;
  final VoidCallback onTap;

  const _CartaoCandidato({
    required this.candidato,
    required this.selecionado,
    this.parada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: selecionado ? AppTheme.frota50 : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selecionado ? Icons.check_box : Icons.check_box_outline_blank,
                color: selecionado ? AppTheme.frota600 : Colors.black38,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            candidato.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _GradeBadge(grade: candidato.grade),
                      ],
                    ),
                    Text(
                      '${_formatoKm.format(candidato.km)} km · R\$ ${candidato.preco.toStringAsFixed(3)}/L',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black54,
                      ),
                    ),
                    if (parada != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${parada!.litrosSugeridos} L · ${_formatoMoeda.format(parada!.custoAbastecimento)} · '
                        'chega ${parada!.pctChegada.toStringAsFixed(0)}% · sai ${parada!.pctApos.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.frota700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
