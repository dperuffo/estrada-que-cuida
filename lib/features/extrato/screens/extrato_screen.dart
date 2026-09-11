import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/app_drawer.dart';
import '../providers/extrato_provider.dart';

import '../../../core/theme/app_theme.dart';

final _formatoData = DateFormat('dd/MM/yyyy HH:mm');
final _formatoDataCurta = DateFormat('dd/MM/yyyy');

// Rótulos de tipo de evento, reaproveitados tanto no texto de cada linha
// quanto no filtro por tipo — uma única fonte de verdade pros dois.
const Map<String, String> _rotulosPorTipo = {
  'abastecimento_confirmado': 'Abastecimento',
  'inicio_jornada': 'Início de jornada',
  'inicio_descanso': 'Início de descanso',
  'inspecao_veiculo': 'Inspeção de veículo',
  'missao_bonus': 'Missão bônus',
  'ajuste_manual': 'Ajuste',
  'resgate': 'Resgate',
};

String _rotuloEvento(LancamentoPontos item) {
  switch (item.tipoEvento) {
    case 'abastecimento_confirmado':
      final placa = item.referencia?['placa'] as String?;
      return placa != null
          ? 'Abastecimento confirmado — $placa'
          : 'Abastecimento confirmado';
    case 'ajuste_manual':
      return 'Ajuste';
    case 'resgate':
      return 'Resgate';
    default:
      return item.tipoEvento;
  }
}

// Placa não é um campo próprio do ledger — vem dentro do jsonb
// `referencia`, e a chave onde ela aparece varia por tipo de evento
// (abastecimento_confirmado e inspecao_veiculo têm 'placa'; os demais
// não têm placa nenhuma). Centraliza a extração aqui pra usar tanto na
// busca quanto, se precisar, na exibição.
String? _placaDoItem(LancamentoPontos item) {
  final valor = item.referencia?['placa'];
  return valor is String && valor.isNotEmpty ? valor : null;
}

bool _mesmoDia(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// Extrato de pontos — histórico completo do ledger (ganhos e usos),
// mais recente primeiro. Cada linha é um evento que já aconteceu — o
// ledger nunca é editado, então isto é sempre auditável.
//
// Filtro (fase Extrato-Filtro, 11/09/2026, pedido do Daniel): busca por
// placa/texto livre, por data e por tipo de evento, aplicados no lado do
// cliente sobre a lista já carregada — o ledger por motorista é pequeno
// o bastante (RLS já restringe a leitura ao dono) pra não valer a pena
// complicar a query do Supabase com filtro em campo jsonb.
class ExtratoScreen extends ConsumerStatefulWidget {
  const ExtratoScreen({super.key});

  @override
  ConsumerState<ExtratoScreen> createState() => _ExtratoScreenState();
}

class _ExtratoScreenState extends ConsumerState<ExtratoScreen> {
  final _buscaController = TextEditingController();
  String _busca = '';
  DateTime? _dataSelecionada;
  String? _tipoSelecionado;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  bool get _temFiltroAtivo =>
      _busca.isNotEmpty || _dataSelecionada != null || _tipoSelecionado != null;

  void _limparFiltros() {
    setState(() {
      _buscaController.clear();
      _busca = '';
      _dataSelecionada = null;
      _tipoSelecionado = null;
    });
  }

  Future<void> _escolherData(BuildContext context) async {
    final agora = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada ?? agora,
      firstDate: DateTime(agora.year - 3),
      lastDate: agora,
      helpText: 'Filtrar por data',
    );
    if (escolhida != null) {
      setState(() => _dataSelecionada = escolhida);
    }
  }

  List<LancamentoPontos> _filtrar(List<LancamentoPontos> itens) {
    final buscaLower = _busca.trim().toLowerCase();
    return itens.where((item) {
      if (_dataSelecionada != null &&
          !_mesmoDia(item.criadoEm, _dataSelecionada!)) {
        return false;
      }
      if (_tipoSelecionado != null && item.tipoEvento != _tipoSelecionado) {
        return false;
      }
      if (buscaLower.isNotEmpty) {
        final placa = _placaDoItem(item)?.toLowerCase() ?? '';
        final rotulo = _rotuloEvento(item).toLowerCase();
        final combina =
            placa.contains(buscaLower) || rotulo.contains(buscaLower);
        if (!combina) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final extratoAsync = ref.watch(extratoPontosProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Extrato de pontos'),
      ),
      drawer: const AppDrawer(),
      body: extratoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não consegui carregar seu extrato agora.'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.invalidate(extratoPontosProvider),
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),
        ),
        data: (itens) {
          if (itens.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum lançamento ainda. Confirme um abastecimento pra começar a pontuar.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Só mostra o filtro por tipo pros tipos que de fato aparecem
          // no extrato desse motorista — evita chips vazios.
          final tiposPresentes = itens.map((e) => e.tipoEvento).toSet();
          final itensFiltrados = _filtrar(itens);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _buscaController,
                      decoration: InputDecoration(
                        hintText: 'Buscar por placa ou descrição',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _busca.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _buscaController.clear();
                                    _busca = '';
                                  });
                                },
                              )
                            : null,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (valor) => setState(() => _busca = valor),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: Text(
                              _dataSelecionada != null
                                  ? _formatoDataCurta.format(_dataSelecionada!)
                                  : 'Data',
                            ),
                            avatar: const Icon(Icons.calendar_today, size: 16),
                            selected: _dataSelecionada != null,
                            onSelected: (_) => _escolherData(context),
                            onDeleted: _dataSelecionada != null
                                ? () => setState(() => _dataSelecionada = null)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          ...tiposPresentes.map((tipo) {
                            final selecionado = _tipoSelecionado == tipo;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(_rotulosPorTipo[tipo] ?? tipo),
                                selected: selecionado,
                                onSelected: (marcado) => setState(() {
                                  _tipoSelecionado = marcado ? tipo : null;
                                }),
                              ),
                            );
                          }),
                          if (_temFiltroAtivo)
                            TextButton(
                              onPressed: _limparFiltros,
                              child: const Text('Limpar'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: itensFiltrados.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Nenhum lançamento encontrado com esse filtro.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(extratoPontosProvider),
                        child: ListView.separated(
                          itemCount: itensFiltrados.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final item = itensFiltrados[i];
                            final positivo = item.pontos >= 0;
                            return ListTile(
                              leading: Icon(
                                positivo
                                    ? Icons.add_circle_outline
                                    : Icons.remove_circle_outline,
                                color: positivo
                                    ? const Color(0xFF1B7A43)
                                    : Colors.redAccent,
                              ),
                              title: Text(_rotuloEvento(item)),
                              subtitle: Text(_formatoData.format(item.criadoEm)),
                              trailing: Text(
                                '${positivo ? '+' : ''}${item.pontos}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: positivo
                                      ? const Color(0xFF1B7A43)
                                      : Colors.redAccent,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
