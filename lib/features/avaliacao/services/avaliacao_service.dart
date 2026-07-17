import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

// Fase avaliação-motorista — porta de avaliacoes_service.dart. RLS
// (`avaliacoes_motorista`) já garante motorista_id = quem está logado e
// empresa_id nulo ou da própria empresa; aqui só validamos o básico de UX.
class AvaliacoesService {
  Future<String?> enviarAvaliacao({
    required String motoristaId,
    required String telefone,
    String? empresaId,
    required int estrelas,
    String? comentario,
  }) async {
    if (estrelas < 1 || estrelas > 5) return 'Selecione de 1 a 5 estrelas.';

    try {
      await SupabaseService.client.from('avaliacoes').insert({
        'user_email': telefone,
        'motorista_id': motoristaId,
        'empresa_id': empresaId,
        'estrelas': estrelas,
        'comentario': (comentario == null || comentario.trim().isEmpty) ? null : comentario.trim(),
      });
      return null;
    } on PostgrestException catch (e) {
      return 'Não foi possível enviar sua avaliação: ${e.message}';
    }
  }
}
