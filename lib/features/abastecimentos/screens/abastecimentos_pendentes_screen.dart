import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/abastecimentos_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../gamificacao/providers/missoes_provider.dart';

final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

// Tela "Abastecimentos pendentes" — mecanismo de vínculo do MVP (ver
// PROPOSTA-FIDELIDADE-MOTORISTA.md, seção 2): motorista revisa os
// abastecimentos recentes do veículo vinculado a ele e confirma "Fui eu"
// (credita pontos) ou rejeita (some da lista, não pontua).
class AbastecimentosPendentesScreen extends ConsumerWidget {
  const AbastecimentosPendentesScreen({super.key});

  Future<void> _confirmar(BuildContext context, WidgetRef ref, AbastecimentoPendente item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resultado = await AbastecimentoFidelidadeService.confirmar(item);
      if (resultado.status == 'confirmado') {
        messenger.showSnackBar(SnackBar(content: Text('Confirmado! +${resultado.pontos} pontos.')));
        // Confirmar pode ter destravado uma missão (ex.: "primeira
        // confirmação") — reavalia na hora pra creditar o bônus já.
        await AsyncValue.guard(() => ref.read(missoesProvider.future));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Esse abastecimento não pôde ser confirmado (já foi confirmado ou não é mais seu).')));
      }
      ref.invalidate(abastecimentosPendentesProvider);
      ref.invalidate(saldoPontosProvider);
      ref.invalidate(missoesProvider);
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Não consegui confirmar agora. Tente de novo em instantes.')));
    }
  }

  Future<void> _rejeitar(BuildContext context, WidgetRef ref, AbastecimentoPendente item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AbastecimentoFidelidadeService.rejeitar(item);
      ref.invalidate(abastecimentosPendentesProvider);
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Não consegui registrar agora. Tente de novo em instantes.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendentesAsync = ref.watch(abastecimentosPendentesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Abastecimentos pendentes')),
      body: pendentesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não consegui carregar seus abastecimentos agora.'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.invalidate(abastecimentosPendentesProvider),
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
                  'Nenhum abastecimento pendente de confirmação nos últimos 15 dias.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(abastecimentosPendentesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: itens.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final item = itens[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item.placa, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(_formatoData.format(item.dataAbastecimento)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (item.postoNome != null) Text(item.postoNome!),
                        if (item.municipio != null) Text('${item.municipio}${item.uf != null ? '/${item.uf}' : ''}', style: const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (item.litros != null) Text('${item.litros!.toStringAsFixed(2)} L'),
                            if (item.valorTotal != null)
                              Text(_formatoMoeda.format(item.valorTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _rejeitar(context, ref, item),
                                child: const Text('Não fui eu'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _confirmar(context, ref, item),
                                child: const Text('Fui eu'),
                              ),
                            ),
                          ],
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
