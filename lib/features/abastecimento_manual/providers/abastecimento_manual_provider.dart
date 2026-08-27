import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

// Fase OCR-Abastecimento-Externo (27/08/2026, pedido do Daniel: "o OCR já
// existe e já é usado no romaneio de frete. Estender a mesma capacidade pro
// cupom fiscal de abastecimento externo — o motorista tira foto, o sistema
// preenche litros/valor/posto sozinho — ataca o maior ponto de atrito hoje:
// digitação manual no aplicativo"). Mesmo espírito de
// abastecimento_interno_provider.dart, mas pro lado EXTERNO (posto
// revendedor, não garagem própria): sem preço pré-cadastrado (o motorista
// informa o que está no cupom), e o registro entra PENDENTE até o gestor
// aprovar na web (decisão confirmada pelo Daniel) — diferente do interno,
// que já entra confirmado.

class EmpresaAbastecimentoManual {
  final String empresaId;
  final String nome;
  const EmpresaAbastecimentoManual({required this.empresaId, required this.nome});
}

class OpcoesAbastecimentoManual {
  final String? motoristaId;
  final String? motoristaNome;
  final List<String> placas;
  final List<EmpresaAbastecimentoManual> empresas;

  const OpcoesAbastecimentoManual({
    required this.motoristaId,
    required this.motoristaNome,
    required this.placas,
    required this.empresas,
  });

  static const empty = OpcoesAbastecimentoManual(
    motoristaId: null,
    motoristaNome: null,
    placas: [],
    empresas: [],
  );

  factory OpcoesAbastecimentoManual.fromJson(Map<String, dynamic> json) {
    if (json['status'] != 'ok') return OpcoesAbastecimentoManual.empty;
    return OpcoesAbastecimentoManual(
      motoristaId: json['motoristaId'] as String?,
      motoristaNome: json['motoristaNome'] as String?,
      placas: (json['placas'] as List? ?? []).map((e) => e as String).toList(),
      empresas: (json['empresas'] as List? ?? [])
          .map(
            (e) => EmpresaAbastecimentoManual(
              empresaId: (e as Map<String, dynamic>)['empresaId'] as String,
              nome: e['nome'] as String? ?? '',
            ),
          )
          .toList(),
    );
  }
}

final opcoesAbastecimentoManualProvider =
    FutureProvider.autoDispose<OpcoesAbastecimentoManual>((ref) async {
      final resp = await SupabaseService.client.rpc(
        'abastecimento_manual_formulario_motorista',
      );
      return OpcoesAbastecimentoManual.fromJson(resp as Map<String, dynamic>);
    });

// Mesma RPC ultimo_hodometro_veiculo já usada em Checklist de Inspeção e
// Abastecimento Interno (Fase Hodômetro-Obrigatório-PWA).
final ultimoHodometroAbastecimentoManualProvider = FutureProvider.autoDispose
    .family<num?, String>((ref, placa) async {
      final resp = await SupabaseService.client.rpc(
        'ultimo_hodometro_veiculo',
        params: {'p_placa': placa},
      );
      return resp as num?;
    });

// --- OCR do cupom fiscal ----------------------------------------------
// Mesmo padrão de ocr_service.dart (fretes): tesseract.js só roda em Node,
// então a leitura acontece numa rota do site (repo Gestão de Frotas),
// autenticada com o access_token da sessão Supabase. Best-effort: nenhum
// campo lido aqui é gravado direto — só pré-preenche o formulário, o
// motorista sempre revisa antes de enviar pra aprovação.
const _baseUrlSite = 'https://fxgestaodefrotasonline.com';

class ResultadoOcrCupomAbastecimento {
  final String? texto;
  final String? postoNome;
  final String? combustivel;
  final num? litros;
  final num? valorUnitario;
  final num? valorTotal;
  final String? erro;

  const ResultadoOcrCupomAbastecimento.ok({
    this.texto,
    this.postoNome,
    this.combustivel,
    this.litros,
    this.valorUnitario,
    this.valorTotal,
  }) : erro = null;

  const ResultadoOcrCupomAbastecimento.erro(this.erro)
    : texto = null,
      postoNome = null,
      combustivel = null,
      litros = null,
      valorUnitario = null,
      valorTotal = null;
}

