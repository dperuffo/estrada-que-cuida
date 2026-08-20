import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'motorista_provider.dart';
import '../services/supabase_service.dart';

// Fase Central-Avisos (28/07/2026) — pedido do Daniel: "Central de Avisos é
// uma funcionalidade do admin da aplicação para os clientes, motoristas e
// postos". Port 1:1 da lógica de `listarAvisosAcao` (web) e do
// avisos_provider.dart do estudo-de-rede/flutter (cliente/posto), adaptado
// pra este app: motorista não tem e-mail (login por telefone/OTP), então a
// identidade usada como `usuario_email` é o telefone da sessão — mesmo
// padrão já usado em `tickets.user_email`/`ticket_comentarios.autor_email`
// (ver chamados_service.dart), e a RLS de `comunicados_leituras` foi
// ajustada pra aceitar e-mail OU telefone (coalesce no auth.jwt()).
class AvisoUsuario {
  final String id;
  final String tipo;
  final String urgencia;
  final String titulo;
  final String resumo;
  final String corpo;
  final String? imagemPath;
  final bool fixado;
  final String dataPublicacao;
  final String? dataExpiracao;
  final bool lido;

  const AvisoUsuario({
    required this.id,
    required this.tipo,
    required this.urgencia,
    required this.titulo,
    required this.resumo,
    required this.corpo,
    required this.imagemPath,
    required this.fixado,
    required this.dataPublicacao,
    required this.dataExpiracao,
    required this.lido,
  });

  String? get urlImagem {
    if (imagemPath == null || imagemPath!.isEmpty) return null;
    return '${SupabaseService.supabaseUrl}/storage/v1/object/public/comunicados-imagens/$imagemPath';
  }
}

// Identidade usada nas linhas de `comunicados_leituras` — telefone da
// sessão Supabase (o mesmo valor que vai no claim `phone` do JWT, então bate
// com a política de RLS `coalesce(auth.jwt()->>'email', auth.jwt()->>'phone')`).
String? _identidadeAtual() => SupabaseService.client.auth.currentUser?.phone;

final avisosProvider = FutureProvider.autoDispose<List<AvisoUsuario>>((
  ref,
) async {
  final identidade = _identidadeAtual();
  if (identidade == null || identidade.isEmpty) return [];

  final perfil = await ref.watch(meuPerfilProvider.future);
  final supabase = SupabaseService.client;

  final agora = DateTime.now().toUtc().toIso8601String();
  final linhas =
      await supabase
              .from('comunicados')
              .select(
                'id, tipo, urgencia, titulo, resumo, corpo, imagem_path, segmentos_alvo, planos_alvo, empresas_alvo, fixado, data_publicacao, data_expiracao',
              )
              .eq('ativo', true)
              .lte('data_publicacao', agora)
              .or('data_expiracao.is.null,data_expiracao.gte.$agora')
              .order('fixado', ascending: false)
              .order('data_publicacao', ascending: false)
          as List;

  if (linhas.isEmpty) return [];

  // Motorista está sempre ligado a UMA empresa (segmento sempre 'Frota') —
  // resolve segmento/plano dela pra segmentação, mesma ideia do
  // estudo-de-rede/flutter (lá com `sessao.empresasIds`, aqui com
  // `perfil.empresaId` só).
  var segmentosUsuario = <String>{};
  var planosUsuario = <String>{};
  final idsEmpresa = <String>[
    if (perfil?.empresaId != null) perfil!.empresaId!,
  ];
  if (idsEmpresa.isNotEmpty) {
    final empresasData =
        await supabase
                .from('empresas')
                .select('id, segmento, plano')
                .inFilter('id', idsEmpresa)
            as List;
    for (final e in empresasData) {
      final m = e as Map<String, dynamic>;
      final seg = m['segmento'] as String?;
      final plano = m['plano'] as String?;
      if (seg != null) segmentosUsuario.add(seg);
      if (plano != null) planosUsuario.add(plano);
    }
  }

  final visiveis = linhas.where((l) {
    final m = l as Map<String, dynamic>;
    final segmentosAlvo = ((m['segmentos_alvo'] as List?) ?? []).cast<String>();
    final planosAlvo = ((m['planos_alvo'] as List?) ?? []).cast<String>();
    final empresasAlvo = ((m['empresas_alvo'] as List?) ?? []).cast<String>();
    final segOk =
        segmentosAlvo.isEmpty || segmentosAlvo.any(segmentosUsuario.contains);
    final planoOk =
        planosAlvo.isEmpty || planosAlvo.any(planosUsuario.contains);
    final empresaOk =
        empresasAlvo.isEmpty || empresasAlvo.any(idsEmpresa.contains);
    return segOk && planoOk && empresaOk;
  }).toList();

  final leituras =
      await supabase
              .from('comunicados_leituras')
              .select('comunicado_id')
              .eq('usuario_email', identidade)
          as List;
  final lidosSet = leituras
      .map((l) => (l as Map<String, dynamic>)['comunicado_id'] as String)
      .toSet();

  return visiveis.map((l) {
    final m = l as Map<String, dynamic>;
    final id = m['id'] as String;
    return AvisoUsuario(
      id: id,
      tipo: m['tipo'] as String,
      urgencia: m['urgencia'] as String,
      titulo: m['titulo'] as String,
      resumo: m['resumo'] as String,
      corpo: m['corpo'] as String,
      imagemPath: m['imagem_path'] as String?,
      fixado: m['fixado'] as bool,
      dataPublicacao: m['data_publicacao'] as String,
      dataExpiracao: m['data_expiracao'] as String?,
      lido: lidosSet.contains(id),
    );
  }).toList();
});

final avisosNaoLidosProvider = Provider.autoDispose<int>((ref) {
  final avisos = ref.watch(avisosProvider).valueOrNull ?? const [];
  return avisos.where((a) => !a.lido).length;
});

Future<void> marcarAvisoLido(WidgetRef ref, String comunicadoId) async {
  final identidade = _identidadeAtual();
  if (identidade == null || identidade.isEmpty) return;
  try {
    await SupabaseService.client
        .from('comunicados_leituras')
        .upsert(
          {'comunicado_id': comunicadoId, 'usuario_email': identidade},
          onConflict: 'comunicado_id,usuario_email',
          ignoreDuplicates: true,
        );
  } catch (_) {
    // Best-effort — mesmo espírito das demais gravações "silenciosas" do app.
  }
  ref.invalidate(avisosProvider);
}
