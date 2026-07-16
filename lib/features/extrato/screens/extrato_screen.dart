import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/extrato_provider.dart';

final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

String _rotuloEvento(LancamentoPontos item) {
  switch (item.tipoEvento) {
    case 'abastecimento_confirmado':
      final placa = item.referencia?['placa'] as String?;
      return placa != null ? 'Abastecimento confirmado — $placa' : 'Abastecimento confirmado';
    case 'ajuste_manual':
      return 'Ajuste';
    case 'resgate':
      return 'Resgate';
    default:
      return item.tipoEvento;
  }
}

// Extrato de pontos — histórico completo do ledger (ganhos e usos),
// mais recente primeiro. Cada linha é um evento que já aconteceu — o
// ledger nunca é editado, então isto é sempre auditável.
class ExtratoScreen extends ConsumerWidget {
  const ExtratoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extratoAsync = ref.watch(extratoPontosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Extrato de pontos')),
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
                child: Text('Nenhum lançamento ainda. Confirme um abastecimento pra começar a pontuar.', textAlign: TextAlign.center),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(extratoPontosProvider),
            child: ListView.separated(
              itemCount: itens.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = itens[i];
                final positivo = item.pontos >= 0;
                return ListTile(
                  leading: Icon(
                    positivo ? Icons.add_circle_outline : Icons.remove_circle_outline,
                    color: positivo ? const Color(0xFF1B7A43) : Colors.redAccent,
                  ),
                  title: Text(_rotuloEvento(item)),
                  subtitle: Text(_formatoData.format(item.criadoEm)),
                  trailing: Text(
                    '${positivo ? '+' : ''}${item.pontos}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: positivo ? const Color(0xFF1B7A43) : Colors.redAccent,
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
