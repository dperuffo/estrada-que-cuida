import 'dart:math';
import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

// Fretes (Fase Fretes) — contratação de frete entre cliente e motorista.
// Dois modos, ambos na mesma tabela `fretes`:
//   - Direto: motorista_id já vem preenchido, status "aguardando_confirmacao"
//     — só o motorista escolhido (próprio ou parceiro) vê, aceita ou recusa.
//   - Mercado aberto: status "disponivel"; motorista propõe um valor
//     (abrirNegociacaoFrete) e pode receber contraproposta do cliente, até
//     alguém aceitar (aceitarNegociacao) ou recusar. Fase Público-Alvo
//     (23/07/26): visibilidade depende de `publico_alvo` — 'fora_base' só
//     pra motoristas de fora da empresa dona; 'base' só pros próprios
//     (RLS e RPCs no banco garantem; aqui é transparente).
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
  // Fase Fretes-Dados-Completos — pedido do Daniel: motorista precisa de
  // endereço completo, horário e dimensões pra decidir se aceita o frete
  // (origemLabel/destinoLabel acima são só a cidade, pro mapa/km).
  final EnderecoFrete coleta;
  final EnderecoFrete entrega;
  final double? cargaComprimentoM;
  final double? cargaLarguraM;
  final double? cargaAlturaM;
  final List<String> veiculosAceitos;
  final List<String> carroceriasAceitas;
  // Fase Fretes-Público-Alvo (23/07/26) — alvo da solicitação no mercado
  // aberto: 'fora_base' (rede/parceiros) ou 'base' (motoristas próprios da
  // empresa dona). A RLS já garante que só chega aqui o que eu posso ver —
  // este campo é só pra UI sinalizar "exclusivo da sua frota".
  final String publicoAlvo;

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
    required this.coleta,
    required this.entrega,
    this.cargaComprimentoM,
    this.cargaLarguraM,
    this.cargaAlturaM,
    this.veiculosAceitos = const [],
    this.carroceriasAceitas = const [],
    this.publicoAlvo = 'fora_base',
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
        coleta: EnderecoFrete.fromMap(m, 'coleta'),
        entrega: EnderecoFrete.fromMap(m, 'entrega'),
        cargaComprimentoM: (m['carga_comprimento_m'] as num?)?.toDouble(),
        cargaLarguraM: (m['carga_largura_m'] as num?)?.toDouble(),
        cargaAlturaM: (m['carga_altura_m'] as num?)?.toDouble(),
        veiculosAceitos: (m['veiculos_aceitos'] as List?)?.map((v) => v as String).toList() ?? const [],
        carroceriasAceitas: (m['carrocerias_aceitas'] as List?)?.map((v) => v as String).toList() ?? const [],
        publicoAlvo: m['publico_alvo'] as String? ?? 'fora_base',
      );
}

class EnderecoFrete {
  final String? rua;
  final String? numero;
  final String? bairro;
  final String? cidade;
  final String? uf;
  final String? cep;
  final String? referencia;
  final String? data;
  final String? hora;
  final String? contatoNome;
  final String? contatoTelefone;

  const EnderecoFrete({
    this.rua,
    this.numero,
    this.bairro,
    this.cidade,
    this.uf,
    this.cep,
    this.referencia,
    this.data,
    this.hora,
    this.contatoNome,
    this.contatoTelefone,
  });

  bool get preenchido => rua != null || cidade != null;

  String get linhaEndereco {
    final partes = <String>[
      ?(rua != null ? (numero != null ? '$rua, $numero' : rua) : null),
      ?bairro,
      ?(cidade != null ? (uf != null ? '$cidade/$uf' : cidade) : null),
    ];
    return partes.join(' — ');
  }

