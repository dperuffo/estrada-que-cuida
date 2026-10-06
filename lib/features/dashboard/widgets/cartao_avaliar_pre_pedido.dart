import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pre_pedido_provider.dart';

// Abastecimento via Pré-Pedido concluído pelo caixa: leva o motorista à mesma
// tela de avaliação da jornada "Abastecer" (posto, abastecimento e
// frentista/caixa). Abre sozinha UMA vez por abastecimento (por sessão do app);
// se ele escolher "Agora não", o cartão continua na Home por até 24 h.
final Set<int> _abertosAutomaticamente = <int>{};

class CartaoAvaliarPrePedido extends ConsumerWidget {
  const CartaoAvaliarPrePedido({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(avaliacaoPrePedidoPendenteProvider).valueOrNull;
    final dispensadas = ref.watch(avaliacoesDispensadasProvider);
    if (item == null || dispensadas.contains(item.id)) return const SizedBox.shrink();

    if (_abertosAutomaticamente.add(item.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.push('/abastecimento-pdv/avaliar/${item.id}');
      });
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rate_rounded, color: AppTheme.accento, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Abastecimento concluído!',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Avalie o posto${item.postoNome != null ? ' ${item.postoNome}' : ''}, o abastecimento e o atendimento do frentista/caixa.',
                style: TextStyle(color: AppTheme.glassTextoMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => context.push('/abastecimento-pdv/avaliar/${item.id}'),
                      child: const Text('Avaliar agora'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => ref.read(avaliacoesDispensadasProvider.notifier).update((s) => {...s, item.id}),
                    child: const Text('Dispensar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
