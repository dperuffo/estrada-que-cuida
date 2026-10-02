import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/abastecimento_pdv_provider.dart';

// Fase 5 PDV (02/10/2026, pedido do Daniel: "tela de captura de hodômetro
// através de foto com OCR, com preenchimento automático e ajuste manual;
// hodômetro tem que ser maior que o último registrado do veículo") —
// nova Tela 1.5 do fluxo, entre escolher o posto (Tela 1) e o código+OTP
// (Tela 2): motorista fotografa o painel, o app lê o valor via OCR (mesma
// rota/abordagem do cupom de abastecimento externo — tesseract.js no
// site, best-effort) e pré-preenche o campo, que continua editável (o OCR
// nunca trava o valor). Quem de fato cria a transação PDV agora é esta
// tela (iniciar_abastecimento_pdv passou a exigir p_hodometro) — a Tela 1
// só escolhe o posto e repassa revenda/geolocalização pra cá.
class AbastecimentoPdvHodometroScreen extends ConsumerStatefulWidget {
  final String revendaEmpresaId;
  final double lat;
  final double lon;

  const AbastecimentoPdvHodometroScreen({
    super.key,
    required this.revendaEmpresaId,
    required this.lat,
    required this.lon,
  });

  @override
  ConsumerState<AbastecimentoPdvHodometroScreen> createState() =>
      _AbastecimentoPdvHodometroScreenState();
}