class OcrCupomAbastecimentoService {
  Future<ResultadoOcrCupomAbastecimento> lerCupom(Uint8List bytes) async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    if (token == null) {
      return const ResultadoOcrCupomAbastecimento.erro(
        'Sessão expirada, faça login novamente.',
      );
    }

    try {
      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('$_baseUrlSite/api/ocr/cupom-abastecimento'),
            )
            ..headers['Authorization'] = 'Bearer $token'
            ..files.add(
              http.MultipartFile.fromBytes('arquivo', bytes, filename: 'cupom.jpg'),
            );

      final resposta = await request.send().timeout(const Duration(seconds: 30));
      final corpoTexto = await resposta.stream.bytesToString();
      final corpo = jsonDecode(corpoTexto) as Map<String, dynamic>;

      if (resposta.statusCode != 200) {
        return ResultadoOcrCupomAbastecimento.erro(
          corpo['erro'] as String? ?? 'Não consegui ler a foto agora.',
        );
      }
      return ResultadoOcrCupomAbastecimento.ok(
        texto: corpo['texto'] as String?,
        postoNome: corpo['postoNome'] as String?,
        combustivel: corpo['combustivel'] as String?,
        litros: corpo['litros'] as num?,
        valorUnitario: corpo['valorUnitario'] as num?,
        valorTotal: corpo['valorTotal'] as num?,
      );
    } catch (_) {
      return const ResultadoOcrCupomAbastecimento.erro(
        'Não consegui ler a foto agora. Preencha manualmente.',
      );
    }
  }
}

// --- Upload da foto + registro -----------------------------------------
// Bucket privado abastecimentos-evidencias (RLS por id do motorista no
// primeiro segmento do path — ver migração bucket_abastecimentos_evidencias):
// o registro em abastecimentos_externos ainda não existe no momento do
// upload (a foto sobe ANTES da RPC de registro), por isso o path usa o id
// do motorista (que já existe) em vez do id do abastecimento.
Future<String> enviarFotoCupomAbastecimento({
  required String motoristaId,
  required Uint8List bytes,
}) async {
  final caminho = '$motoristaId/${DateTime.now().millisecondsSinceEpoch}.jpg';
  await SupabaseService.client.storage
      .from('abastecimentos-evidencias')
      .uploadBinary(
        caminho,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
  return caminho;
}

class AbastecimentoManualResultado {
  final String status;
  final int? id;
  final String? codigoAbastecimento;

  const AbastecimentoManualResultado({required this.status, this.id, this.codigoAbastecimento});

  factory AbastecimentoManualResultado.fromJson(Map<String, dynamic> json) {
    return AbastecimentoManualResultado(
      status: json['status'] as String,
      id: (json['id'] as num?)?.toInt(),
      codigoAbastecimento: json['codigoAbastecimento'] as String?,
    );
  }
}

class AbastecimentoManualService {
  static Future<AbastecimentoManualResultado> registrar({
    required String empresaId,
    required String placa,
    required String combustivel,
    required num quantidade,
    required num valorTotal,
    required String postoNome,
    num? hodometro,
    DateTime? dataAbastecimento,
    required String fotoPath,
    String? ocrTextoBruto,
  }) async {
    final resp = await SupabaseService.client.rpc(
      'registrar_abastecimento_manual',
      params: {
        'p_empresa_id': empresaId,
        'p_placa': placa,
        'p_combustivel': combustivel,
        'p_quantidade': quantidade,
        'p_valor_total': valorTotal,
        'p_posto_nome': postoNome,
        'p_hodometro': hodometro,
        'p_data_abastecimento': (dataAbastecimento ?? DateTime.now()).toIso8601String(),
        'p_foto_path': fotoPath,
        'p_ocr_texto_bruto': ocrTextoBruto,
      },
    );
    return AbastecimentoManualResultado.fromJson(resp as Map<String, dynamic>);
  }
}

// Opções de combustível oferecidas no formulário — mesmo vocabulário
// reconhecido pela extração de OCR no lado do servidor (ver
// PALAVRAS_COMBUSTIVEL em src/lib/ocr.ts, repo Gestão de Frotas), pra o
// valor pré-preenchido pelo OCR sempre bater com uma opção do dropdown.
const combustiveisAbastecimentoManual = <String>[
  'Diesel S10',
  'Diesel S500',
  'Diesel',
  'Gasolina Comum',
  'Gasolina Aditivada',
  'Etanol',
  'GNV',
  'Arla32',
];
