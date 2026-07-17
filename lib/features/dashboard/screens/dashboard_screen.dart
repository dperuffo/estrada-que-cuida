import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';

final _formatoPontos = NumberFormat.decimalPattern('pt_BR');

class DashboardScreen extends ConsumerWidget {
  final String motoristaId;
  final String? nome;

  const DashboardScreen({super.key, required this.motoristaId, this.nome});

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
            const SizedBox(height: 16),
            _CartaoVoltePraCasa(onTap: () => context.push('/catalogo', extra: 'volte_para_casa')),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/pendentes'),
              icon: const Icon(Icons.local_gas_station),
              label: const Text('Confirmar abastecimentos'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/catalogo'),
              icon: const Icon(Icons.card_giftcard_outlined),
              label: const Text('Catálogo de benefícios'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/extrato'),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Extrato de pontos'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/missoes'),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Missões'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/ranking'),
                    icon: const Icon(Icons.leaderboard_outlined),
                    label: const Text('Ranking'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/dependentes', extra: motoristaId),
              icon: const Icon(Icons.family_restroom_outlined),
              label: const Text('Conta Família'),
            ),
          ],
        ),
      ),
    );
  }
}

// Atalho de destaque — pilar "Volte para Casa" do programa: se o
// motorista está cansado e precisa de ajuda pra voltar com segurança, o
// benefício está a 1 toque, sem precisar navegar pelo catálogo inteiro.
class _CartaoVoltePraCasa extends StatelessWidget {
  final VoidCallback onTap;

  const _CartaoVoltePraCasa({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFEAF5EE),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.home_outlined, color: Color(0xFF1B7A43), size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cansado na estrada?', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Veja os benefícios de Volte para Casa.', style: TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
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
