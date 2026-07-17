import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

// Fretes (Fase Fretes) — contratação de frete entre cliente e motorista.
// Dois modos, ambos na mesma tabela `fretes`:
//   - Direto: motorista_id já vem preenchido, status "aguardando_confirmacao"
//     — só o motorista escolhido (próprio ou parceiro) vê, aceita ou recusa.
//   - Mercado aberto: status "disponivel", visível pra rede toda; motorista
//     propõe um valor (abrirNegociacaoFrete) e pode receber contraproposta
//     do cliente, até alguém aceitar (aceitarNegociacao) ou recusar.
// A RLS já escopa tudo certinho (mercado aberto visível a qualquer
// autenticado; o resto só pro motorista_id dono) — aqui não precisa nem
// saber o próprio motorista_id, só filtrar por status.

class Frete {
  final String id;
  final String titulo;
  final String? descricao;
  final String status;
  final String origemLabel;
  final double origemLat;
  final double origemLon;
  final String destinoLabel;
  final double destinoLat;
  final double destinoLon;
  final String? tipoCarga;
  final double? pesoCargaKg;
  final String? dataSaidaPrevista;
  final String? prazoEntrega;
  final double? kmEstimado;
  final double valorOferecido;
  final String? motoristaId;
  final DateTime criadoEm;

  const Frete({
    required this.id,
    required this.titulo,
    this.descricao,
    required this.status,
    required this.origemLabel,
    required this.origemLat,
    required this.origemLon,
    required this.destinoLabel,
    required this.destinoLat,
    required this.destinoLon,
    this.tipoCarga,
    this.pesoCargaKg,
    this.dataSaidaPrevista,
    this.prazoEntrega,
    this.kmEstimado,
    required this.valorOferecido,
    this.motoristaId,
    required this.criadoEm,
  });

  factory Frete.fromMap(Map<String, dynamic> m) => Frete(
        id: m['id'] as String,
        titulo: m['titulo'] as String,
        descricao: m['descricao'] as String?,
        status: m['status'] as String,
        origemLabel: m['origem_label'] as String,
        origemLat: (m['origem_lat'] as num).toDouble(),
        origemLon: (m['origem_lon'] as num).toDouble(),
        destinoLabel: m['destino_label'] as String,
        destinoLat: (m['destino_lat'] as num).toDouble(),
        destinoLon: (m['destino_lon'] as num).toDouble(),
        tipoCarga: m['tipo_carga'] as String?,
        pesoCargaKg: (m['peso_carga_kg'] as num?)?.toDouble(),
        dataSaidaPrevista: m['data_saida_prevista'] as String?,
        prazoEntrega: m['prazo_entrega'] as String?,
        kmEstimado: (m['km_estimado'] as num?)?.toDouble(),
        valorOferecido: (m['valor_oferecido'] as num).toDouble(),
        motoristaId: m['motorista_id'] as String?,
        criadoEm: DateTime.parse(m['criado_em'] as String),
      );
}

class RodadaNegociacao {
  final int numeroRodada;
  final String autor; // 'cliente' | 'motorista'
  final double valorProposto;
  final String? mensagem;
  final DateTime criadoEm;

  const RodadaNegociacao({
    required this.numeroRodada,
    required this.autor,
    required this.valorProposto,
    this.mensagem,
    required this.criadoEm,
  });

  factory RodadaNegociacao.fromMap(Map<String, dynamic> m) => RodadaNegociacao(
        numeroRodada: m['numero_rodada'] as int,
        autor: m['autor'] as String,
        valorProposto: (m['valor_proposto'] as num).toDouble(),
        mensagem: m['mensagem'] as String?,
        criadoEm: DateTime.parse(m['criado_em'] as String),
      );
}

class Negociacao {
  final String id;
  final String freteId;
  final String status; // aberta | aceita | recusada | retirada | perdida
  final int rodadaAtual;
  final List<RodadaNegociacao> rodadas;

  const Negociacao({
    required this.id,
    required this.freteId,
    required this.status,
    required this.rodadaAtual,
    required this.rodadas,
  });

  RodadaNegociacao? get ultimaRodada => rodadas.isEmpty ? null : rodadas.last;
}

/// Fretes do mercado aberto — visíveis a qualquer motorista da rede.
Future<List<Frete>> buscarFretesMercado() async {
  final linhas = await SupabaseService.client
      .from('fretes')
      .select()
      .eq('status', 'disponivel')
      .order('criado_em', ascending: false);
  return (linhas as List).map((l) => Frete.fromMap(l as Map<String, dynamic>)).toList();
}

