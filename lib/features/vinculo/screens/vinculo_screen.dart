import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/motorista_provider.dart';
import '../../../core/services/supabase_service.dart';

// "Tela de confirmação de cadastro" — aparece quando o celular verificado
// não bate (ou bate com mais de um) com nenhum motorista cadastrado por
// nenhuma empresa. Pede o CPF pra localizar o cadastro certo (chave mais
// confiável que telefone).
class VinculoScreen extends ConsumerStatefulWidget {
  final String statusInicial; // 'ambiguo_requer_cpf' ou 'nao_encontrado'

  const VinculoScreen({super.key, required this.statusInicial});

  @override
  ConsumerState<VinculoScreen> createState() => _VinculoScreenState();
}

class _VinculoScreenState extends ConsumerState<VinculoScreen> {
  final _cpfController = TextEditingController();
  bool _enviando = false;
  String? _erro;

  Future<void> _confirmar() async {
    final cpf = _cpfController.text.replaceAll(RegExp(r'\D'), '');
    if (cpf.length != 11) {
      setState(() => _erro = 'Digite um CPF válido (11 números).');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final resp = await SupabaseService.client.rpc('vincular_motorista_auth', params: {'p_cpf': cpf});
      final resultado = VinculoResultado.fromJson(resp as Map<String, dynamic>);
      if (resultado.status == 'vinculado' || resultado.status == 'ja_vinculado') {
        // Refaz a checagem sem CPF lá em cima (Gate) — agora vem
        // 'ja_vinculado' porque o vínculo já foi gravado.
        ref.invalidate(vinculoProvider(null));
      } else if (resultado.status == 'ambiguo_requer_cpf') {
        setState(() => _erro = 'Esse CPF e celular não formam uma combinação única. Confira os dados ou fale com sua empresa.');
      } else {
        setState(() => _erro = 'Não encontrei nenhum cadastro com esse celular e CPF. Confira com a empresa se você já foi cadastrado como motorista.');
      }
    } catch (e) {
      setState(() => _erro = 'Não consegui verificar agora. Tente de novo em instantes.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final explicacao = widget.statusInicial == 'ambiguo_requer_cpf'
        ? 'Encontramos mais de um cadastro com esse celular. Digite seu CPF pra confirmar qual é o seu.'
        : 'Não achamos seu cadastro só pelo celular. Digite seu CPF pra localizarmos — ele precisa ser o mesmo que sua empresa usou ao te cadastrar.';

    return Scaffold(
      appBar: AppBar(title: const Text('Confirme seu cadastro')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(explicacao),
              const SizedBox(height: 24),
              TextField(
                controller: _cpfController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'CPF', hintText: '000.000.000-00'),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _enviando ? null : _confirmar,
                child: _enviando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Confirmar'),
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
