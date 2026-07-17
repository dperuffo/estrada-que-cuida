import '../../../core/services/supabase_service.dart';

// Fase chamados-motorista — porta manual (mesmo aviso já dado em
// outros *_service.dart deste app: não existe RPC pra essa lógica, é
// regra de negócio replicada à mão no Dart, segurança de verdade vem da
// RLS `tickets_motorista`/`ticket_comentarios_motorista`).
class ChamadosService {
  final _supabase = SupabaseService.client;

  Future<String> criarChamado({
    required String empresaId,
    required String motoristaId,
    required String telefone,
    required String tipo,
    required String titulo,
    required String descricao,
    required String prioridade,
  }) async {
    final inserido = await _supabase
        .from('tickets')
        .insert({
          'empresa_id': empresaId,
          'motorista_id': motoristaId,
          'user_email': telefone,
          'tipo': tipo,
          'titulo': titulo,
          'descricao': descricao,
          'prioridade': prioridade,
          'status': 'aberto',
          'usuario_visto_em': DateTime.now().toIso8601String(),
        })
        .select('id')
        .single();
    return inserido['id'].toString();
  }

  Future<void> comentar({required String ticketId, required String telefone, required String texto}) async {
    final textoLimpo = texto.trim();
    if (textoLimpo.isEmpty) throw Exception('Escreva uma mensagem.');

    await _supabase.from('ticket_comentarios').insert({
      'ticket_id': ticketId,
      'autor_email': telefone,
      'autor_tipo': 'usuario',
      'texto': textoLimpo,
    });

    await marcarVisto(ticketId);
  }

  Future<void> marcarVisto(String ticketId) async {
    await _supabase
        .from('tickets')
        .update({'usuario_visto_em': DateTime.now().toIso8601String()}).eq('id', ticketId);
  }
}
