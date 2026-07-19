import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../roteirizacao/providers/roteirizacao_provider.dart';
import '../fretes_veiculos_constantes.dart';
import '../providers/fretes_provider.dart';

// Fase Fretes-Compatibilidade-Veiculo (19/07) — mesma simplificação do
// banco (ver migração fretes_trava_compatibilidade_veiculo_funcoes):
// cadastro_veiculos.tipo só tem 'Leve'/'Pesado', enquanto os fretes
// restringem por nome granular (3 grupos). 'Leve' cobre só o grupo
// Leves; 'Pesado' cobre Médios+Pesados (mais permissivo pro motorista de
// veículo pesado, já que o cadastro não distingue os dois).
const Map<String, Set<String>> _nomesCompativeisPorTipo = {
  'Leve': {'3/4', 'Toco', 'VLC', 'Fiorino', 'Van', 'HR'},
  'Pesado': {'Bitruck', 'Truck', 'Carreta', 'Carreta LS', 'Bitrem', 'Rodotrem'},
};

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

// Fase Fretes-Home-3-Abas (19/07) — pedido do Daniel: cor por status, com
// destaque forte (badge preenchida) pro que está "em_andamento" — é o que
// mais importa saber de relance na lista.
const _corStatus = {
  'disponivel': AppTheme.frota500,
  'aguardando_confirmacao': AppTheme.statusAtencao,
  'aceito': AppTheme.frota600,
  'em_andamento': AppTheme.statusAtivo,
  'concluido': Colors.black45,
  'cancelado': AppTheme.statusInativo,
  'recusado': AppTheme.statusInativo,
};

