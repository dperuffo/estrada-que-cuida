import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/app_drawer.dart';
import '../providers/dependentes_provider.dart';

import '../../../core/theme/app_theme.dart';

final _formatoData = DateFormat('dd/MM/yyyy');

class DependentesScreen extends ConsumerWidget {
  final String motoristaId;

  const DependentesScreen({super.key, required this.motoristaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dependentesAsync = ref.watch(dependentesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Conta Família'),
      ),
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormularioNovo(context, ref),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Adicionar'),
      ),
      body: dependentesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não consegui carregar seus dependentes agora.'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.invalidate(dependentesProvider),
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),
        ),
        data: (dependentes) {
          if (dependentes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum familiar cadastrado ainda. Adicione pra poder resgatar benefícios pra eles também.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: dependentes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = dependentes[i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(d.nome),
                  subtitle: Text(
                    [
                      if (d.parentesco != null) d.parentesco!,
                      if (d.dataNascimento != null)
                        _formatoData.format(d.dataNascimento!),
                    ].join(' • '),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    onPressed: () async {
                      final confirmar = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Remover ${d.nome}?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Remover'),
                            ),
                          ],
                        ),
                      );
                      if (confirmar == true) {
                        await DependentesService.remover(d.id);
                        ref.invalidate(dependentesProvider);
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _abrirFormularioNovo(BuildContext context, WidgetRef ref) {
    final nomeController = TextEditingController();
    final parentescoController = TextEditingController();
    DateTime? dataNascimento;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Novo familiar',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nomeController,
                    decoration: const InputDecoration(labelText: 'Nome'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: parentescoController,
                    decoration: const InputDecoration(
                      labelText: 'Parentesco (ex.: cônjuge, filho(a))',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      dataNascimento == null
                          ? 'Data de nascimento (opcional)'
                          : _formatoData.format(dataNascimento!),
                    ),
                    onPressed: () async {
                      final escolhida = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime(1990),
                        firstDate: DateTime(1930),
                        lastDate: DateTime.now(),
                      );
                      if (escolhida != null)
                        setState(() => dataNascimento = escolhida);
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      if (nomeController.text.trim().isEmpty) return;
                      await DependentesService.adicionar(
                        motoristaId: motoristaId,
                        nome: nomeController.text.trim(),
                        parentesco: parentescoController.text.trim().isEmpty
                            ? null
                            : parentescoController.text.trim(),
                        dataNascimento: dataNascimento,
                      );
                      ref.invalidate(dependentesProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Salvar'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