  factory EnderecoFrete.fromMap(Map<String, dynamic> m, String prefixo) => EnderecoFrete(
        rua: m['${prefixo}_rua'] as String?,
        numero: m['${prefixo}_numero'] as String?,
        bairro: m['${prefixo}_bairro'] as String?,
        cidade: m['${prefixo}_cidade'] as String?,
        uf: m['${prefixo}_uf'] as String?,
        cep: m['${prefixo}_cep'] as String?,
        referencia: m['${prefixo}_referencia'] as String?,
        data: m['${prefixo}_data'] as String?,
        hora: m['${prefixo}_hora'] as String?,
        contatoNome: m['${prefixo}_contato_nome'] as String?,
        contatoTelefone: m['${prefixo}_contato_telefone'] as String?,
      );
}

// Fase Fretes-Dados-Completos — distância em linha reta (haversine) do
// motorista até o ponto de coleta, pra ele decidir se vale a pena aceitar
// antes mesmo de abrir o frete. Mesma fórmula usada na Roteirização.
double distanciaKm(double lat1, double lon1, double lat2, double lon2) {
  const raioTerraKm = 6371.0;
  final dLat = _paraRad(lat2 - lat1);
  final dLon = _paraRad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_paraRad(lat1)) * cos(_paraRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return raioTerraKm * c;
}

double _paraRad(double graus) => graus * (pi / 180);