// Fretes (Fase Fretes) — "Uber de frete": mercado aberto com negociação de
// valor, ou frete atribuído direto (próprio/parceiro) só pra confirmar.
// Fase Fretes-Home-3-Abas (19/07) — pedido do Daniel: dividir em 3 abas
// (Em Negociação / Aceitos-Em Andamento / Concluídos) pra melhorar a
// visibilidade — antes tudo vinha numa lista só, misturado.
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
  // Fase Fretes-Compatibilidade-Veiculo — tipo do veículo vinculado ao
  // motorista ('Leve'/'Pesado'/null), pra pré-filtrar a lista de mercado
  // aberto pelo que ele realmente pode aceitar (a trava de verdade mora
  // no banco — isso aqui é só pra não mostrar o que ele não vai conseguir
  // pegar de qualquer jeito).
  String? _tipoVeiculo;

  // Fase Fretes-Dados-Completos-2 — pedido do Daniel (inspirado em telas de
  // outras plataformas de frete): "veja fretes... filtros personalizados de
  // acordo com o seu veículo". Filtro é só de tela (não vai pro servidor) —
  // um frete "combina" se ele não restringiu nada, ou se restringiu algo
  // que está entre o que o motorista marcou que tem.
  final Set<String> _filtroVeiculos = {};
  final Set<String> _filtroCarrocerias = {};

  // Compatibilidade real com o veículo cadastrado do motorista — some da
  // lista o que ele não vai conseguir aceitar de qualquer forma (a trava
  // que impede de verdade fica no banco, ver compativel_veiculo_frete).
  bool _compativelComMeuVeiculo(Frete f) {
    if (f.veiculosAceitos.isEmpty) return true;
    final tipo = _tipoVeiculo;
    if (tipo == null) return true; // sem vínculo/dado — não bloqueia por falta de info
    final aceitos = _nomesCompativeisPorTipo[tipo] ?? const {};
    return f.veiculosAceitos.any(aceitos.contains);
  }

  List<Frete> get _mercadoCompativel => _mercado.where(_compativelComMeuVeiculo).toList();

  List<Frete> get _mercadoFiltrado => _mercadoCompativel.where((f) {
        final combinaVeiculo = f.veiculosAceitos.isEmpty ||
            _filtroVeiculos.isEmpty ||
            f.veiculosAceitos.any(_filtroVeiculos.contains);
        final combinaCarroceria = f.carroceriasAceitas.isEmpty ||
            _filtroCarrocerias.isEmpty ||
            f.carroceriasAceitas.any(_filtroCarrocerias.contains);
        return combinaVeiculo && combinaCarroceria;
      }).toList();

  // Fase Fretes-Home-3-Abas — os 3 grupos que viram as 3 abas.
  List<Frete> get _aguardandoConfirmacao => _atribuidos.where((f) => f.status == 'aguardando_confirmacao').toList();
  List<Frete> get _emAndamento => _atribuidos.where((f) => f.status == 'em_andamento').toList();
  List<Frete> get _aceitos => _atribuidos.where((f) => f.status == 'aceito').toList();
  List<Frete> get _finalizados =>
      _atribuidos.where((f) => f.status == 'concluido' || f.status == 'cancelado' || f.status == 'recusado').toList();

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
      final veiculos = await buscarMeusVeiculos();
      if (!mounted) return;
      final idsNegociando = negociando.map((n) => n.$2.id).toSet();
      VeiculoRoteirizacao? veiculoVinculado;
      for (final v in veiculos) {
        if (v.vinculoAtivo) {
          veiculoVinculado = v;
          break;
        }
      }
      veiculoVinculado ??= veiculos.isNotEmpty ? veiculos.first : null;
      setState(() {
        _mercado = mercado.where((f) => !idsNegociando.contains(f.id)).toList();
        _negociando = negociando;
        _atribuidos = atribuidos;
        _minhaPosicao = posicao;
        _tipoVeiculo = veiculoVinculado?.tipo;
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
    // Contagens nas abas — ajuda o motorista a saber onde tem algo novo
    // sem precisar entrar em cada uma.
    final totalNegociacao = _aguardandoConfirmacao.length + _negociando.length + _mercadoFiltrado.length;
    final totalAndamento = _emAndamento.length + _aceitos.length;
    final totalFinalizados = _finalizados.length;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fretes'),
          bottom: _carregando || _erro != null
              ? null
              : TabBar(
                  // Pedido do Daniel (19/07): texto branco na barra azul
                  // escura do AppBar, pra ficar legível de verdade.
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  unselectedLabelStyle: const TextStyle(fontSize: 12.5),
                  tabs: [
                    Tab(text: 'Em Negociação${totalNegociacao > 0 ? ' ($totalNegociacao)' : ''}'),
                    Tab(text: 'Aceitos/Em Andamento${totalAndamento > 0 ? ' ($totalAndamento)' : ''}'),
                    Tab(text: 'Concluídos${totalFinalizados > 0 ? ' ($totalFinalizados)' : ''}'),
                  ],
                ),
        ),
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
                : TabBarView(
                    children: [
                      _abaNegociacao(),
                      _abaAndamento(),
                      _abaFinalizados(),
                    ],
                  ),
      ),
    );
  }

  Widget _abaNegociacao() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_aguardandoConfirmacao.isNotEmpty) ...[
            const _TituloSecao('Aguardando sua confirmação'),
            ..._aguardandoConfirmacao.map((f) => _CardFrete(frete: f, minhaPosicao: _minhaPosicao, onTap: () => _abrir(f.id))),
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
                _mercado.isEmpty
                    ? 'Nenhum frete disponível no momento.'
                    : _mercadoCompativel.isEmpty
                        ? 'Nenhum frete disponível aceita o tipo do seu veículo cadastrado.'
                        : 'Nenhum frete combina com o filtro selecionado.',
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          ..._mercadoFiltrado.map((f) => _CardFrete(frete: f, minhaPosicao: _minhaPosicao, onTap: () => _abrir(f.id))),
          if (_aguardandoConfirmacao.isEmpty && _negociando.isEmpty && _mercadoFiltrado.isEmpty && _mercado.isNotEmpty)
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _abaAndamento() {
    if (_emAndamento.isEmpty && _aceitos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            Center(child: Text('Nenhum frete aceito ou em andamento agora.', style: TextStyle(color: Colors.black45))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Em andamento primeiro e com destaque — é o que está rolando
          // agora, o resto é só "aceito, ainda não começou".
          if (_emAndamento.isNotEmpty) ...[
            const _TituloSecao('Em andamento'),
            ..._emAndamento.map((f) => _CardFrete(frete: f, minhaPosicao: _minhaPosicao, onTap: () => _abrir(f.id))),
            const SizedBox(height: 20),
          ],
          if (_aceitos.isNotEmpty) ...[
            const _TituloSecao('Aceitos, aguardando início'),
            ..._aceitos.map((f) => _CardFrete(frete: f, minhaPosicao: _minhaPosicao, onTap: () => _abrir(f.id))),
          ],
        ],
      ),
    );
  }

  Widget _abaFinalizados() {
    if (_finalizados.isEmpty) {
      return RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            Center(child: Text('Nenhum frete concluído ainda.', style: TextStyle(color: Colors.black45))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _finalizados.map((f) => _CardFrete(frete: f, minhaPosicao: _minhaPosicao, onTap: () => _abrir(f.id))).toList(),
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

// Fase Fretes-Home-3-Abas — badge de status colorida. "em_andamento" vem
// preenchida (fundo sólido, texto branco) pra saltar aos olhos na lista;
// os demais status vêm só com um tom claro de fundo.
class _ChipStatusFrete extends StatelessWidget {
  final String status;
  const _ChipStatusFrete({required this.status});

  @override
  Widget build(BuildContext context) {
    final cor = _corStatus[status] ?? Colors.black45;
    final destaque = status == 'em_andamento';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: destaque ? cor : cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _labelStatus[status] ?? status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: destaque ? Colors.white : cor),
      ),
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
    final destaque = frete.status == 'em_andamento';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      // Fase Fretes-Home-3-Abas — borda colorida discreta pros "em
      // andamento" pra reforçar o destaque mesmo antes de ler a badge.
      shape: destaque
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppTheme.statusAtivo.withValues(alpha: 0.5), width: 1.5),
            )
          : null,
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
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ChipStatusFrete(status: frete.status),
                  if (subtitulo != null)
                    Text(subtitulo!, style: const TextStyle(fontSize: 11.5, color: Colors.black54, fontWeight: FontWeight.w500)),
                ],
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
