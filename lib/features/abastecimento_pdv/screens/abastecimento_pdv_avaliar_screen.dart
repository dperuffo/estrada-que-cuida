import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
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
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient)),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        automaticallyImplyLeading: false,
        title: const Text('Avalie seu abastecimento'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.check_circle, size: 56, color: AppTheme.statusAtivo),
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
          const Text(
            'Como foi sua experiência? Toque nas estrelas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
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
            Text(subtitulo, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => aoMudar(i),
                    iconSize: 36,
                    tooltip: '$i estrela${i > 1 ? 's' : ''}',
                    icon: Icon(
                      i <= nota ? Icons.star : Icons.star_border,
                      color: i <= nota ? const Color(0xFFF59E0B) : Colors.black26,
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
