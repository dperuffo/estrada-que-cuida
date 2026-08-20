import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_drawer.dart';
import '../providers/financeiro_provider.dart';

// Fase Financeiro-Motorista (pedido do Daniel, 19/07): tela nova pro
// motorista ver, num só lugar, o dinheiro do frete — quanto o cliente
// depositou de saldo de combustível, quanto já foi consumido em
// abastecimentos, quanto o cliente pagou de frete (adiantamento/saldo
// final) e quanto ainda falta. Saldo de frete concluído continua valendo
// pra abastecimento futuro de uso pessoal (RPC motorista_financeiro_resumo
// já resolve isso, ver migração fretes_saldo_combustivel_sobrevive_conclusao).

final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _formatoNumero = NumberFormat.decimalPattern('pt_BR');
final _formatoData = DateFormat('dd/MM/yyyy');

const _nomesStatusFrete = {
  'aceito': 'Aceito',
  'em_andamento': 'Em andamento',
  'concluido': 'Concluído',
};

const _corStatusFrete = {
  'aceito': AppTheme.frota600,
  'em_andamento': AppTheme.statusAtivo,
  'concluido': Colors.black45,
};

class FinanceiroScreen extends ConsumerWidget {
  const FinanceiroScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumoAsync = ref.watch(financeiroResumoProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Financeiro'),
      ),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(financeiroResumoProvider),
        child: resumoAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 40),
              const Text(
                'Não consegui carregar seu Financeiro agora.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton(
                  onPressed: () => ref.invalidate(financeiroResumoProvider),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(160, 44),
                  ),
                  child: const Text('Tentar de novo'),
                ),
              ),
            ],
          ),
          data: (resumo) {
            if (resumo == null || resumo.status != 'ok') {
              return ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  SizedBox(height: 60),
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 48,
                    color: Colors.black26,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Ainda não há informações financeiras de frete pra mostrar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              );
            }

            final semCombustivel = resumo.fretesCombustivel.isEmpty;
            final semPagamentos = resumo.pagamentos.isEmpty;

            if (semCombustivel && semPagamentos) {
              return ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  SizedBox(height: 60),
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 48,
                    color: Colors.black26,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Você ainda não tem frete com saldo de combustível ou pagamento registrado.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!semPagamentos) ...[
                  const Text(
                    'Pagamentos de frete',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'O que o cliente já pagou e o que ainda falta pagar de cada frete.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _CartaoTotal(
                        rotulo: 'Recebido',
                        valor: _formatoMoeda.format(resumo.totalRecebido),
                        cor: const Color(0xFF1B7A43),
                        icone: Icons.check_circle_outline,
                      ),
                      const SizedBox(width: 12),
                      _CartaoTotal(
                        rotulo: 'Pendente',
                        valor: _formatoMoeda.format(resumo.totalPendente),
                        cor: const Color(0xFFC97A00),
                        icone: Icons.schedule_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...resumo.pagamentos.map(
                    (p) => _CartaoPagamento(pagamento: p),
                  ),
                  const SizedBox(height: 28),
                ],
                if (!semCombustivel) ...[
                  // Fase Financeiro-Motorista-Ajuste (pedido do Daniel: "a
                  // plataforma não é uma carteira digital e nao tem como usar
                  // o saldo de frete dentro do aplicativo pra novos
                  // abastecimentos") — texto reescrito pra não sugerir que
                  // existe um saldo "resgatável": é só o acompanhamento do
                  // orçamento que o cliente reservou por frete, descontado
                  // automaticamente (alocar_abastecimento_saldo) sempre que o
                  // motorista abastece normalmente pela rede/cartão da
                  // empresa — nunca algo que o motorista aciona ou usa
                  // manualmente dentro do app.
                  const Text(
                    'Orçamento de combustível por frete',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Quanto o cliente reservou de orçamento para combustível em cada frete e quanto já foi descontado '
                    'automaticamente nos seus abastecimentos feitos pela rede. Isso não é um saldo em carteira digital — '
                    'é só o acompanhamento de quanto ainda resta do orçamento que o cliente definiu; o desconto acontece '
                    'sozinho, conforme você abastece normalmente.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  if (resumo.totaisValor.depositado > 0)
                    _CartaoTotaisCombustivel(
                      totais: resumo.totaisValor,
                      emVolume: false,
                    ),
                  if (resumo.totaisVolume.depositado > 0) ...[
                    if (resumo.totaisValor.depositado > 0)
                      const SizedBox(height: 10),
                    _CartaoTotaisCombustivel(
                      totais: resumo.totaisVolume,
                      emVolume: true,
                    ),
                  ],
                  const SizedBox(height: 12),
                  ...resumo.fretesCombustivel.map(
                    (f) => _CartaoFreteCombustivel(frete: f),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CartaoTotal extends StatelessWidget {
  final String rotulo;
  final String valor;
  final Color cor;
  final IconData icone;

  const _CartaoTotal({
    required this.rotulo,
    required this.valor,
    required this.cor,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: cor, size: 18),
                const SizedBox(width: 6),
                Text(
                  rotulo,
                  style: TextStyle(
                    color: cor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              valor,
              style: TextStyle(
                color: cor,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoPagamento extends StatelessWidget {
  final PagamentoFrete pagamento;

  const _CartaoPagamento({required this.pagamento});

  @override
  Widget build(BuildContext context) {
    final cor = pagamento.pago
        ? const Color(0xFF1B7A43)
        : const Color(0xFFC97A00);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              pagamento.isAdiantamento
                  ? Icons.arrow_downward
                  : Icons.flag_outlined,
              color: Colors.black45,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pagamento.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${pagamento.isAdiantamento ? 'Adiantamento' : 'Saldo final'} · ${pagamento.percentual.toStringAsFixed(0)}%'
                    '${pagamento.pago && pagamento.pagoEm != null ? ' · pago em ${_formatoData.format(pagamento.pagoEm!)}' : ''}',
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatoMoeda.format(pagamento.valor),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    pagamento.pago ? 'Pago' : 'Pendente',
                    style: TextStyle(
                      color: cor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoTotaisCombustivel extends StatelessWidget {
  final TotaisCombustivel totais;
  final bool emVolume;

  const _CartaoTotaisCombustivel({
    required this.totais,
    required this.emVolume,
  });

  String _formata(double v) =>
      emVolume ? '${_formatoNumero.format(v)} L' : _formatoMoeda.format(v);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3EF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orçamento${emVolume ? ' (litros)' : ''}',
                  style: const TextStyle(color: Colors.black54, fontSize: 11.5),
                ),
                Text(
                  _formata(totais.depositado),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Descontado',
                  style: TextStyle(color: Colors.black54, fontSize: 11.5),
                ),
                Text(
                  _formata(totais.consumido),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Restante',
                  style: TextStyle(color: Colors.black54, fontSize: 11.5),
                ),
                Text(
                  _formata(totais.saldo),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: totais.saldo < 0
                        ? Colors.redAccent
                        : const Color(0xFF1B7A43),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoFreteCombustivel extends StatelessWidget {
  final FreteCombustivel frete;

  const _CartaoFreteCombustivel({required this.frete});

  String _formata(double v) => frete.emVolume
      ? '${_formatoNumero.format(v)} L'
      : _formatoMoeda.format(v);

  @override
  Widget build(BuildContext context) {
    final progresso = frete.depositado <= 0
        ? 0.0
        : (frete.saldo / frete.depositado).clamp(0.0, 1.0);
    final estourou = frete.saldo < 0;
    final cor = estourou
        ? Colors.redAccent
        : progresso < 0.2
        ? const Color(0xFFC97A00)
        : const Color(0xFF1B7A43);
    final corStatus = _corStatusFrete[frete.status] ?? Colors.black45;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    frete.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: corStatus.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _nomesStatusFrete[frete.status] ?? frete.status,
                    style: TextStyle(
                      color: corStatus,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              estourou
                  ? 'Orçamento estourado em ${_formata(frete.saldo.abs())}'
                  : '${_formata(frete.saldo)} restantes do orçamento',
              style: TextStyle(
                color: cor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: estourou ? 1.0 : progresso,
                minHeight: 8,
                backgroundColor: const Color(0xFFE5E5E0),
                valueColor: AlwaysStoppedAnimation(cor),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Orçamento ${_formata(frete.depositado)} · descontado ${_formata(frete.consumido)}',
              style: const TextStyle(color: Colors.black45, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
