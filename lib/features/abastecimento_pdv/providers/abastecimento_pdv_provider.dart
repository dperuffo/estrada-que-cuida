import 'dart:convert';
import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/supabase_service.dart';

// Fase 2 PDV (02/10/2026, "Vamos para a fase 2") — fluxo do motorista pra
// abastecer num posto com PDV ativo (revenda). Espelha o padrão de
// abastecimento_interno_provider.dart (RPCs SECURITY DEFINER que resolvem
// tudo a partir do auth.uid() do motorista, devolvendo sempre um campo
// `status` em vez de lançar exceção pra erro de negócio), mas aqui com 3
// passos em vez de 1: (1) escolher a revenda + checar geolocalização
// bloqueante (iniciar_abastecimento_pdv), (2) mostrar código+OTP renovando
// a cada 30s (obter_otp_atual_pdv), (3) acompanhar o status em tempo real
// via Supabase Realtime (mesmo mecanismo .stream() já usado em
// streamMensagensFrete, fretes_provider.dart — único precedente de
// Realtime no app).

// --- Geolocalização bloqueante ---------------------------------------
//
// O único helper existente (fretes_provider.dart/obterLocalizacaoAtual) é
// best-effort (retorna null em qualquer erro, sem distinguir o motivo) e
// usa LocationAccuracy.low — adequado pra "mostrar distância aproximada",
// mas não pro double-check de geofencing, que PRECISA saber por que
// falhou (serviço desligado vs. permissão negada vs. permissão negada
// permanentemente) pra orientar o motorista a corrigir.
class LocalizacaoPdv {
  final double? lat;
  final double? lon;
  final String? erro; // null = sucesso
  const LocalizacaoPdv({this.lat, this.lon, this.erro});
}

Future<LocalizacaoPdv> obterLocalizacaoBloqueantePdv() async {
  try {
    final servicoAtivo = await Geolocator.isLocationServiceEnabled();
    if (!servicoAtivo) {
      return const LocalizacaoPdv(
        erro: 'O GPS do aparelho está desligado. Ative a localização e tente de novo.',
      );
    }

    var permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    if (permissao == LocationPermission.deniedForever) {
      return const LocalizacaoPdv(
        erro: 'A permissão de localização foi negada permanentemente. Libere o acesso à localização nas configurações do app.',
      );
    }
    if (permissao == LocationPermission.denied) {
      return const LocalizacaoPdv(
        erro: 'É preciso permitir o acesso à localização para abastecer pelo PDV.',
      );
    }

    final posicao = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return LocalizacaoPdv(lat: posicao.latitude, lon: posicao.longitude);
  } catch (_) {
    return const LocalizacaoPdv(
      erro: 'Não consegui obter sua localização agora. Tente de novo em instantes.',
    );
  }
}

// --- Passo 1: revendas próximas + início da transação ------------------

class RevendaPdvProxima {
  final String revendaEmpresaId;
  final String nome;
  final String? municipio;
  final String? uf;
  final num distanciaMetros;

  const RevendaPdvProxima({
    required this.revendaEmpresaId,
    required this.nome,
    this.municipio,
    this.uf,
    required this.distanciaMetros,
  });

  factory RevendaPdvProxima.fromJson(Map<String, dynamic> json) {
    return RevendaPdvProxima(
      revendaEmpresaId: json['revenda_empresa_id'] as String,
      nome: json['nome'] as String? ?? 'Posto',
      municipio: json['municipio'] as String?,
      uf: json['uf'] as String?,
      distanciaMetros: (json['distancia_metros'] as num?) ?? 0,
    );
  }
}

final revendasPdvProximasProvider = FutureProvider.autoDispose
    .family<List<RevendaPdvProxima>, ({double lat, double lon})>((
      ref,
      pos,
    ) async {
      final resp = await SupabaseService.client.rpc(
        'buscar_revendas_pdv_proximas',
        params: {'p_lat': pos.lat, 'p_lon': pos.lon},
      );
      return (resp as List? ?? [])
          .map((e) => RevendaPdvProxima.fromJson(e as Map<String, dynamic>))
          .toList();
    });

class ResultadoIniciarPdv {
  final String status;
  final int? id;
  final String? codigoAbastecimento;
  final String? otpAtual;
  final DateTime? otpValidoAteTransacao;
  final num? distanciaMetros;
  final num? raioPermitidoMetros;
  final String? nomeRevenda;
  // Fase 5 PDV — só vem preenchido quando status == 'hodometro_invalido',
  // pra tela mostrar "tem que ser maior que X km".
  final num? ultimoHodometro;

