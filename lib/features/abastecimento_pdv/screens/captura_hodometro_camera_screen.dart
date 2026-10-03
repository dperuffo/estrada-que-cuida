import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../providers/abastecimento_pdv_provider.dart';

// Backlog #103 (03/10/2026, pedido do Daniel: "o quadro de foco para leitura
// do hodômetro já seja apresentado na câmera no momento da foto") — câmera
// ao vivo com um quadro de enquadramento por cima. O image_picker abre a
// câmera nativa do navegador, que não deixa desenhar nada em cima; aqui o
// preview é um widget nosso. O motorista encaixa só os dígitos do hodômetro
// dentro do quadro, e junto com a foto devolvemos o retângulo do quadro (em
// frações 0-1 da imagem) — o servidor recorta nessa região antes do OCR.
class CapturaHodometroResultado {
  final Uint8List? bytes;
  final RecorteQuadro? recorte;

  // true quando não deu pra abrir a câmera ao vivo (permissão negada,
  // navegador sem suporte etc.) — a tela chamadora cai no image_picker.
  final bool cameraIndisponivel;

  const CapturaHodometroResultado.foto(this.bytes, this.recorte) : cameraIndisponivel = false;
  const CapturaHodometroResultado.semCamera() : bytes = null, recorte = null, cameraIndisponivel = true;
}

// Posição do quadro, em frações do preview. Largo e baixo: dígitos de
// hodômetro formam uma linha horizontal.
const _quadro = RecorteQuadro(x: 0.08, y: 0.40, w: 0.84, h: 0.18);

class CapturaHodometroCameraScreen extends StatefulWidget {
  const CapturaHodometroCameraScreen({super.key});

  @override
  State<CapturaHodometroCameraScreen> createState() => _CapturaHodometroCameraScreenState();
}

class _CapturaHodometroCameraScreenState extends State<CapturaHodometroCameraScreen> {
  CameraController? _controller;
  bool _capturando = false;

  @override
  void initState() {
    super.initState();
    _iniciarCamera();
  }

  Future<void> _iniciarCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('sem câmera');
      // Prefere a câmera traseira (a do painel do veículo).
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(camera, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) Navigator.of(context).pop(const CapturaHodometroResultado.semCamera());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capturar() async {
    final controller = _controller;
    if (controller == null || _capturando) return;
    setState(() => _capturando = true);
    try {
      final foto = await controller.takePicture();
      final bytes = await foto.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(CapturaHodometroResultado.foto(bytes, _quadro));
    } catch (_) {
      if (mounted) {
        setState(() => _capturando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não consegui tirar a foto. Tente de novo.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Fotografar hodômetro'),
      ),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(controller),
                          const IgnorePointer(child: CustomPaint(painter: _QuadroPainter())),
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Encaixe só os números do hodômetro dentro do quadro.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16, top: 8),
                    child: FloatingActionButton(
                      onPressed: _capturando ? null : _capturar,
                      backgroundColor: Colors.white,
                      child: _capturando
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt, color: Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// Escurece tudo fora do quadro e desenha a moldura com cantos destacados.
class _QuadroPainter extends CustomPainter {
  const _QuadroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _quadro.x * size.width,
      _quadro.y * size.height,
      _quadro.w * size.width,
      _quadro.h * size.height,
    );

    final fora = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(fora, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final canto = Paint()
      ..color = const Color(0xFF4DB956)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const t = 22.0;
    final cantos = <(Offset, Offset, Offset)>[
      (rect.topLeft, const Offset(t, 0), const Offset(0, t)),
      (rect.topRight, const Offset(-t, 0), const Offset(0, t)),
      (rect.bottomLeft, const Offset(t, 0), const Offset(0, -t)),
      (rect.bottomRight, const Offset(-t, 0), const Offset(0, -t)),
    ];
    for (final (origem, horizontal, vertical) in cantos) {
      canvas.drawLine(origem, origem + horizontal, canto);
      canvas.drawLine(origem, origem + vertical, canto);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
