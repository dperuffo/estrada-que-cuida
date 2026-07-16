import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';

final _formatoPontos = NumberFormat.decimalPattern('pt_BR');

class DashboardScreen extends ConsumerWidget {
  final String? nome;

  const DashboardScreen({super.key, this.nome});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primeiroNome = (nome ?? '').split(' ').first;
    final saldoAsync = ref.watch(saldoPontosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estrada que Cuida'),
        actions: [
          IconButton(onPressed: () => AuthService.sair(), icon: const Icon(Icons.logout), tooltip: 'Sair'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(saldoPontosProvider),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              primeiroNome.isEmpty ? 'Olá!' : 'Olá, $primeiroNome!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            saldoAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Text('Não consegui carregar seu saldo agora.'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(saldoPontosProvider),
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
              data: (saldo) => _CartaoNivel(saldo: saldo),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/pendentes'),
              icon: const Icon(Icons.local_gas_station),
              label: const Text('Confirmar abastecimentos'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoNivel extends StatelessWidget {
  final int saldo;

  const _CartaoNivel({required this.saldo});

  @override
  Widget build(BuildContext context) {
    final nivel = nivelParaSaldo(saldo);
    final proximo = proximoNivel(saldo);
    final progresso = proximo == null ? 1.0 : (saldo - nivel.min) / (proximo.min - nivel.min);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(nivel.icone, color: nivel.cor, size: 32),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nível ${nivel.nome}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${_formatoPontos.format(saldo)} pontos', style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progresso.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: const Color(0xFFE5E5E0),
                valueColor: AlwaysStoppedAnimation(nivel.cor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              proximo == null
                  ? 'Você alcançou o nível máximo — parabéns!'
                  : 'Faltam ${_formatoPontos.format(proximo.min - saldo)} pontos para ${proximo.nome}',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
