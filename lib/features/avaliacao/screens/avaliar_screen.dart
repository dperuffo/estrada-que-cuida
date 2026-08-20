import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/motorista_provider.dart';
import '../../../core/widgets/app_drawer.dart';
import '../providers/avaliacao_provider.dart';
import '../services/avaliacao_service.dart';

import '../../../core/theme/app_theme.dart';

final _formatoData = DateFormat('dd/MM/yyyy');

class AvaliarScreen extends ConsumerStatefulWidget {
  const AvaliarScreen({super.key});

  @override
  ConsumerState<AvaliarScreen> createState() => _AvaliarScreenState();
}

class _AvaliarScreenState extends ConsumerState<AvaliarScreen> {
  final _comentarioCtrl = TextEditingController();
  int _estrelas = 0;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar(PerfilMotorista perfil) async {
    if (_estrelas == 0) {
      setState(() => _erro = 'Selecione de 1 a 5 estrelas.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final erro = await AvaliacoesService().enviarAvaliacao(
      motoristaId: perfil.id,
      telefone: perfil.telefone ?? '',
      empresaId: perfil.empresaId,
      estrelas: _estrelas,
      comentario: _comentarioCtrl.text,
    );
    if (!mounted) return;
    if (erro != null) {
      setState(() {
        _erro = erro;
        _enviando = false;
      });
      return;
    }
    setState(() {
      _estrelas = 0;
      _comentarioCtrl.clear();
      _enviando = false;
    });
    ref.invalidate(minhasAvaliacoesProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Obrigado pela avaliação!')));
  }

  @override
  Widget build(BuildContext context) {
    final perfilAsync = ref.watch(meuPerfilProvider);
    final historicoAsync = ref.watch(minhasAvaliacoesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Avaliar o app'),
      ),
      drawer: const AppDrawer(),
      body: perfilAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (perfil) {
          if (perfil == null)
            return const Center(child: Text('Perfil não encontrado.'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Como está sendo sua experiência com o Estrada que Cuida?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final n = i + 1;
                  return IconButton(
                    iconSize: 36,
                    onPressed: () => setState(() => _estrelas = n),
                    icon: Icon(
                      n <= _estrelas ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                  );
                }),
              ),
              if (_estrelas > 0)
                Center(
                  child: Text(
                    rotuloNota(_estrelas),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _comentarioCtrl,
                decoration: const InputDecoration(
                  labelText: 'Comentário (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _enviando ? null : () => _enviar(perfil),
                child: _enviando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Enviar avaliação'),
              ),
              const Divider(height: 40),
              const Text(
                'Suas avaliações anteriores',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              historicoAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Não consegui carregar o histórico: $e'),
                data: (lista) {
                  if (lista.isEmpty)
                    return const Text('Você ainda não avaliou o app.');
                  return Column(
                    children: lista.map((a) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Row(
                                    children: List.generate(
                                      5,
                                      (i) => Icon(
                                        i < a.estrelas
                                            ? Icons.star
                                            : Icons.star_border,
                                        color: Colors.amber,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (a.criadoEm != null)
                                    Text(
                                      _formatoData.format(
                                        DateTime.parse(a.criadoEm!).toLocal(),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                ],
                              ),
                              if (a.comentario != null &&
                                  a.comentario!.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(a.comentario!),
                              ],
                              if (a.respostaAdmin != null &&
                                  a.respostaAdmin!.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Resposta da FNI: ${a.respostaAdmin}',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
