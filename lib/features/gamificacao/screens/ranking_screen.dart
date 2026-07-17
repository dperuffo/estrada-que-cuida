import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_drawer.dart';
import '../providers/ranking_provider.dart';

class RankingScreen extends ConsumerStatefulWidget {
  const RankingScreen({super.key});

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen> {
  String _periodo = 'mes';

  @override
  Widget build(BuildContext context) {
    final rankingAsync = ref.watch(rankingProvider(_periodo));

    return Scaffold(
      appBar: AppBar(title: const Text('Ranking')),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'semana', label: Text('Semana')),
                ButtonSegment(value: 'mes', label: Text('Mês')),
              ],
              selected: {_periodo},
              onSelectionChanged: (novo) => setState(() => _periodo = novo.first),
            ),
          ),
          Expanded(
            child: rankingAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Não consegui carregar o ranking agora.'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(rankingProvider(_periodo)),
                        child: const Text('Tentar de novo'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (resultado) {
                if (resultado.itens.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Ainda não há pontos suficientes pra montar o ranking neste período.', textAlign: TextAlign.center),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: resultado.itens.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = resultado.itens[i];
                    return ListTile(
                      tileColor: item.voce ? const Color(0xFFEAF5EE) : null,
                      leading: CircleAvatar(
                        backgroundColor: item.posicao <= 3 ? const Color(0xFFC9A227) : const Color(0xFFE5E5E0),
                        foregroundColor: item.posicao <= 3 ? Colors.white : Colors.black87,
                        child: Text('${item.posicao}'),
                      ),
                      title: Text(item.voce ? '${item.nome} (você)' : item.nome, style: TextStyle(fontWeight: item.voce ? FontWeight.bold : FontWeight.normal)),
                      trailing: Text('${item.pontos} pts', style: const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
