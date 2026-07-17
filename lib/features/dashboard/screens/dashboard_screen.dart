import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../abastecimentos/providers/abastecimentos_provider.dart';
import '../../gamificacao/providers/missoes_provider.dart';
import '../providers/dashboard_provider.dart';

final _formatoPontos = NumberFormat.decimalPattern('pt_BR');

// Fase Home-interativa — pedido do Daniel (17/07): os botões que
// duplicavam o menu lateral saíram daqui (já dá pra chegar em todo lugar
// pelo Drawer). No lugar, a Home virou um resumo do que importa agora:
// nível/progresso, sugestões do momento (abastecimento parado pra
// confirmar, missão quase concluída) e as missões em si, com barra de
// progresso — sem precisar entrar em mais nenhuma tela pra saber "o que
// falta".
class DashboardScreen extends ConsumerWidget {
  final String motoristaId;
  final String? nome;

  const DashboardScreen({super.key, required this.motoristaId, this.nome});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primeiroNome = (nome ?? '').split(' ').first;
    final saldoAsync = ref.watch(saldoPontosProvider);
    final missoesAsync = ref.watch(missoesProvider);
    final pendentesAsync = ref.watch(abastecimentosPendentesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Estrada que Cuida')),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(saldoPontosProvider);
          ref.invalidate(missoesProvider);
          ref.invalidate(abastecimentosPendentesProvider);
        },
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

            // Sugestões — cartões dinâmicos, só aparecem quando fazem
            // sentido pro motorista agora (nada de espaço vazio "avisando
            // que não há nada a avisar").
            ...pendentesAsync.maybeWhen(
              data: (pendentes) => pendentes.isEmpty
                  ? []
                  : [
                      const SizedBox(height: 20),
                      _CartaoSugestao(
                        icone: Icons.local_gas_station,
                        cor: const Color(0xFF1E6FBF),
                        titulo: pendentes.length == 1
                            ? '1 abastecimento esperando confirmação'
                            : '${pendentes.length} abastecimentos esperando confirmação',
                        subtitulo: 'Confirme pra não perder os pontos deles.',
                        onTap: () => context.push('/pendentes'),
                      ),
                    ],
              orElse: () => [],
            ),

            const SizedBox(height: 28),
            const Text('Suas missões', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            const Text(
              'Complete missões pra ganhar pontos bônus, além dos pontos normais de cada abastecimento.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            missoesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
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
              data: (missoes) => _BlocoMissoes(missoes: missoes),
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

// Cartão de sugestão genérico — usado tanto pra "abastecimento parado"
// quanto pra qualquer outra dica futura que dependa de dado do momento
// (não é fixo, cada instância decide se aparece ou não).
class _CartaoSugestao extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _CartaoSugestao({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: cor.withValues(alpha: 0.08),
      margin: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icone, color: cor, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(subtitulo, style: const TextStyle(color: Colors.black54, fontSize: 13)),
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

// Mostra até 3 missões — as ainda não concluídas primeiro (mais perto de
// bater a meta primeiro, pra dar aquele empurrão), concluídas por
// último. Se tiver mais que isso, um link leva pra lista completa.
class _BlocoMissoes extends StatelessWidget {
  final List<MissaoProgresso> missoes;

  const _BlocoMissoes({required this.missoes});

  @override
  Widget build(BuildContext context) {
    if (missoes.isEmpty) {
      return const Text('Nenhuma missão disponível no momento.', style: TextStyle(color: Colors.black45));
    }

    final pendentes = missoes.where((m) => !m.concluida).toList()
      ..sort((a, b) {
        final progA = a.meta == 0 ? 0.0 : a.progresso / a.meta;
        final progB = b.meta == 0 ? 0.0 : b.progresso / b.meta;
        return progB.compareTo(progA); // mais perto de concluir primeiro
      });
    final concluidas = missoes.where((m) => m.concluida).toList();
    final ordenadas = [...pendentes, ...concluidas];
    final destaque = ordenadas.take(3).toList();
    final temMais = missoes.length > destaque.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...destaque.map((m) => _CartaoMissao(missao: m)),
        if (temMais) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => context.push('/missoes'),
            child: const Text('Ver todas as missões'),
          ),
        ],
      ],
    );
  }
}

class _CartaoMissao extends StatelessWidget {
  final MissaoProgresso missao;

  const _CartaoMissao({required this.missao});

  @override
  Widget build(BuildContext context) {
    final progresso = missao.meta == 0 ? 0.0 : missao.progresso / missao.meta;
    final cor = missao.concluida ? const Color(0xFF1B7A43) : const Color(0xFF1E6FBF);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(missao.iconeData, color: missao.concluida ? cor : Colors.black38, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(missao.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (!missao.concluida) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progresso.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: const Color(0xFFE5E5E0),
                        valueColor: AlwaysStoppedAnimation(cor),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Faltam ${(missao.meta - missao.progresso).clamp(0, missao.meta)} — +${missao.bonus} pontos ao concluir',
                      style: const TextStyle(color: Colors.black54, fontSize: 12.5),
                    ),
                  ] else
                    Text(
                      'Concluída — +${missao.bonus} pontos',
                      style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