/// Fretes atribuídos direto a mim (próprio ou parceiro) ou que eu ganhei
/// numa negociação — qualquer status diferente de "disponivel" que a RLS
/// deixa eu ver só pode ser meu.
Future<List<Frete>> buscarMeusFretesAtribuidos() async {
  final linhas = await SupabaseService.client
      .from('fretes')
      .select()
      .neq('status', 'disponivel')
      .order('criado_em', ascending: false);
  return (linhas as List).map((l) => Frete.fromMap(l as Map<String, dynamic>)).toList();
}

/// Minhas negociações em aberto (mercado aberto), com o frete carregado à
/// parte — pra mostrar "estou negociando o frete X por R$ Y". Evita o
/// embed `fretes(*)` do PostgREST (select('*, fretes(*)')) de propósito:
/// logo depois de criar uma FK nova, o cache de relacionamentos do
/// PostgREST às vezes demora a atualizar e o embed falha com "Could not
/// find a relationship" — duas consultas simples são mais previsíveis.
Future<List<(Negociacao, Frete)>> buscarMinhasNegociacoes() async {
  final linhas = await SupabaseService.client
      .from('fretes_negociacoes')
      .select()
      .order('atualizado_em', ascending: false);

  final negociacoes = (linhas as List).map((l) {
    final mapa = l as Map<String, dynamic>;
    return Negociacao(
      id: mapa['id'] as String,
      freteId: mapa['frete_id'] as String,
      status: mapa['status'] as String,
      rodadaAtual: mapa['rodada_atual'] as int,
      rodadas: const [],
    );
  }).toList();

  if (negociacoes.isEmpty) return [];

  final freteIds = negociacoes.map((n) => n.freteId).toSet().toList();
  final fretesLinhas = await SupabaseService.client.from('fretes').select().inFilter('id', freteIds);
  final fretesPorId = {
    for (final f in (fretesLinhas as List)) (f as Map<String, dynamic>)['id'] as String: Frete.fromMap(f),
  };

  final resultado = <(Negociacao, Frete)>[];
  for (final n in negociacoes) {
    final frete = fretesPorId[n.freteId];
    if (frete != null) resultado.add((n, frete));
  }
  return resultado;
}

/// Busca um frete específico por id (RLS garante que só retorna se eu
/// puder ver: disponível pra rede, ou atribuído/negociado por mim).
Future<Frete?> buscarFrete(String freteId) async {
  final linha = await SupabaseService.client.from('fretes').select().eq('id', freteId).maybeSingle();
  if (linha == null) return null;
  return Frete.fromMap(linha);
}

/// Minha negociação (se existir) pra um frete específico, com as rodadas.
Future<Negociacao?> buscarMinhaNegociacao(String freteId) async {
  final linha = await SupabaseService.client
      .from('fretes_negociacoes')
      .select()
      .eq('frete_id', freteId)
      .maybeSingle();
  if (linha == null) return null;

  final rodadas = await SupabaseService.client
      .from('fretes_negociacoes_rodadas')
      .select()
      .eq('negociacao_id', linha['id'] as String)
      .order('numero_rodada', ascending: true);

  return Negociacao(
    id: linha['id'] as String,
    freteId: linha['frete_id'] as String,
    status: linha['status'] as String,
    rodadaAtual: linha['rodada_atual'] as int,
    rodadas: (rodadas as List).map((r) => RodadaNegociacao.fromMap(r as Map<String, dynamic>)).toList(),
  );
}

Future<void> abrirNegociacaoFrete(String freteId, double valor, {String? mensagem}) async {
  await SupabaseService.client.rpc('abrir_negociacao_frete', params: {
    'p_frete_id': freteId,
    'p_valor_proposto': valor,
    'p_mensagem': mensagem,
  });
}

Future<void> proporRodadaNegociacao(String negociacaoId, double valor, {String? mensagem}) async {
  await SupabaseService.client.rpc('propor_rodada_negociacao', params: {
    'p_negociacao_id': negociacaoId,
    'p_valor_proposto': valor,
    'p_mensagem': mensagem,
  });
}

Future<void> aceitarNegociacaoFrete(String negociacaoId) async {
  await SupabaseService.client.rpc('aceitar_negociacao_frete', params: {'p_negociacao_id': negociacaoId});
}

Future<void> recusarNegociacaoFrete(String negociacaoId) async {
  await SupabaseService.client.rpc('recusar_negociacao_frete', params: {'p_negociacao_id': negociacaoId});
}

