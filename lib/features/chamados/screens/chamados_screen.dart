import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/app_drawer.dart';
import '../providers/chamados_provider.dart';

import '../../../core/theme/app_theme.dart';

final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

class ChamadosScreen extends ConsumerWidget {
  const ChamadosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chamadosAsync = ref.watch(meusChamadosProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Meus chamados'),
      ),
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/chamados/novo'),
        icon: const Icon(Icons.add),
        label: const Text('Novo chamado'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(meusChamadosProvider),
        child: chamadosAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 80),
              Center(
                child: Text(
                  'Não consegui carregar seus chamados. Puxe pra atualizar.\n$e',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          data: (chamados) {
            if (chamados.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Você ainda não abriu nenhum chamado.\nToque em "Novo chamado" pra relatar um problema ou sugerir uma melhoria.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: chamados.length,
              itemBuilder: (context, i) {
                final t = chamados[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => context.push('/chamados/${t.id}'),
                    title: Text(
                      '#${t.numero} — ${t.titulo}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(tiposTicket[t.tipo] ?? t.tipo),
                        if (t.criadoEm != null)
                          Text(
                            _formatoData.format(
                              DateTime.parse(t.criadoEm!).toLocal(),
                            ),
                          ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ChipStatus(status: t.status),
                        if (t.naoVisto)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Icon(
                              Icons.circle,
                              color: Colors.red,
                              size: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ChipStatus extends StatelessWidget {
  final String status;
  const _ChipStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final cor = switch (status) {
      'aberto' => Colors.blue,
      'em_analise' => Colors.orange,
      'resolvido' => Colors.green,
      'fechado' => Colors.grey,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusTicket[status] ?? status,
        style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
