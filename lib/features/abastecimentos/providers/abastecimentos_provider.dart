import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// 1 linha = 1 abastecimento do veículo vinculado ao motorista logado,
// ainda não confirmado nem rejeitado por ele (RPC
// `motorista_abastecimentos_pendentes`, ver migração
// criar_fluxo_confirmacao_abastecimento_fidelidade).
class AbastecimentoPendente {
  final String provedor;
  final String abastecimentoId;
  final String placa;
  final DateTime dataAbastecimento;
  final String? postoNome;
  final String? municipio;
  final String? uf;
  final num? litros;
  final num? valorTotal;
  final String? produto;

  AbastecimentoPendente({
    required this.provedor,
    required this.abastecimentoId,
    required this.placa,
    required this.dataAbastecimento,
    this.postoNome,
    this.municipio,
    this.uf,
    this.litros,
    this.valorTotal,
    this.produto,
  });

  factory AbastecimentoPendente.fromJson(Map<String, dynamic> json) {
    return AbastecimentoPendente(
      provedor: json['provedor'] as String,
      abastecimentoId: json['abastecimento_id'] as String,
      placa: json['placa'] as String,
      dataAbastecimento: DateTime.parse(json['data_abastecimento'] as String),
      postoNome: json['posto_nome'] as String?,
      municipio: json['municipio'] as String?,
      uf: json['uf'] as String?,
      litros: json['litros'] as num?,
      valorTotal: json['valor_total'] as num?,
      produto: json['produto'] as String?,
    );
  }
}

final abastecimentosPendentesProvider = FutureProvider.autoDispose<List<AbastecimentoPendente>>((ref) async {
  final resp = await SupabaseService.client.rpc('motorista_abastecimentos_pendentes');
  return (resp as List).map((e) => AbastecimentoPendente.fromJson(e as Map<String, dynamic>)).toList();
});

class AbastecimentoConfirmacaoResultado {
  final String status;
  final int? pontos;

  AbastecimentoConfirmacaoResultado({required this.status, this.pontos});

  factory AbastecimentoConfirmacaoResultado.fromJson(Map<String, dynamic> json) {
    return AbastecimentoConfirmacaoResultado(
      status: json['status'] as String,
      pontos: json['pontos'] as int?,
    );
  }
}

class AbastecimentoFidelidadeService {
  static Future<AbastecimentoConfirmacaoResultado> confirmar(AbastecimentoPendente item) async {
    final resp = await SupabaseService.client.rpc('confirmar_abastecimento_fidelidade', params: {
      'p_provedor': item.provedor,
      'p_abastecimento_id': item.abastecimentoId,
    });
    return AbastecimentoConfirmacaoResultado.fromJson(resp as Map<String, dynamic>);
  }

  static Future<void> rejeitar(AbastecimentoPendente item) async {
    await SupabaseService.client.rpc('rejeitar_abastecimento_fidelidade', params: {
      'p_provedor': item.provedor,
      'p_abastecimento_id': item.abastecimentoId,
    });
  }
}