Future<void> responderFreteDireto(String freteId, bool aceitar) async {
  await SupabaseService.client.rpc('responder_frete_direto', params: {'p_frete_id': freteId, 'p_aceitar': aceitar});
}

// Fase Fretes B — postos recomendados, checkpoints de execução e avaliação.

class PostoRecomendado {
  final String id;
  final String nomePosto;
  final String? observacao;
  final String? itemCatalogoId;

  const PostoRecomendado({required this.id, required this.nomePosto, this.observacao, this.itemCatalogoId});

  factory PostoRecomendado.fromMap(Map<String, dynamic> m) => PostoRecomendado(
        id: m['id'] as String,
        nomePosto: m['nome_posto'] as String,
        observacao: m['observacao'] as String?,
        itemCatalogoId: m['item_catalogo_id'] as String?,
      );
}

class EventoFrete {
  final String id;
  final String tipoEvento;
  final String? observacao;
  final DateTime criadoEm;
  // Fase foto-evidência-checkpoints — caminho no bucket privado
  // `fretes-evidencias` (não a URL: assinada sob demanda, só quando o
  // cliente/motorista realmente abre a foto).
  final String? fotoPath;

  const EventoFrete({
    required this.id,
    required this.tipoEvento,
    this.observacao,
    required this.criadoEm,
    this.fotoPath,
  });

  factory EventoFrete.fromMap(Map<String, dynamic> m) => EventoFrete(
        id: m['id'] as String,
        tipoEvento: m['tipo_evento'] as String,
        observacao: m['observacao'] as String?,
        criadoEm: DateTime.parse(m['criado_em'] as String),
        fotoPath: m['foto_path'] as String?,
      );
}

class AvaliacaoFrete {
  final String avaliador;
  final int estrelas;
  final String? comentario;

  const AvaliacaoFrete({required this.avaliador, required this.estrelas, this.comentario});

  factory AvaliacaoFrete.fromMap(Map<String, dynamic> m) => AvaliacaoFrete(
        avaliador: m['avaliador'] as String,
        estrelas: m['estrelas'] as int,
        comentario: m['comentario'] as String?,
      );
}

Future<List<PostoRecomendado>> buscarPostosRecomendados(String freteId) async {
  final linhas = await SupabaseService.client
      .from('fretes_postos_recomendados')
      .select()
      .eq('frete_id', freteId)
      .order('ordem', ascending: true);
  return (linhas as List).map((l) => PostoRecomendado.fromMap(l as Map<String, dynamic>)).toList();
}

Future<List<EventoFrete>> buscarEventosFrete(String freteId) async {
  final linhas = await SupabaseService.client
      .from('fretes_eventos')
      .select()
      .eq('frete_id', freteId)
      .order('criado_em', ascending: true);
  return (linhas as List).map((l) => EventoFrete.fromMap(l as Map<String, dynamic>)).toList();
}

Future<List<AvaliacaoFrete>> buscarAvaliacoesFrete(String freteId) async {
  final linhas = await SupabaseService.client.from('fretes_avaliacoes').select().eq('frete_id', freteId);
  return (linhas as List).map((l) => AvaliacaoFrete.fromMap(l as Map<String, dynamic>)).toList();
}

Future<void> registrarEventoFrete(
  String freteId,
  String tipoEvento, {
  String? postoRecomendadoId,
  String? observacao,
  String? fotoPath,
}) async {
  await SupabaseService.client.rpc('registrar_evento_frete', params: {
    'p_frete_id': freteId,
    'p_tipo_evento': tipoEvento,
    'p_posto_recomendado_id': postoRecomendadoId,
    'p_observacao': observacao,
    'p_foto_path': fotoPath,
  });
}

// Fase foto-evidência-checkpoints — sobe a foto ANTES de chamar a RPC
// (que exige p_foto_path pra abasteceu/chegou_destino/concluido/
// ocorrencia — ver migração foto_evidencia_checkpoints_frete). Bucket
// privado: quem vê depois é via signed URL (ver _verFoto na tela).
Future<String> enviarFotoEvidenciaFrete({
  required String freteId,
  required String tipoEvento,
  required Uint8List bytes,
}) async {
  final caminho = '$freteId/${DateTime.now().millisecondsSinceEpoch}_$tipoEvento.jpg';
  await SupabaseService.client.storage.from('fretes-evidencias').uploadBinary(
        caminho,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
  return caminho;
}

Future<void> avaliarFrete(String freteId, int estrelas, {String? comentario}) async {
  await SupabaseService.client.rpc('avaliar_frete', params: {
    'p_frete_id': freteId,
    'p_estrelas': estrelas,
    'p_comentario': comentario,
  });
}
