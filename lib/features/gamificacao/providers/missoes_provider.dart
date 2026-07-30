import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Fase 17/07-4 — pedido do Daniel: "quero que o cliente tenha uma tela para
// criar mais missões". Missões deixaram de ser um catálogo fixo no app —
// agora vêm inteiras (título, descrição, ícone, meta, progresso) da RPC
// avaliar_missoes_motorista(), que lê da tabela fidelidade_missoes (missões
// globais do produto + as que a empresa do motorista cadastrou em Gestão de
// Frotas). O app só precisa saber traduzir a CHAVE do ícone (texto) pra um
// IconData de verdade — o catálogo de chaves disponíveis é o mesmo exposto
// no formulário de criação da tela web.
class MissaoProgresso {
  final String codigo;
  final String titulo;
  final String descricao;
  final String icone;
  final int progresso;
  final int meta;
  final bool concluida;
  final int bonus;

  MissaoProgresso({
    required this.codigo,
    required this.titulo,
    required this.descricao,
    required this.icone,
    required this.progresso,
    required this.meta,
    required this.concluida,
    required this.bonus,
  });

  factory MissaoProgresso.fromJson(Map<String, dynamic> json) {
    return MissaoProgresso(
      codigo: json['codigo'] as String,
      titulo: (json['titulo'] as String?) ?? json['codigo'] as String,
      descricao: (json['descricao'] as String?) ?? '',
      icone: (json['icone'] as String?) ?? 'flag_outlined',
      progresso: (json['progresso'] as num).round(),
      meta: (json['meta'] as num).round(),
      concluida: json['concluida'] as bool,
      bonus: (json['bonus'] as num).round(),
    );
  }

  IconData get iconeData => iconesMissao[icone] ?? Icons.flag_outlined;
}

/// Catálogo fixo de ícones disponíveis pra uma missão — mesma lista de
/// chaves oferecida no seletor de ícone da tela de criação em Gestão de
/// Frotas (src/app/(dashboard)/fidelidade/missoes). Chave desconhecida (ex:
/// digitada direto no banco) cai no ícone padrão (flag_outlined).
const Map<String, IconData> iconesMissao = {
  'emoji_flags_outlined': Icons.emoji_flags_outlined,
  'local_gas_station_outlined': Icons.local_gas_station_outlined,
  'calendar_month_outlined': Icons.calendar_month_outlined,
  'local_fire_department_outlined': Icons.local_fire_department_outlined,
  'local_shipping_outlined': Icons.local_shipping_outlined,
  'star_outline': Icons.star_outline,
  'card_giftcard_outlined': Icons.card_giftcard_outlined,
  'security': Icons.security,
  'family_restroom': Icons.family_restroom,
  'alt_route': Icons.alt_route,
  'emoji_events_outlined': Icons.emoji_events_outlined,
  'thumb_up_outlined': Icons.thumb_up_outlined,
  'verified_outlined': Icons.verified_outlined,
  'route_outlined': Icons.route_outlined,
  'groups_outlined': Icons.groups_outlined,
  'payments_outlined': Icons.payments_outlined,
  'military_tech_outlined': Icons.military_tech_outlined,
  'flag_outlined': Icons.flag_outlined,
  // Fase Inspeção-pelo-Motorista (30/07/2026) — missões "Primeira Inspeção"
  // e "Hábito de Cuidado" (fidelidade_missoes.tipo_metrica =
  // 'inspecoes_realizadas').
  'fact_check_outlined': Icons.fact_check_outlined,
};

// Chama a RPC que avalia todas as missões ativas (globais + da empresa do
// motorista), credita bônus pra qualquer uma recém-concluída, e devolve o
// progresso de todas já com o conteúdo pronto pra exibir.
final missoesProvider = FutureProvider.autoDispose<List<MissaoProgresso>>((ref) async {
  final resp = await SupabaseService.client.rpc('avaliar_missoes_motorista');
  final json = resp as Map<String, dynamic>;
  final lista = (json['missoes'] as List? ?? [])
      .map((e) => MissaoProgresso.fromJson(e as Map<String, dynamic>))
      .toList();
  return lista;
});