  const ResultadoIniciarPdv({
    required this.status,
    this.id,
    this.codigoAbastecimento,
    this.otpAtual,
    this.otpValidoAteTransacao,
    this.distanciaMetros,
    this.raioPermitidoMetros,
    this.nomeRevenda,
    this.ultimoHodometro,
  });

  factory ResultadoIniciarPdv.fromJson(Map<String, dynamic> json) {
    return ResultadoIniciarPdv(
      status: json['status'] as String,
      id: json['id'] as int?,
      codigoAbastecimento: json['codigoAbastecimento'] as String?,
      otpAtual: json['otpAtual'] as String?,
      otpValidoAteTransacao: json['otpValidoAteTransacao'] != null
          ? DateTime.tryParse(json['otpValidoAteTransacao'] as String)
          : null,
      distanciaMetros: json['distanciaMetros'] as num?,
      raioPermitidoMetros: json['raioPermitidoMetros'] as num?,
      nomeRevenda: json['nomeRevenda'] as String?,
      ultimoHodometro: json['ultimoHodometro'] as num?,
    );
  }
}

// --- Fase 5 PDV: contexto de hodômetro (placa + último registrado) -----
// Consultado pela nova tela de captura de hodômetro ANTES de fotografar,
// só pra mostrar "último hodômetro: X km" como referência — a validação
// de verdade acontece no servidor, dentro de iniciar_abastecimento_pdv
// (ver ResultadoIniciarPdv.ultimoHodometro acima, status hodometro_invalido).
class ContextoHodometroPdv {
  final String status;
  final String? placa;
  final num? ultimoHodometro;

  const ContextoHodometroPdv({required this.status, this.placa, this.ultimoHodometro});

  factory ContextoHodometroPdv.fromJson(Map<String, dynamic> json) {
    return ContextoHodometroPdv(
      status: json['status'] as String,
      placa: json['placa'] as String?,
      ultimoHodometro: json['ultimoHodometro'] as num?,
    );
  }
}

// --- OCR do painel do veículo (hodômetro) -------------------------------
// Mesmo padrão de OcrCupomAbastecimentoService (abastecimento_manual_provider.dart):
// tesseract.js só roda em Node, então a leitura acontece numa rota do site
// (repo Gestão de Frotas), autenticada com o access_token da sessão
// Supabase. Best-effort: o valor lido só pré-preenche o campo — o
// motorista sempre pode corrigir antes de confirmar.
const _baseUrlSitePdv = 'https://fxgestaodefrotasonline.com';

class ResultadoOcrHodometro {
  final String? texto;
  final num? hodometro;
  final String? erro;

  const ResultadoOcrHodometro.ok({this.texto, this.hodometro}) : erro = null;
  const ResultadoOcrHodometro.erro(this.erro) : texto = null, hodometro = null;
}

class OcrHodometroService {
  Future<ResultadoOcrHodometro> lerHodometro(Uint8List bytes) async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    if (token == null) {
      return const ResultadoOcrHodometro.erro('Sessão expirada, faça login novamente.');
    }

    try {
      final request =
          http.MultipartRequest('POST', Uri.parse('$_baseUrlSitePdv/api/ocr/hodometro'))
            ..headers['Authorization'] = 'Bearer $token'
            ..files.add(http.MultipartFile.fromBytes('arquivo', bytes, filename: 'hodometro.jpg'));

      final resposta = await request.send().timeout(const Duration(seconds: 30));
      final corpoTexto = await resposta.stream.bytesToString();
      final corpo = jsonDecode(corpoTexto) as Map<String, dynamic>;

      if (resposta.statusCode != 200) {
        return ResultadoOcrHodometro.erro(corpo['erro'] as String? ?? 'Não consegui ler a foto agora.');
      }
      return ResultadoOcrHodometro.ok(texto: corpo['texto'] as String?, hodometro: corpo['hodometro'] as num?);
    } catch (_) {
      return const ResultadoOcrHodometro.erro('Não consegui ler a foto agora. Preencha manualmente.');
    }
  }
}

// --- Passo 2: OTP atual (refresh a cada 30s) ----------------------------

class OtpAtualPdv {
  final String status;
  final String? codigoAbastecimento;
  final String? otpAtual;
  final int? segundosRestantesJanela;
  final DateTime? otpValidoAteTransacao;

  const OtpAtualPdv({
    required this.status,
    this.codigoAbastecimento,
    this.otpAtual,
    this.segundosRestantesJanela,
    this.otpValidoAteTransacao,
  });

