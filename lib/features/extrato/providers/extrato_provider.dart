import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// 1 linha = 1 evento do ledger (fidelidade_pontos_ledger) — nunca
// editado, só inserido. RLS já restringe a leitura só ao motorista dono.
class LancamentoPontos {
  final String tipoEvento;
  final int pontos;
  final Map<String, dynamic>? referencia;
  final DateTime criadoEm;

  LancamentoPontos({
    required this.tipoEvento,
    required this.pontos,
    required this.referencia,
    required this.criadoEm,
  });

  factory LancamentoPontos.fromJson(Map<String, dynamic> json) {
    return LancamentoPontos(
      tipoEvento: json['tipo_evento'] as String,
      pontos: json['pontos'] as int,
      referencia: json['referencia'] as Map<String, dynamic>?,
      criadoEm: DateTime.parse(json['criado_em'] as String),
    );
  }
}

final extratoPontosProvider = FutureProvider.autoDispose<List<LancamentoPontos>>((ref) async {
  final rows = await SupabaseService.client
      .from('fidelidade_pontos_ledger')
      .select('tipo_evento, pontos, referencia, criado_em')
      .order('criado_em', ascending: false);
  return (rows as List).map((e) => LancamentoPontos.fromJson(e as Map<String, dynamic>)).toList();
});
