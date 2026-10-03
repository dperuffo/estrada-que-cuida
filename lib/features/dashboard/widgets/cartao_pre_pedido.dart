import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pre_pedido_provider.dart';

final _moeda = NumberFormat.simpleCurrency(locale: 'pt_BR');

// Cartão da Home com o(s) número(s) de Pré-Pedido que o motorista deve
// informar no posto. Some quando não há Pré-Pedido ativo (parâmetro do
// cliente desligado ou nenhum criado).
class CartaoPrePedido extends ConsumerWidget {
  const CartaoPrePedido({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(prePedidosMotoristaProvider);
    return async.maybeWhen(
      data: (lista) => lista.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [for (final p in lista) _Item(pedido: p)],
              ),
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _Item extends StatelessWidget {
  final PrePedidoMotorista pedido;
  const _Item({required this.pedido});

  String _limite(ParadaPrePedido p) {
    if (p.litros != null) {
      return 'até ${NumberFormat.decimalPattern('pt_BR').format(p.litros)} L';
    }
    if (p.valor != null) return 'até ${_moeda.format(p.valor)}';
    return 'sem limite';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.confirmation_number_outlined,
                    color: AppTheme.accento, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pré-Pedido${pedido.placa != null ? ' · ${pedido.placa}' : ''}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Informe este número no posto para autorizar o abastecimento.',
              style: TextStyle(color: AppTheme.glassTextoMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${pedido.numero}',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: AppTheme.accento,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copiar número',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${pedido.numero}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Número copiado')),
                    );
                  },
                ),
              ],
            ),
            if (pedido.paradas.isNotEmpty) ...[
              const Divider(height: 20),
              for (final p in pedido.paradas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        p.atendido
                            ? Icons.check_circle
                            : Icons.local_gas_station_outlined,
                        size: 16,
                        color: p.atendido
                            ? AppTheme.statusAtivo
                            : AppTheme.glassIcone,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${p.postoNome ?? 'Posto'} — ${_limite(p)}',
                          style: TextStyle(
                            fontSize: 13,
                            decoration:
                                p.atendido ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
