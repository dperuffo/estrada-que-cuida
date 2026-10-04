import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pre_pedido_provider.dart';

final _moeda = NumberFormat.simpleCurrency(locale: 'pt_BR');

// Cartão da Home com o OTP do Pré-Pedido: o motorista informa SÓ esse código
// de 6 dígitos no caixa do posto (muda a cada 30 s, calculado no servidor).
// Some quando não há Pré-Pedido ativo (parâmetro do cliente desligado ou
// nenhum criado).
class CartaoPrePedido extends ConsumerWidget {
  const CartaoPrePedido({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(prePedidosMotoristaProvider);
    // valueOrNull: mantém o cartão na tela enquanto o próximo OTP é buscado.
    final lista = async.valueOrNull ?? const <PrePedidoMotorista>[];
    if (lista.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [for (final p in lista) _Item(key: ValueKey(p.placa), pedido: p)],
      ),
    );
  }
}

class _Item extends ConsumerStatefulWidget {
  final PrePedidoMotorista pedido;
  const _Item({super.key, required this.pedido});

  @override
  ConsumerState<_Item> createState() => _ItemState();
}

class _ItemState extends ConsumerState<_Item> {
  late int _restante;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restante = widget.pedido.segundosRestantes;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _restante -= 1);
      // Ao expirar, busca o próximo OTP no servidor.
      if (_restante <= 0) ref.invalidate(prePedidosMotoristaProvider);
    });
  }

  @override
  void didUpdateWidget(covariant _Item old) {
    super.didUpdateWidget(old);
    _restante = widget.pedido.segundosRestantes;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _limite(ParadaPrePedido p) {
    if (p.litros != null) {
      return 'até ${NumberFormat.decimalPattern('pt_BR').format(p.litros)} L';
    }
    if (p.valor != null) return 'até ${_moeda.format(p.valor)}';
    return 'sem limite';
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    final otp = pedido.otp;
    final otpFormatado = '${otp.substring(0, 3)} ${otp.substring(3)}';
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
              'No caixa do posto, informe somente este OTP.',
              style: TextStyle(color: AppTheme.glassTextoMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  otpFormatado,
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: AppTheme.accento,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: (_restante.clamp(0, 30)) / 30,
                        strokeWidth: 3,
                      ),
                      Text('${_restante.clamp(0, 30)}',
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
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
