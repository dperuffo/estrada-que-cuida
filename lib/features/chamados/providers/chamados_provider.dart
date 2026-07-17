import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/motorista_provider.dart';
import '../../../core/services/supabase_service.dart';

// Fase chamados-motorista — porta com escopo reduzido (mesmo espírito do
// chamados_provider.dart do estudo-de-rede/flutter: sem anexos nesta
// primeira leva, só o essencial: abrir chamado, ver status/resposta,
// conversar por comentários). RLS aqui é a policy `tickets_motorista` /
// `ticket_comentarios_motorista` (ver migração
// chamados_e_avaliacao_motorista) — só enxerga os chamados vinculados ao
// próprio `motorista_id`.

const tiposTicket = <String, String>{'incidente': 'Incidente', 'melhoria': 'Melhoria'};
const statusTicket = <String, String>{
  'aberto': 'Aberto',
  'em_analise': 'Em análise',
  'resolvido': 'Resolvido',
  'fechado': 'Fechado',
};
const prioridadesTicket = <String, String>{'baixa': 'Baixa', 'media': 'Média', 'alta': 'Alta', 'critica': 'Crítica'};

class Ticket {
  final String id;
  final int numero;
  final String tipo;
  final String titulo;
  final String descricao;
  final String status;
  final String prioridade;
  final String? respostaAdmin;
  final String? criadoEm;
  final String? atualizadoEm;
  final String? usuarioVistoEm;

  const Ticket({
    required this.id,
    required this.numero,
    required this.tipo,
    required this.titulo,
    required this.descricao,
    required this.status,
    required this.prioridade,
    this.respostaAdmin,
    this.criadoEm,
    this.atualizadoEm,
    this.usuarioVistoEm,
  });

  factory Ticket.fromMap(Map<String, dynamic> m) => Ticket(
        id: m['id'].toString(),
        numero: (m['numero'] as num?)?.toInt() ?? 0,
        tipo: m['tipo'] as String? ?? '',
        titulo: m['titulo'] as String? ?? '',
        descricao: m['descricao'] as String? ?? '',
        status: m['status'] as String? ?? 'aberto',
        prioridade: m['prioridade'] as String? ?? 'media',
        respostaAdmin: m['resposta_admin'] as String?,
        criadoEm: m['criado_em'] as String?,
        atualizadoEm: m['atualizado_em'] as String?,
        usuarioVistoEm: m['usuario_visto_em'] as String?,
      );

  bool get naoVisto {
    if (atualizadoEm == null) return false;
    if (usuarioVistoEm == null) return true;
    return DateTime.parse(atualizadoEm!).isAfter(DateTime.parse(usuarioVistoEm!));
  }
}

class TicketComentario {
  final String id;
  final String autorTipo;
  final String texto;
  final String criadoEm;

  const TicketComentario({
    required this.id,
    required this.autorTipo,
    required this.texto,
    required this.criadoEm,
  });

  factory TicketComentario.fromMap(Map<String, dynamic> m) => TicketComentario(
        id: m['id'].toString(),
        autorTipo: m['autor_tipo'] as String? ?? 'usuario',
        texto: m['texto'] as String? ?? '',
        criadoEm: m['criado_em'] as String? ?? '',
      );
}

final meusChamadosProvider = FutureProvider.autoDispose<List<Ticket>>((ref) async {
  final perfil = await ref.watch(meuPerfilProvider.future);
  if (perfil == null) return [];
  final rows = await SupabaseService.client
      .from('tickets')
      .select('id, numero, tipo, titulo, descricao, status, prioridade, resposta_admin, criado_em, atualizado_em, usuario_visto_em')
      .eq('motorista_id', perfil.id)
      .order('criado_em', ascending: false);
  return (rows as List).map((m) => Ticket.fromMap(m as Map<String, dynamic>)).toList();
});

class ChamadoDetalhe {
  final Ticket ticket;
  final List<TicketComentario> comentarios;

  const ChamadoDetalhe({required this.ticket, required this.comentarios});
}

final chamadoDetalheProvider = FutureProvider.autoDispose.family<ChamadoDetalhe?, String>((ref, ticketId) async {
  final supabase = SupabaseService.client;

  final ticketRaw = await supabase
      .from('tickets')
      .select('id, numero, tipo, titulo, descricao, status, prioridade, resposta_admin, criado_em, atualizado_em, usuario_visto_em')
      .eq('id', ticketId)
      .maybeSingle();
  if (ticketRaw == null) return null;

  final comentariosRaw = await supabase
      .from('ticket_comentarios')
      .select('id, autor_tipo, texto, criado_em')
      .eq('ticket_id', ticketId)
      .order('criado_em', ascending: true);
  final comentarios = (comentariosRaw as List).map((m) => TicketComentario.fromMap(m as Map<String, dynamic>)).toList();

  return ChamadoDetalhe(ticket: Ticket.fromMap(ticketRaw), comentarios: comentarios);
});
