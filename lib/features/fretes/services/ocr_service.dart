import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../../core/services/supabase_service.dart';

// Fase ocr-documentos (04/08/2026, item 8 do benchmark FNI vs KMM, Grupo 2)
// — "ler CT-e/canhoto automaticamente em vez de só foto". Decisão do
// Daniel: Tesseract OCR (gratuito). Igual ao Assistente FNI (ver
// assistente_service.dart no PWA Cliente): tesseract.js só roda em Node,
// então não dá pra rodar OCR direto no app Flutter — esta chamada vai pra
// uma rota nova do site (`/api/ocr/documento`, repo Gestão de Frotas),
// autenticada com o access_token da sessão Supabase do usuário (mesmo
// padrão do Assistente). Best-effort: nenhum campo extraído é gravado
// direto — só pré-preenche formulário, o motorista sempre revisa antes de
// confirmar (foto de celular nunca garante 100% de acerto).
const _baseUrlSite = 'https://fxgestaodefrotasonline.com';

class ResultadoOcrDocumento {
  final String? chaveAcesso;
  final String? documentoRecebedor;
  final String? erro;

  const ResultadoOcrDocumento.ok({this.chaveAcesso, this.documentoRecebedor})
    : erro = null;
  const ResultadoOcrDocumento.erro(this.erro)
    : chaveAcesso = null,
      documentoRecebedor = null;

  bool get temAlgumaLeitura =>
      chaveAcesso != null || documentoRecebedor != null;
}

class OcrService {
  // Lê uma foto (canhoto ou DANFE) e tenta extrair chave de acesso da NF-e
  // (44 dígitos) e/ou CPF do recebedor — só o que costuma vir IMPRESSO;
  // nome escrito à mão não é confiável pra nenhum OCR, nem os pagos.
  Future<ResultadoOcrDocumento> lerDocumento(Uint8List bytes) async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    if (token == null)
      return const ResultadoOcrDocumento.erro(
        'Sessão expirada, faça login novamente.',
      );

    try {
      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('$_baseUrlSite/api/ocr/documento'),
            )
            ..headers['Authorization'] = 'Bearer $token'
            ..files.add(
              http.MultipartFile.fromBytes(
                'arquivo',
                bytes,
                filename: 'documento.jpg',
              ),
            );

      final resposta = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final corpoTexto = await resposta.stream.bytesToString();
      final corpo = jsonDecode(corpoTexto) as Map<String, dynamic>;

      if (resposta.statusCode != 200) {
        return ResultadoOcrDocumento.erro(
          corpo['erro'] as String? ?? 'Não consegui ler a foto agora.',
        );
      }
      return ResultadoOcrDocumento.ok(
        chaveAcesso: corpo['chaveAcesso'] as String?,
        documentoRecebedor: corpo['documentoRecebedor'] as String?,
      );
    } catch (_) {
      return const ResultadoOcrDocumento.erro(
        'Não consegui ler a foto agora. Tente de novo ou digite manualmente.',
      );
    }
  }
}