class _AbastecimentoPdvHodometroScreenState
    extends ConsumerState<AbastecimentoPdvHodometroScreen> {
  final _hodometroCtrl = TextEditingController();

  Uint8List? _fotoBytes;
  bool _lendoOcr = false;
  bool _confirmando = false;
  bool _carregandoContexto = true;
  String? _placa;
  num? _ultimoHodometro;
  String? _erro;
  bool _confiancaBaixa = false;

  @override
  void initState() {
    super.initState();
    _carregarContexto();
  }

  @override
  void dispose() {
    _hodometroCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarContexto() async {
    final contexto = await AbastecimentoPdvService.contextoHodometro();
    if (!mounted) return;
    setState(() {
      _placa = contexto.placa;
      _ultimoHodometro = contexto.ultimoHodometro;
      _carregandoContexto = false;
    });
  }

  // Mesmo padrão de câmera + confirmação já usado em
  // abastecimento_manual_screen.dart (_capturarFoto/_tirarFoto). Qualidade e
  // resolução mais altas que o padrão usado nos outros OCRs desta tela
  // (02/10/2026, acurácia ruim reportada pelo Daniel): dígito de hodômetro é
  // pequeno no quadro da foto — comprimir demais destrói exatamente o
  // detalhe que o OCR precisa pra distinguir, por exemplo, "3" de "8".
  Future<Uint8List?> _capturarFoto() async {
    try {
      final foto = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 2400,
      );
      if (foto == null) return null;
      return await foto.readAsBytes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não consegui abrir a câmera: $e')));
      }
      return null;
    }
  }

  Future<Uint8List?> _tirarFoto() async {
    while (true) {
      final bytes = await _capturarFoto();
      if (bytes == null || !mounted) return null;

      final confirmou = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Usar esta foto do hodômetro?'),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tirar de novo'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirmou == true) return bytes;
      if (confirmou == null) return null;
      if (!mounted) return null;
    }
  }

  Future<void> _fotografarELer() async {
    final bytes = await _tirarFoto();
    if (bytes == null || !mounted) return;

    setState(() {
      _fotoBytes = bytes;
      _lendoOcr = true;
      _erro = null;
      _confiancaBaixa = false;
    });

    final resultado = await OcrHodometroService().lerHodometro(bytes);
    if (!mounted) return;

    setState(() {
      _lendoOcr = false;
      if (resultado.hodometro != null) {
        _hodometroCtrl.text = resultado.hodometro!.toStringAsFixed(0);
      }
      // A leitura preenche o campo mesmo com confiança baixa (ajuda mais do
      // que não preencher nada), mas sinaliza bem visível que o motorista
      // precisa conferir dígito a dígito antes de confirmar.
      _confiancaBaixa = resultado.hodometro == null || resultado.confiancaBaixa;
    });

    if (resultado.erro != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${resultado.erro} Digite o hodômetro manualmente.')),
      );
    }
  }

  Future<void> _confirmar() async {
    final hodometro = num.tryParse(_hodometroCtrl.text.replaceAll(',', '.'));
    if (hodometro == null || hodometro <= 0) {
      setState(() => _erro = 'Informe o hodômetro atual (só números).');
      return;
    }
    final ultimo = _ultimoHodometro;
    if (ultimo != null && hodometro <= ultimo) {
      setState(
        () => _erro =
            'O hodômetro tem que ser maior que o último registrado (${ultimo.toStringAsFixed(0)} km).',
      );
      return;
    }

    setState(() {
      _confirmando = true;
      _erro = null;
    });
    try {
      final resultado = await AbastecimentoPdvService.iniciar(
        revendaEmpresaId: widget.revendaEmpresaId,
        lat: widget.lat,
        lon: widget.lon,
        hodometro: hodometro,
      );
      if (!mounted) return;

      switch (resultado.status) {
        case 'aguardando_pdv':
          context.push(
            '/abastecimento-pdv/otp',
            extra: {
              'id': resultado.id,
              'codigoAbastecimento': resultado.codigoAbastecimento,
              'otpAtual': resultado.otpAtual,
              'otpValidoAteTransacao': resultado.otpValidoAteTransacao,
              'nomeRevenda': resultado.nomeRevenda,
            },
          );
          break;
        case 'hodometro_obrigatorio':
          setState(() => _erro = 'Informe o hodômetro atual (só números).');
          break;
        case 'hodometro_invalido':
          final ultimoServidor = resultado.ultimoHodometro;
          setState(
            () => _erro = ultimoServidor != null
                ? 'O hodômetro tem que ser maior que o último registrado (${ultimoServidor.toStringAsFixed(0)} km).'
                : 'Hodômetro inválido.',
          );
          break;
        case 'geolocalizacao_reprovada':
          setState(
            () => _erro =
                'Você está a ${resultado.distanciaMetros?.toStringAsFixed(0) ?? '?'} m do posto — '
                'o limite permitido é ${resultado.raioPermitidoMetros?.toStringAsFixed(0) ?? '500'} m. '
                'Chegue mais perto da bomba e tente de novo.',
          );
          break;
        case 'nao_vinculado':
          setState(() => _erro = 'Seu usuário não está vinculado a um cadastro de motorista.');
          break;
        case 'veiculo_nao_identificado':
        case 'veiculo_nao_autorizado':
          setState(() => _erro = 'Não encontrei um veículo autorizado vinculado a você.');
          break;
        case 'revenda_invalida':
        case 'posto_sem_coordenadas':
        case 'revenda_sem_pdv_ativo':
          setState(() => _erro = 'Esse posto não está com o PDV disponível no momento. Tente outro ou abasteça por outro canal.');
          break;
        default:
          setState(() => _erro = 'Não consegui iniciar o abastecimento agora. Tente de novo em instantes.');
      }
    } catch (e) {
      setState(() => _erro = 'Não consegui iniciar o abastecimento agora. Tente de novo em instantes.');
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Hodômetro do veículo'),
      ),
      drawer: const AppDrawer(),
      body: _carregandoContexto
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _placa != null
                      ? 'Fotografe o painel do veículo $_placa pra registrar o hodômetro deste abastecimento.'
                      : 'Fotografe o painel do veículo pra registrar o hodômetro deste abastecimento.',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Dica: aproxime bem só dos números do hodômetro, evite reflexo no vidro do painel e garanta boa luz.',
                  style: TextStyle(color: Colors.black45, fontSize: 12),
                ),
                if (_ultimoHodometro != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Último registrado: ${_ultimoHodometro!.toStringAsFixed(0)} km',
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                if (_fotoBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_fotoBytes!, height: 180, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 12),
                if (_lendoOcr)
                  const Row(
                    children: [
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Lendo o painel...'),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _fotografarELer,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(_fotoBytes == null ? 'Fotografar o hodômetro' : 'Tirar outra foto'),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _hodometroCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Hodômetro (km)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_confiancaBaixa && _fotoBytes != null && !_lendoOcr) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: AppTheme.statusAtencao),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'A leitura automática não ficou confiável — confira o valor com atenção antes de confirmar.',
                          style: TextStyle(color: AppTheme.statusAtencao, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Text(_erro!, style: const TextStyle(color: AppTheme.statusInativo)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _confirmando ? null : _confirmar,
                  child: _confirmando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirmar e gerar código'),
                ),
              ],
            ),
    );
  }
}
