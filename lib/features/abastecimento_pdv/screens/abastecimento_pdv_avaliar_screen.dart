import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/pre_pedido_provider.dart';
import '../providers/abastecimento_pdv_provider.dart';

// Tela final do fluxo PDV (03/10/2026, pedido do Daniel): depois do posto
// confirmar o abastecimento, o motorista avalia o posto, o abastecimento e o
// atendimento (frentista/caixa) com estrelas, mais uma observação opcional.
class AbastecimentoPdvAvaliarScreen extends ConsumerStatefulWidget {
  final int abastecimentoPdvId;

  const AbastecimentoPdvAvaliarScreen({super.key, required this.abastecimentoPdvId});

  @override
  ConsumerState<AbastecimentoPdvAvaliarScreen> createState() => _AbastecimentoPdvAvaliarScreenState();
}

class _AbastecimentoPdvAvaliarScreenState extends ConsumerState<AbastecimentoPdvAvaliarScreen> {
  int _posto = 0;
  int _abastecimento = 0;
  int _atendimento = 0;
  final _obs = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  bool get _completo => _posto > 0 && _abastecimento > 0 && _atendimento > 0;

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    final erro = await AbastecimentoPdvService.avaliar(
      abastecimentoPdvId: widget.abastecimentoPdvId,
      notaPosto: _posto,
      notaAbastecimento: _abastecimento,
      notaAtendimento: _atendimento,
      observacao: _obs.text.trim().isEmpty ? null : _obs.text.trim(),
    );
    if (!mounted) return;
    setState(() => _enviando = false);
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
      return;
    }
    // Some o cartão "Abastecimento concluído" da Home na hora (sem esperar o
    // próximo ciclo de 10 s da consulta).
    ref.read(avaliacoesDispensadasProvider.notifier).update((s) => {...s, widget.abastecimentoPdvId});
    ref.invalidate(avaliacaoPrePedidoPendenteProvider);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Obrigado pela sua avaliação!')));
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(statusTransacaoPdvProvider(widget.abastecimentoPdvId)).valueOrNull;
    final posto = status?.postoNome;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(decoration: BoxDecoration(gradient: AppTheme.glassNavGradient)),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: IconThemeData(color: AppTheme.glassIcone),
        automaticallyImplyLeading: false,
        title: const Text('Avalie seu abastecimento'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          const Text(
            'Abastecimento confirmado!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          if (posto != null)
            Text(
              posto,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.accento),
            ),
          const SizedBox(height: 4),
          Text(
            'Como foi sua experiência? Toque nas estrelas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.glassTextoMuted),
          ),
          const SizedBox(height: 20),
          _bloco('Posto', posto ?? 'Estrutura, limpeza e conveniência', _posto, (n) => setState(() => _posto = n)),
          _bloco('Abastecimento', 'Bomba, combustível e tempo', _abastecimento, (n) => setState(() => _abastecimento = n)),
          _bloco('Frentista / Caixa', 'Atendimento e cordialidade', _atendimento, (n) => setState(() => _atendimento = n)),
          const SizedBox(height: 8),
          TextField(
            controller: _obs,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Observação (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _completo && !_enviando ? _enviar : null,
            child: _enviando
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enviar avaliação'),
          ),
          TextButton(
            onPressed: _enviando ? null : () => context.go('/'),
            child: const Text('Agora não'),
          ),
        ],
      ),
    );
  }

  Widget _bloco(String titulo, String subtitulo, int nota, ValueChanged<int> aoMudar) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text(subtitulo, style: TextStyle(color: AppTheme.glassTextoMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  GestureDetector(
                    onTap: () => aoMudar(i),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: CustomPaint(
                        size: const Size(40, 40),
                        painter: _EstrelaPainter(preenchida: i <= nota),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Estrela desenhada à mão (Path) — não depende da fonte de ícones, que não
// estava carregando no PWA publicado.
class _EstrelaPainter extends CustomPainter {
  final bool preenchida;
  const _EstrelaPainter({required this.preenchida});

  @override
  void paint(Canvas canvas, Size size) {
    final centro = Offset(size.width / 2, size.height / 2 + 1);
    final raioExterno = size.width / 2;
    final raioInterno = raioExterno * 0.42;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final raio = i.isEven ? raioExterno : raioInterno;
      final angulo = -math.pi / 2 + i * math.pi / 5;
      final ponto = Offset(centro.dx + raio * math.cos(angulo), centro.dy + raio * math.sin(angulo));
      if (i == 0) {
        path.moveTo(ponto.dx, ponto.dy);
      } else {
        path.lineTo(ponto.dx, ponto.dy);
      }
    }
    path.close();
    const cor = Color(0xFFF59E0B);
    if (preenchida) canvas.drawPath(path, Paint()..color = cor);
    canvas.drawPath(
      path,
      Paint()
        ..color = preenchida ? cor : const Color(0xFF94A3B8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _EstrelaPainter old) => old.preenchida != preenchida;
}