// Fase Fretes-Dados-Completos — best-effort: se o motorista negar a
// permissão, o navegador não suportar geolocalização, ou o serviço de
// localização estiver desligado no aparelho, simplesmente não mostra a
// distância (não pode travar a lista de fretes por causa disso).
Future<Position?> obterLocalizacaoAtual() async {
  try {
    final servicoAtivo = await Geolocator.isLocationServiceEnabled();
    if (!servicoAtivo) return null;

    var permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    if (permissao == LocationPermission.denied || permissao == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
    );
  } catch (_) {
    return null;
  }
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

// Fase Fretes-Aceitar-Direto-Mercado (19/07) — pedido do Daniel: aceitar o
// valor já anunciado num frete de mercado aberto sem precisar negociar
// primeiro (mesmo espírito de responderFreteDireto, só que pro caso de
// mercado aberto). Primeiro motorista a chamar leva — a RLS/lock no banco
// garante isso (ver aceitar_frete_disponivel).
Future<void> aceitarFreteDisponivel(String freteId) async {
  await SupabaseService.client.rpc('aceitar_frete_disponivel', params: {'p_frete_id': freteId});
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
  // Fase P0.4 — só preenchido quando tipoEvento == 'ocorrencia'.
  final String? codigoOcorrencia;

  const EventoFrete({
    required this.id,
    required this.tipoEvento,
    this.observacao,
    required this.criadoEm,
    this.fotoPath,
    this.codigoOcorrencia,
  });

  factory EventoFrete.fromMap(Map<String, dynamic> m) => EventoFrete(
        id: m['id'] as String,
        tipoEvento: m['tipo_evento'] as String,
        observacao: m['observacao'] as String?,
        criadoEm: DateTime.parse(m['criado_em'] as String),
        fotoPath: m['foto_path'] as String?,
        codigoOcorrencia: m['codigo_ocorrencia'] as String?,
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
  // Fase P0.4 — obrigatório (validado no banco) quando tipoEvento ==
  // 'ocorrencia': atraso, avaria, recusa, reentrega ou devolucao.
  String? codigoOcorrencia,
  // Fase Botao-Panico (02/08/2026) — a RPC já tinha p_lat/p_lon desde
  // sempre (usados por confirmar_entrega_frete), mas essa função nunca os
  // repassava. Só o botão de pânico usa hoje (localização fresca no
  // momento do clique), os outros checkpoints continuam sem lat/lon.
  double? lat,
  double? lon,
}) async {
  await SupabaseService.client.rpc('registrar_evento_frete', params: {
    'p_frete_id': freteId,
    'p_tipo_evento': tipoEvento,
    'p_posto_recomendado_id': postoRecomendadoId,
    'p_observacao': observacao,
    'p_lat': lat,
    'p_lon': lon,
    'p_foto_path': fotoPath,
    'p_codigo_ocorrencia': codigoOcorrencia,
  });
}

// Fase Botao-Panico (02/08/2026, Grupo 1 item 2 do benchmark FNI vs KMM) —
// avisa a operação por e-mail (Edge Function frete-panico-email, best-effort:
// nunca lança — o evento 'panico' já foi salvo em fretes_eventos antes desta
// chamada, então o alerta "existe" no sistema mesmo se o e-mail falhar).
Future<void> dispararAlertaPanicoFrete(String freteId) async {
  try {
    await SupabaseService.client.functions.invoke(
      'frete-panico-email',
      body: {'frete_id': freteId},
    );
  } catch (_) {
    // Best-effort — o evento já está registrado, só o e-mail que pode falhar.
  }
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

// Fase P0.4 — canhoto digital (POD): confirmação de entrega substitui o
// antigo botão "Concluir frete" — agora exige nome do recebedor, foto do
// canhoto e assinatura na tela. A RPC grava fretes_entregas, registra o
// mesmo evento 'concluido' de sempre (mantendo a timeline) e muda o status
// do frete pra 'concluido' (nenhum status novo — mesma máquina de estados
// que o resto do app já lê).

Future<String> enviarAssinaturaEntregaFrete({
  required String freteId,
  required Uint8List bytes,
}) async {
  final caminho = '$freteId/assinatura_${DateTime.now().millisecondsSinceEpoch}.png';
  await SupabaseService.client.storage.from('fretes-evidencias').uploadBinary(
        caminho,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/png'),
      );
  return caminho;
}

// Fase Grupo-1-item-3 (02/08/2026, benchmark FNI vs KMM) — chat simples
// motorista<->operação por frete. Usa o `.stream()` do supabase_flutter
// (Realtime por baixo, já com RLS aplicada) em vez de canal manual — é o
// jeito mais direto de ter atualização ao vivo sem gerenciar subscription
// à mão na tela. Primeira vez que o app usa Realtime.
class MensagemFrete {
  final String id;
  final String remetenteTipo; // 'motorista' | 'empresa'
  final String? remetenteEmail;
  final String mensagem;
  final DateTime criadoEm;

  const MensagemFrete({
    required this.id,
    required this.remetenteTipo,
    this.remetenteEmail,
    required this.mensagem,
    required this.criadoEm,
  });

  factory MensagemFrete.fromMap(Map<String, dynamic> m) => MensagemFrete(
        id: m['id'] as String,
        remetenteTipo: m['remetente_tipo'] as String,
        remetenteEmail: m['remetente_email'] as String?,
        mensagem: m['mensagem'] as String,
        criadoEm: DateTime.parse(m['criado_em'] as String),
      );
}

Stream<List<MensagemFrete>> streamMensagensFrete(String freteId) {
  return SupabaseService.client
      .from('fretes_mensagens')
      .stream(primaryKey: ['id'])
      .eq('frete_id', freteId)
      .order('criado_em')
      .map((linhas) => linhas.map((l) => MensagemFrete.fromMap(l)).toList());
}

// `motoristaId` aqui é o mesmo `frete.motoristaId` já carregado na tela —
// como essa tela só mostra fretes já atribuídos a mim, é sempre o meu
// próprio id de motorista. Evita ter que buscar separadamente.
Future<void> enviarMensagemFrete(String freteId, String motoristaId, String mensagem) async {
  await SupabaseService.client.from('fretes_mensagens').insert({
    'frete_id': freteId,
    'remetente_tipo': 'motorista',
    'remetente_motorista_id': motoristaId,
    'mensagem': mensagem,
  });
}

Future<void> confirmarEntregaFrete(
  String freteId, {
  required String nomeRecebedor,
  String? documentoRecebedor,
  required String fotoCanhotoPath,
  required String assinaturaPath,
  double? lat,
  double? lon,
}) async {
  await SupabaseService.client.rpc('confirmar_entrega_frete', params: {
    'p_frete_id': freteId,
    'p_nome_recebedor': nomeRecebedor,
    'p_foto_canhoto_path': fotoCanhotoPath,
    'p_assinatura_path': assinaturaPath,
    'p_documento_recebedor': documentoRecebedor,
    'p_lat': lat,
    'p_lon': lon,
  });
}
