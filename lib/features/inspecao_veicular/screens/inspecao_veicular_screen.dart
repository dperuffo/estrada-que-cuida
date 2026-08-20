import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../gamificacao/providers/missoes_provider.dart';
import '../providers/inspecao_veicular_provider.dart';

import '../../../core/theme/app_theme.dart';

final _formatoData = DateFormat('dd/MM/yyyy');

// Fase Inspeção-pelo-Motorista (30/07/2026) — pedido do Daniel: "Criar este
// formulario de inspeção no PWA motorista". Mesmo checklist de 12 itens do
// gestor/painel web, só que o motorista marca ele mesmo, rotineiramente,
// direto do celular — e ganha pontos de fidelidade (RPC
// registrar_inspecao_motorista credita 15 pontos e alimenta as missões
// "Primeira Inspeção" / "Hábito de Cuidado").
class InspecaoVeicularScreen extends ConsumerStatefulWidget {
  const InspecaoVeicularScreen({super.key});

  @override
  ConsumerState<InspecaoVeicularScreen> createState() =>
      _InspecaoVeicularScreenState();
}

class _InspecaoVeicularScreenState
    extends ConsumerState<InspecaoVeicularScreen> {
  final _hodometroCtrl = TextEditingController();
  String? _placaSelecionada;
  DateTime _dataInspecao = DateTime.now();
  final Map<String, bool> _conformidade = {
    for (final item in itensInspecao) item: true,
  };
  final Map<String, TextEditingController> _observacoes = {
    for (final item in itensInspecao) item: TextEditingController(),
  };
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _hodometroCtrl.dispose();
    for (final ctrl in _observacoes.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _selecionarData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataInspecao,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now(),
    );
    if (escolhida != null) setState(() => _dataInspecao = escolhida);
  }

  Future<void> _enviar() async {
    if (_placaSelecionada == null) {
      setState(
        () => _erro = 'Selecione o veículo que você está inspecionando.',
      );
      return;
    }
    final hodometro = num.tryParse(_hodometroCtrl.text.replaceAll(',', '.'));
    if (hodometro == null) {
      setState(() => _erro = 'Informe o hodômetro atual (só números).');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final resultado = await InspecaoVeicularService.registrar(
        placa: _placaSelecionada!,
        dataInspecao: _dataInspecao,
        hodometro: hodometro,
        conformidadePorItem: _conformidade,
        observacoesPorItem: {
          for (final e in _observacoes.entries)
            if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
        },
      );

      if (!mounted) return;

      switch (resultado.status) {
        case 'registrada':
          ref.invalidate(minhasInspecoesProvider);
          ref.invalidate(missoesProvider);
          final naoConformes = resultado.itensNaoConformes ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                naoConformes > 0
                    ? 'Inspeção registrada! Você ganhou ${resultado.pontos ?? 15} pontos. $naoConformes item(ns) marcado(s) como não conforme — avise seu gestor.'
                    : 'Inspeção registrada! Você ganhou ${resultado.pontos ?? 15} pontos. Tudo conforme 🎉',
              ),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _placaSelecionada = null;
            _hodometroCtrl.clear();
            for (final item in itensInspecao) {
              _conformidade[item] = true;
              _observacoes[item]!.clear();
            }
          });
          break;
        case 'ja_registrada_hoje':
          setState(
            () => _erro =
                'Você já registrou uma inspeção pra esse veículo nessa data.',
          );
          break;
        case 'veiculo_nao_autorizado':
          setState(() => _erro = 'Esse veículo não está vinculado a você.');
          break;
        default:
          setState(
            () => _erro =
                'Não consegui registrar a inspeção agora. Tente de novo em instantes.',
          );
      }
    } catch (e) {
      setState(
        () => _erro =
            'Não consegui registrar a inspeção agora. Tente de novo em instantes.',
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final veiculosAsync = ref.watch(veiculosInspecaoProvider);
    final historicoAsync = ref.watch(minhasInspecoesProvider);
    // Ajuste (30/07/2026) — pedido do Daniel: "traer a informação de
    // hodometro atual para o usuario em tela". Só busca depois que um
    // veículo é escolhido (a RPC precisa da placa).
    final placaAtual = _placaSelecionada;
    final ultimoHodometro = placaAtual == null
        ? null
        : ref.watch(ultimoHodometroInspecaoProvider(placaAtual)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Checklist de inspeção'),
      ),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Faça a inspeção de segurança do seu veículo e ganhe pontos de fidelidade a cada checklist concluído.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          veiculosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => const Text('Não consegui carregar seus veículos.'),
            data: (veiculos) {
              if (veiculos.isEmpty) {
                return const Text(
                  'Nenhum veículo vinculado a você no momento.',
                );
              }
              return DropdownButtonFormField<String>(
                initialValue: _placaSelecionada,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Veículo',
                  border: OutlineInputBorder(),
                ),
                items: veiculos
                    .map(
                      (v) => DropdownMenuItem(
                        value: v.placa,
                        child: Text(v.rotulo, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _placaSelecionada = v),
              );
            },
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _selecionarData,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Data da inspeção',
                border: OutlineInputBorder(),
              ),
              child: Text(_formatoData.format(_dataInspecao)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hodometroCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Hodômetro (km)',
              border: const OutlineInputBorder(),
              helperText: (ultimoHodometro != null && ultimoHodometro > 0)
                  ? 'Último conhecido: ${ultimoHodometro.toStringAsFixed(0)} km'
                  : null,
              suffixIcon: (ultimoHodometro != null && ultimoHodometro > 0)
                  ? IconButton(
                      icon: const Icon(Icons.speed, size: 20),
                      tooltip: 'Usar último hodômetro conhecido',
                      onPressed: () => setState(
                        () => _hodometroCtrl.text = ultimoHodometro
                            .toStringAsFixed(0),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Itens do checklist',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Desmarque o que não estiver em ordem. Itens críticos (pneus e freios) são destacados.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ...itensInspecao.map((item) {
            final critico = itensCriticos.contains(item);
            final conforme = _conformidade[item] ?? true;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  CheckboxListTile(
                    value: conforme,
                    onChanged: (v) =>
                        setState(() => _conformidade[item] = v ?? true),
                    title: Row(
                      children: [
                        Expanded(child: Text(item)),
                        if (critico)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.priority_high,
                              color: Colors.red,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(conforme ? 'Conforme' : 'Não conforme'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (!conforme)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextField(
                        controller: _observacoes[item],
                        decoration: const InputDecoration(
                          labelText: 'O que foi observado?',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ),
                ],
              ),
            );
          }),
          if (_erro != null) ...[
            const SizedBox(height: 8),
            Text(_erro!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _enviando ? null : _enviar,
            child: _enviando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Registrar inspeção'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Suas últimas inspeções',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          historicoAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => const Text('Não consegui carregar seu histórico.'),
            data: (historico) {
              if (historico.isEmpty) {
                return const Text(
                  'Você ainda não registrou nenhuma inspeção.',
                  style: TextStyle(color: Colors.black54),
                );
              }
              return Column(
                children: historico
                    .map(
                      (h) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          h.itensNaoConformes > 0
                              ? Icons.warning_amber_outlined
                              : Icons.check_circle_outline,
                          color: h.itensNaoConformes > 0
                              ? Colors.orange
                              : Colors.green,
                        ),
                        title: Text(
                          '${h.placa} — ${_formatoData.format(h.dataInspecao)}',
                        ),
                        subtitle: Text(
                          h.itensNaoConformes > 0
                              ? '${h.itensNaoConformes} item(ns) não conforme(s)'
                              : 'Tudo conforme',
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
