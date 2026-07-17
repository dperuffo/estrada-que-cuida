import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class MissaoProgresso {
  final String codigo;
  final int progresso;
  final int meta;
  final bool concluida;
  final int bonus;

  MissaoProgresso({
    required this.codigo,
    required this.progresso,
    required this.meta,
    required this.concluida,
    required this.bonus,
  });

  factory MissaoProgresso.fromJson(Map<String, dynamic> json) {
    return MissaoProgresso(
      codigo: json['codigo'] as String,
      progresso: json['progresso'] as int,
      meta: json['meta'] as int,
      concluida: json['concluida'] as bool,
      bonus: json['bonus'] as int,
    );
  }
}

// Nome, descrição e ícone de cada missão — só o código vem do banco
// (ver RPC avaliar_missoes_motorista), o resto é conteúdo fixo no app.
class InfoMissao {
  final String titulo;
  final String descricao;
  final IconData icone;

  const InfoMissao({required this.titulo, required this.descricao, required this.icone});
}

const Map<String, InfoMissao> infoMissoes = {
  'primeiro_abastecimento': InfoMissao(
    titulo: 'Primeira confirmação',
    descricao: 'Confirme seu primeiro abastecimento.',
    icone: Icons.emoji_flags_outlined,
  ),
  'cinco_abastecimentos': InfoMissao(
    titulo: 'Rotina em dia',
    descricao: 'Confirme 5 abastecimentos.',
    icone: Icons.local_gas_station_outlined,
  ),
  'trinta_dias_adesao': InfoMissao(
    titulo: '30 dias de estrada',
    descricao: 'Fique 30 dias aderido ao programa.',
    icone: Icons.calendar_month_outlined,
  ),
  'sequencia_7_dias': InfoMissao(
    titulo: 'Sequência de 7 dias',
    descricao: 'Confirme abastecimentos em 7 dias seguidos.',
    icone: Icons.local_fire_department_outlined,
  ),
};

// Chama a RPC que avalia as 4 missões do v1, credita bônus pra
// qualquer uma recém-concluída, e devolve o progresso de todas.
final missoesProvider = FutureProvider.autoDispose<List<MissaoProgresso>>((ref) async {
  final resp = await SupabaseService.client.rpc('avaliar_missoes_motorista');
  final json = resp as Map<String, dynamic>;
  final lista = (json['missoes'] as List? ?? [])
      .map((e) => MissaoProgresso.fromJson(e as Map<String, dynamic>))
      .toList();
  return lista;
});
