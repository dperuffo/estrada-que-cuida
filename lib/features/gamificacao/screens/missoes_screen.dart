import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_drawer.dart';
import '../providers/missoes_provider.dart';

class MissoesScreen extends ConsumerWidget {
  const MissoesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missoesAsync = ref.watch(missoesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Missões')),
      drawer: const AppDrawer(),
      body: missoesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não consegui carregar suas missões agora.'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.invalidate(missoesProvider),
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),
        ),
        data: (missoes) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(missoesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: missoes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final missao = missoes[i];
                final progresso = missao.meta == 0 ? 0.0 : missao.progresso / missao.meta;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          missao.iconeData,
                          color: missao.concluida ? const Color(0xFF1B7A43) : Colors.black38,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(missao.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(missao.descricao, style: const TextStyle(color: Colors.black54)),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: progresso.clamp(0.0, 1.0),
                                  minHeight: 8,
                                  backgroundColor: const Color(0xFFE5E5E0),
                                  valueColor: AlwaysStoppedAnimation(missao.concluida ? const Color(0xFF1B7A43) : Colors.black38),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                missao.concluida ? 'Concluída — +${missao.bonus} pontos' : '${missao.progresso}/${missao.meta}',
                                style: TextStyle(
                                  color: missao.concluida ? const Color(0xFF1B7A43) : Colors.black54,
                                  fontWeight: missao.concluida ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
