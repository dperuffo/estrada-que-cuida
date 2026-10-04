import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/abastecimento_pdv_provider.dart';

// Fase 2 PDV (02/10/2026) — Tela 3 do fluxo: acompanhamento em tempo real.
// Escuta abastecimentos_pdv via Realtime (mesmo mecanismo .stream() já
// usado no chat de frete) até o posto confirmar ou negar — nada de ficar
// dando "puxa pra atualizar": a mudança de status chega sozinha assim
// que o frentista confirma no PDV.
class AbastecimentoPdvAcompanharScreen extends ConsumerWidget {
  final int abastecimentoPdvId;

  const AbastecimentoPdvAcompanharScreen({super.key, required this.abastecimentoPdvId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(statusTransacaoPdvProvider(abastecimentoPdvId));

    // Confirmado e ainda não avaliado → leva o motorista à tela de avaliação.
    ref.listen<AsyncValue<StatusTransacaoPdv>>(statusTransacaoPdvProvider(abastecimentoPdvId), (_, next) {
      final status = next.valueOrNull;
      if (status != null && status.status == 'confirmado' && !status.jaAvaliado) {
        context.pushReplacement('/abastecimento-pdv/avaliar/$abastecimentoPdvId');
      }
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Acompanhar abastecimento'),
      ),
      drawer: const AppDrawer(),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Não consegui acompanhar esse abastecimento agora. Volte e tente de novo.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (status) => _buildConteudo(context, status),
      ),
    );
  }

  Widget _buildConteudo(BuildContext context, StatusTransacaoPdv status) {
    final info = _infoStatus(status);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              Icon(info.icone, size: 64, color: info.cor),
              const SizedBox(height: 16),
              Text(
                info.titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                info.descricao,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.glassTextoMuted),
              ),
            ],
          ),
        ),
        if (status.status == 'aguardando_pdv' && status.codigoAbastecimento != null) ...[
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _linha('Código', status.codigoAbastecimento!),
                  const SizedBox(height: 8),
                  Text(
                    'Mostre o código e o OTP ao frentista (botão voltar). Quando ele confirmar no PDV, o resultado aparece aqui.',
                    style: TextStyle(color: AppTheme.glassTextoMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (status.status == 'confirmado') ...[
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (status.codigoAbastecimento != null)
                    _linha('Código', status.codigoAbastecimento!),
                  if (status.combustivel != null) _linha('Combustível', status.combustivel!),
                  if (status.litros != null) _linha('Litros', '${status.litros!.toStringAsFixed(2)} L'),
                  if (status.precoLitro != null)
                    _linha('Preço por litro', 'R\$ ${status.precoLitro!.toStringAsFixed(3)}'),
                  if (status.formaPagamento != null)
                    _linha('Forma de pagamento', _rotuloFormaPagamento(status.formaPagamento!)),
                  if (status.valorTotalTransacao != null)
                    _linha(
                      'Valor total',
                      'R\$ ${status.valorTotalTransacao!.toStringAsFixed(2)}',
                      destaque: true,
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (status.status != 'aguardando_pdv')
          ElevatedButton(
            onPressed: () => context.go('/'),
            child: const Text('Voltar ao início'),
          ),
      ],
    );
  }

  Widget _linha(String label, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.glassTextoMuted)),
          Text(
            valor,
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
              fontSize: destaque ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }

  String _rotuloFormaPagamento(String forma) {
    const rotulos = {
      'pix': 'Pix',
      'cartao_credito': 'Cartão de crédito',
      'cartao_debito': 'Cartão de débito',
      'dinheiro': 'Dinheiro',
      'profrotas': 'PróFrotas',
      'valecard': 'ValeCard',
      'ticket_log': 'Ticket Log',
      'rede_frota': 'Rede Frota',
      'veloe': 'Veloe',
      'outro': 'Outro',
    };
    return rotulos[forma] ?? forma;
  }

  String _rotuloMotivoNegacao(String? motivo) {
    const rotulos = {
      'forma_pagamento_nao_permitida': 'A forma de pagamento usada não está habilitada para esse veículo.',
      'valor_acima_do_limite_sem_supervisor': 'O valor do abastecimento está acima do limite permitido sem aprovação de um supervisor.',
      'pre_pedido_limite': 'O abastecimento passou do volume ou valor autorizado no seu Pré-Pedido. Ele não foi aceito; abasteça dentro do limite do Pré-Pedido.',
      'regras_cliente':
          'O abastecimento foi negado por regras da sua empresa. O gestor já foi avisado e pode liberar enquanto o pedido estiver válido — esta tela atualiza sozinha.',
    };
    return rotulos[motivo] ?? 'O posto não autorizou esse abastecimento.';
  }

  _InfoStatus _infoStatus(StatusTransacaoPdv status) {
    switch (status.status) {
      case 'confirmado':
        return _InfoStatus(
          icone: Icons.check_circle_outline,
          cor: AppTheme.statusAtivo,
          titulo: 'Abastecimento confirmado!',
          descricao: 'O posto já confirmou seu abastecimento.',
        );
      case 'negado':
        return _InfoStatus(
          icone: Icons.cancel_outlined,
          cor: AppTheme.statusInativo,
          titulo: 'Abastecimento negado',
          descricao: _rotuloMotivoNegacao(status.motivoNegacao),
        );
      case 'expirado':
        return _InfoStatus(
          icone: Icons.timer_off_outlined,
          cor: AppTheme.statusInativo,
          titulo: 'Código expirado',
          descricao: 'O prazo para o posto confirmar esse abastecimento acabou. Inicie de novo se ainda for abastecer.',
        );
      case 'nao_encontrado':
        return const _InfoStatus(
          icone: Icons.error_outline,
          cor: AppTheme.statusInativo,
          titulo: 'Abastecimento não encontrado',
          descricao: 'Não encontrei esse abastecimento.',
        );
      default:
        return const _InfoStatus(
          icone: Icons.hourglass_top_outlined,
          cor: AppTheme.statusAtencao,
          titulo: 'Aguardando confirmação do posto',
          descricao: 'Assim que o frentista confirmar no PDV, esta tela atualiza sozinha.',
        );
    }
  }
}

class _InfoStatus {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String descricao;
  const _InfoStatus({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.descricao,
  });
}