  factory OtpAtualPdv.fromJson(Map<String, dynamic> json) {
    return OtpAtualPdv(
      status: json['status'] as String,
      codigoAbastecimento: json['codigoAbastecimento'] as String?,
      otpAtual: json['otpAtual'] as String?,
      segundosRestantesJanela: json['segundosRestantesJanela'] as int?,
      otpValidoAteTransacao: json['otpValidoAteTransacao'] != null
          ? DateTime.tryParse(json['otpValidoAteTransacao'] as String)
          : null,
    );
  }
}

// --- Passo 3: status em tempo real --------------------------------------

class StatusTransacaoPdv {
  final String status; // aguardando_pdv | negado | confirmado | expirado
  final String? codigoAbastecimento;
  final String? motivoNegacao;
  final String? combustivel;
  final num? litros;
  final num? precoLitro;
  final num? valorTotalCombustivel;
  final num? valorTotalItensExtra;
  final num? valorTotalTransacao;
  final String? formaPagamento;

  const StatusTransacaoPdv({
    required this.status,
    this.codigoAbastecimento,
    this.motivoNegacao,
    this.combustivel,
    this.litros,
    this.precoLitro,
    this.valorTotalCombustivel,
    this.valorTotalItensExtra,
    this.valorTotalTransacao,
    this.formaPagamento,
  });

  factory StatusTransacaoPdv.fromRow(Map<String, dynamic> row) {
    return StatusTransacaoPdv(
      status: row['status'] as String? ?? 'aguardando_pdv',
      codigoAbastecimento: row['codigo_abastecimento'] as String?,
      motivoNegacao: row['motivo_negacao'] as String?,
      combustivel: row['combustivel'] as String?,
      litros: row['litros'] as num?,
      precoLitro: row['preco_litro'] as num?,
      valorTotalCombustivel: row['valor_total_combustivel'] as num?,
      valorTotalItensExtra: row['valor_total_itens_extra'] as num?,
      valorTotalTransacao: row['valor_total_transacao'] as num?,
      formaPagamento: row['forma_pagamento'] as String?,
    );
  }
}

// Tela 3 (acompanhamento em tempo real) consome isto direto — StreamProvider
// cancela a subscription sozinho quando a tela sai da árvore (autoDispose).
final statusTransacaoPdvProvider = StreamProvider.autoDispose
    .family<StatusTransacaoPdv, int>((ref, abastecimentoPdvId) {
      return AbastecimentoPdvService.streamStatus(abastecimentoPdvId);
    });

class AbastecimentoPdvService {
  static Future<ResultadoIniciarPdv> iniciar({
    required String revendaEmpresaId,
    required double lat,
    required double lon,
    required num hodometro,
  }) async {
    final resp = await SupabaseService.client.rpc(
      'iniciar_abastecimento_pdv',
      params: {
        'p_revenda_empresa_id': revendaEmpresaId,
        'p_lat': lat,
        'p_lon': lon,
        'p_hodometro': hodometro,
      },
    );
    return ResultadoIniciarPdv.fromJson(resp as Map<String, dynamic>);
  }

  // Fase 5 PDV — chamada pela tela de captura de hodômetro antes de
  // fotografar, só pra mostrar a placa/último hodômetro como referência.
  static Future<ContextoHodometroPdv> contextoHodometro() async {
    final resp = await SupabaseService.client.rpc('contexto_hodometro_pdv');
    return ContextoHodometroPdv.fromJson(resp as Map<String, dynamic>);
  }

  static Future<OtpAtualPdv> obterOtpAtual(int abastecimentoPdvId) async {
    final resp = await SupabaseService.client.rpc(
      'obter_otp_atual_pdv',
      params: {'p_abastecimento_pdv_id': abastecimentoPdvId},
    );
    return OtpAtualPdv.fromJson(resp as Map<String, dynamic>);
  }

  // Mesmo padrão de streamMensagensFrete (fretes_provider.dart): usa
  // `.stream()` do supabase_flutter (Realtime por baixo, já com RLS
  // aplicada) em vez de gerenciar um RealtimeChannel manualmente.
  static Stream<StatusTransacaoPdv> streamStatus(int abastecimentoPdvId) {
    return SupabaseService.client
        .from('abastecimentos_pdv')
        .stream(primaryKey: ['id'])
        .eq('id', abastecimentoPdvId)
        .map((linhas) {
          if (linhas.isEmpty) {
            return const StatusTransacaoPdv(status: 'nao_encontrado');
          }
          return StatusTransacaoPdv.fromRow(linhas.first);
        });
  }
}
