import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/motorista_provider.dart';
import '../../../core/services/supabase_service.dart';

// Fase avaliação-motorista — porta de avaliacoes_provider.dart do
// estudo-de-rede/flutter, adaptado pra sessão por telefone (RLS
// `avaliacoes_motorista`, ver migração chamados_e_avaliacao_motorista).
class Avaliacao {
  final String id;
  final int estrelas;
  final String? comentario;
  final String? respostaAdmin;
  final String? criadoEm;

  const Avaliacao({
    required this.id,
    required this.estrelas,
    required this.comentario,
    required this.respostaAdmin,
    required this.criadoEm,
  });

  factory Avaliacao.fromMap(Map<String, dynamic> m) => Avaliacao(
    id: m['id'] as String,
    estrelas: (m['estrelas'] as num).toInt(),
    comentario: m['comentario'] as String?,
    respostaAdmin: m['resposta_admin'] as String?,
    criadoEm: m['criado_em'] as String?,
  );
}

String rotuloNota(int estrelas) {
  if (estrelas >= 5) return 'Excelente';
  if (estrelas == 4) return 'Muito boa';
  if (estrelas == 3) return 'Razoável';
  if (estrelas == 2) return 'Ruim';
  return 'Muito ruim';
}

final minhasAvaliacoesProvider = FutureProvider.autoDispose<List<Avaliacao>>((
  ref,
) async {
  final perfil = await ref.watch(meuPerfilProvider.future);
  if (perfil == null) return [];
  final rows = await SupabaseService.client
      .from('avaliacoes')
      .select('id, estrelas, comentario, resposta_admin, criado_em')
      .eq('motorista_id', perfil.id)
      .order('criado_em', ascending: false);
  return (rows as List)
      .map((m) => Avaliacao.fromMap(m as Map<String, dynamic>))
      .toList();
});
