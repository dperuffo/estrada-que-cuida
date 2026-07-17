import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/motorista_provider.dart';
import '../../../core/services/supabase_service.dart';

// Tela de Adesão — obrigatória antes de qualquer outra tela do programa
// (confirmar abastecimento, ver saldo). Pontos ficam cumulativos enquanto
// o motorista permanecer aderido (decisão do Daniel, ver
// PROPOSTA-FIDELIDADE-MOTORISTA.md).
class AdesaoScreen extends ConsumerStatefulWidget {
  final String motoristaId;
  final String? nome;

  const AdesaoScreen({super.key, required this.motoristaId, this.nome});

  @override
  ConsumerState<AdesaoScreen> createState() => _AdesaoScreenState();
}

class _AdesaoScreenState extends ConsumerState<AdesaoScreen> {
  bool _aceitou = false;
  bool _enviando = false;
  String? _erro;

  Future<void> _aderir() async {
    if (!_aceitou) {
      setState(() => _erro = 'Você precisa aceitar os termos pra continuar.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await SupabaseService.client.from('fidelidade_adesoes').insert({
        'motorista_id': widget.motoristaId,
        'versao_termos_aceita': 'v1',
        'status': 'ativo',
      });
      ref.invalidate(adesaoAtivaProvider);
    } catch (e) {
      // Fase debug-adesão — pedido do Daniel: a mensagem genérica escondia
      // o motivo real (RLS, coluna obrigatória faltando etc.). Mostrar o
      // erro do Postgrest quando existir ajuda a diagnosticar sem precisar
      // ficar adivinhando.
      setState(() {
        _erro = e is PostgrestException
            ? 'Não consegui registrar sua adesão agora: ${e.message}'
            : 'Não consegui registrar sua adesão agora. Tente de novo em instantes. ($e)';
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primeiroNome = (widget.nome ?? '').split(' ').first;
    return Scaffold(
      appBar: AppBar(title: const Text('Estrada que Cuida')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                primeiroNome.isEmpty ? 'Bem-vindo!' : 'Bem-vindo, $primeiroNome!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Mais do que abastecer. Cuidar de quem move o Brasil.\n\n'
                'Ao aderir ao Estrada que Cuida, cada abastecimento que você confirmar como seu vira pontos. '
                'Os pontos ficam guardados enquanto você continuar no programa — sem expirar por tempo.',
              ),
              const SizedBox(height: 24),
              CheckboxListTile(
                value: _aceitou,
                onChanged: (v) => setState(() => _aceitou = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('Li e aceito participar do programa Estrada que Cuida.'),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _enviando ? null : _aderir,
                child: _enviando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Quero participar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => AuthService.sair(),
                child: const Text('Sair'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
