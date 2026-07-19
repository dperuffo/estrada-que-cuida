import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Fase Financeiro-Motorista (pedido do Daniel, 19/07): tela "Financeiro" no
// PWA pra trazer valores de frete contratado — quanto o cliente depositou de
// saldo de combustível, quanto já foi consumido em abastecimentos, quanto o
// cliente pagou de frete (adiantamento/saldo final) e o saldo que sobra pra
// consumo. Tudo calculado no banco pela RPC `motorista_financeiro_resumo`
// (ver migração fretes_saldo_combustivel_sobrevive_conclusao). Saldo de
// frete concluído continua valendo pra abastecimentos futuros de uso
// pessoal (mesma migração ajustou `alocar_abastecimento_saldo`).

class FreteCombustivel {
  final String freteId;
  final String titulo;
  final String status;
  final String tipo; // 'Valor' | 'Volume'
  final double depositado;
  final double consumido;
  final double saldo;

  const FreteCombustivel({
    required this.freteId,
    required this.titulo,
    required this.status,
    required this.tipo,
    required this.depositado,
    required this.consumido,
    required this.saldo,
  });

  bool get emVolume => tipo == 'Volume';

  factory FreteCombustivel.fromJson(Map<String, dynamic> json) => FreteCombustivel(
        freteId: json['frete_id'] as String,
        titulo: json['titulo'] as String,
        status: json['status'] as String,
        tipo: json['tipo'] as String,
        depositado: (json['depositado'] as num).toDouble(),
        consumido: (json['consumido'] as num).toDouble(),
        saldo: (json['saldo'] as num).toDouble(),
      );
}

class TotaisCombustivel {
  final double depositado;
  final double consumido;
  final double saldo;

  const TotaisCombustivel({required this.depositado, required this.consumido, required this.saldo});

  factory TotaisCombustivel.fromJson(Map<String, dynamic> json) => TotaisCombustivel(
        depositado: (json['depositado'] as num).toDouble(),
        consumido: (json['consumido'] as num).toDouble(),
        saldo: (json['saldo'] as num).toDouble(),
      );
}

class PagamentoFrete {
  final String freteId;
  final String titulo;
  final String tipo; // 'adiantamento' | 'saldo_final'
  final double percentual;
  final double valor;
  final String status; // 'pendente' | 'pago'
  final DateTime? pagoEm;

  const PagamentoFrete({
    required this.freteId,
    required this.titulo,
    required this.tipo,
    required this.percentual,
    required this.valor,
    required this.status,
    this.pagoEm,
  });

  bool get pago => status == 'pago';
  bool get isAdiantamento => tipo == 'adiantamento';

  factory PagamentoFrete.fromJson(Map<String, dynamic> json) => PagamentoFrete(
        freteId: json['frete_id'] as String,
        titulo: json['titulo'] as String,
        tipo: json['tipo'] as String,
        percentual: (json['percentual'] as num).toDouble(),
        valor: (json['valor'] as num).toDouble(),
        status: json['status'] as String,
        pagoEm: json['pago_em'] != null ? DateTime.parse(json['pago_em'] as String) : null,
      );
}

class FinanceiroResumo {
  final String status;
  final List<FreteCombustivel> fretesCombustivel;
  final TotaisCombustivel totaisValor;
  final TotaisCombustivel totaisVolume;
  final List<PagamentoFrete> pagamentos;
  final double totalRecebido;
  final double totalPendente;

  const FinanceiroResumo({
    required this.status,
    required this.fretesCombustivel,
    required this.totaisValor,
    required this.totaisVolume,
    required this.pagamentos,
    required this.totalRecebido,
    required this.totalPendente,
  });

  factory FinanceiroResumo.fromJson(Map<String, dynamic> json) {
    final combustivel = json['combustivel'] as Map<String, dynamic>?;
    final pagamentos = json['pagamentos'] as Map<String, dynamic>?;
    return FinanceiroResumo(
      status: json['status'] as String,
      fretesCombustivel: ((combustivel?['fretes'] as List?) ?? [])
          .map((e) => FreteCombustivel.fromJson(e as Map<String, dynamic>))
          .toList(),
      totaisValor: combustivel?['totais_valor'] != null
          ? TotaisCombustivel.fromJson(combustivel!['totais_valor'] as Map<String, dynamic>)
          : const TotaisCombustivel(depositado: 0, consumido: 0, saldo: 0),
      totaisVolume: combustivel?['totais_volume'] != null
          ? TotaisCombustivel.fromJson(combustivel!['totais_volume'] as Map<String, dynamic>)
          : const TotaisCombustivel(depositado: 0, consumido: 0, saldo: 0),
      pagamentos: ((pagamentos?['itens'] as List?) ?? [])
          .map((e) => PagamentoFrete.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalRecebido: (pagamentos?['total_recebido'] as num? ?? 0).toDouble(),
      totalPendente: (pagamentos?['total_pendente'] as num? ?? 0).toDouble(),
    );
  }
}

final financeiroResumoProvider = FutureProvider.autoDispose<FinanceiroResumo?>((ref) async {
  final resp = await SupabaseService.client.rpc('motorista_financeiro_resumo');
  if (resp == null) return null;
  return FinanceiroResumo.fromJson(resp as Map<String, dynamic>);
});
