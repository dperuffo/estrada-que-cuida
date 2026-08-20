import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Ranking só entre motoristas da MESMA empresa (decisão do Daniel) — a
// RPC no banco já garante esse recorte (não dá pra fazer isso com RLS
// normal, porque precisamos enxergar linhas de outros motoristas).
class ItemRanking {
  final int posicao;
  final String motoristaId;
  final String nome;
  final int pontos;
  final bool voce;

  ItemRanking({
    required this.posicao,
    required this.motoristaId,
    required this.nome,
    required this.pontos,
    required this.voce,
  });

  factory ItemRanking.fromJson(Map<String, dynamic> json) {
    return ItemRanking(
      posicao: json['posicao'] as int,
      motoristaId: json['motorista_id'] as String,
      nome: json['nome'] as String,
      pontos: json['pontos'] as int,
      voce: json['voce'] as bool,
    );
  }
}

class ResultadoRanking {
  final List<ItemRanking> itens;
  final int? minhaPosicao;

  ResultadoRanking({required this.itens, required this.minhaPosicao});
}

/// `periodo`: 'semana' (últimos 7 dias) ou 'mes' (últimos 30 dias).
final rankingProvider = FutureProvider.autoDispose
    .family<ResultadoRanking, String>((ref, periodo) async {
      final resp = await SupabaseService.client.rpc(
        'ranking_motoristas_empresa',
        params: {'p_periodo': periodo},
      );
      final json = resp as Map<String, dynamic>;
      final lista = (json['ranking'] as List? ?? [])
          .map((e) => ItemRanking.fromJson(e as Map<String, dynamic>))
          .toList();
      return ResultadoRanking(
        itens: lista,
        minhaPosicao: json['minha_posicao'] as int?,
      );
    });
