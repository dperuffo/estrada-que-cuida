import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/motorista_provider.dart';
import '../providers/chamados_provider.dart';
import '../services/chamados_service.dart';

final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

class ChamadoDetalheScreen extends ConsumerStatefulWidget {
  final String ticketId;
  const ChamadoDetalheScreen({super.key, required this.ticketId});

  @override
  ConsumerState<ChamadoDetalheScreen> createState() => _ChamadoDetalheScreenState();
}

class _ChamadoDetalheScreenState extends ConsumerState<ChamadoDetalheScreen> {
  final _comentarioCtrl = TextEditingController();
  bool _enviando = false;
  bool _jaMarcouVisto = false;

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviarComentario(String telefone) async {
    final texto = _comentarioCtrl.text.trim();
    if (texto.isEmpty) return;
    setState(() => _enviando = true);
    try {
      await ChamadosService().comentar(ticketId: widget.ticketId, telefone: telefone, texto: texto);
      _comentarioCtrl.clear();
      ref.invalidate(chamadoDetalheProvider(widget.ticketId));
      ref.invalidate(meusChamadosProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não consegui enviar a mensagem.')));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detalheAsync = ref.watch(chamadoDetalheProvider(widget.ticketId));
    final perfilAsync = ref.watch(meuPerfilProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chamado')),
      body: detalheAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (detalhe) {
          if (detalhe == null) return const Center(child: Text('Chamado não encontrado.'));

          // Marca como visto assim que abre a tela (uma vez só por sessão
          // dessa tela) — mesma UX da web/posto.
          if (!_jaMarcouVisto) {
            _jaMarcouVisto = true;
            Future.microtask(() => ChamadosService().marcarVisto(widget.ticketId));
          }

          final t = detalhe.ticket;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('#${t.numero} — ${t.titulo}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${tiposTicket[t.tipo] ?? t.tipo} • ${statusTicket[t.status] ?? t.status} • Prioridade ${prioridadesTicket[t.prioridade] ?? t.prioridade}'),
                    const SizedBox(height: 16),
                    Text(t.descricao),
                    if (t.respostaAdmin != null && t.respostaAdmin!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Resposta da FNI', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(t.respostaAdmin!),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 32),
                    const Text('Conversa', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (detalhe.comentarios.isEmpty) const Text('Nenhuma mensagem ainda.'),
                    for (final c in detalhe.comentarios)
                      Align(
                        alignment: c.autorTipo == 'admin' ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: c.autorTipo == 'admin' ? Colors.grey.shade200 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.autorTipo == 'admin' ? 'FNI' : 'Você',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 2),
                              Text(c.texto),
                              const SizedBox(height: 4),
                              Text(_formatoData.format(DateTime.parse(c.criadoEm).toLocal()),
                                  style: const TextStyle(fontSize: 10, color: Colors.black54)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _comentarioCtrl,
                          decoration: const InputDecoration(hintText: 'Escreva uma mensagem...', border: OutlineInputBorder(), isDense: true),
                          minLines: 1,
                          maxLines: 3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _enviando
                            ? null
                            : () => _enviarComentario(perfilAsync.valueOrNull?.telefone ?? ''),
                        icon: _enviando
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
