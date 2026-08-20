import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/motorista_provider.dart';
import '../providers/chamados_provider.dart';
import '../services/chamados_service.dart';

import '../../../core/theme/app_theme.dart';

class ChamadoNovoScreen extends ConsumerStatefulWidget {
  const ChamadoNovoScreen({super.key});

  @override
  ConsumerState<ChamadoNovoScreen> createState() => _ChamadoNovoScreenState();
}

class _ChamadoNovoScreenState extends ConsumerState<ChamadoNovoScreen> {
  final _tituloCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  String _tipo = 'incidente';
  String _prioridade = 'media';
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descricaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar(PerfilMotorista perfil) async {
    if (_tituloCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Digite um título curto pro chamado.');
      return;
    }
    if (_descricaoCtrl.text.trim().isEmpty) {
      setState(() => _erro = 'Descreva o que aconteceu.');
      return;
    }
    if (perfil.empresaId == null) {
      setState(
        () => _erro = 'Não encontrei sua empresa. Tente sair e entrar de novo.',
      );
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final id = await ChamadosService().criarChamado(
        empresaId: perfil.empresaId!,
        motoristaId: perfil.id,
        telefone: perfil.telefone ?? '',
        tipo: _tipo,
        titulo: _tituloCtrl.text.trim(),
        descricao: _descricaoCtrl.text.trim(),
        prioridade: _prioridade,
      );
      ref.invalidate(meusChamadosProvider);
      if (!mounted) return;
      context.pushReplacement('/chamados/$id');
    } catch (e) {
      setState(
        () => _erro =
            'Não consegui abrir o chamado agora. Tente de novo em instantes.',
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfilAsync = ref.watch(meuPerfilProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Novo chamado'),
      ),
      body: perfilAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (perfil) {
          if (perfil == null)
            return const Center(child: Text('Perfil não encontrado.'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  border: OutlineInputBorder(),
                ),
                items: tiposTicket.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _tipo = v ?? _tipo),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _prioridade,
                decoration: const InputDecoration(
                  labelText: 'Prioridade',
                  border: OutlineInputBorder(),
                ),
                items: prioridadesTicket.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) =>
                    setState(() => _prioridade = v ?? _prioridade),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tituloCtrl,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descricaoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descreva o que aconteceu',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
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
                    : const Text('Abrir chamado'),
              ),
            ],
          );
        },
      ),
    );
  }
}
