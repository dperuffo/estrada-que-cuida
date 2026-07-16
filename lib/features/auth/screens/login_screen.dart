import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/auth_provider.dart';

// Tela 1 do app — motorista digita o celular (com DDD) e recebe um
// código por SMS. Sem senha, sem cadastro aqui: o cadastro (nome, CPF,
// CNH) já existe em `motoristas`, feito pela empresa dele; aqui só
// provamos que o celular é dele.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = TextEditingController();
  bool _enviando = false;
  String? _erro;

  /// Aceita "(11) 99999-8888", "11999998888" etc. e devolve E.164
  /// (+55DDDNÚMERO) — formato que o Supabase Auth espera.
  String? _paraE164(String digitado) {
    final digitos = digitado.replaceAll(RegExp(r'\D'), '');
    if (digitos.length < 10 || digitos.length > 11) return null;
    return '+55$digitos';
  }

  Future<void> _enviarCodigo() async {
    final telefone = _paraE164(_controller.text);
    if (telefone == null) {
      setState(() => _erro = 'Digite um celular válido, com DDD.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await AuthService.enviarCodigo(telefone);
      if (!mounted) return;
      context.push('/otp', extra: telefone);
    } catch (e) {
      setState(() => _erro = 'Não consegui enviar o código. Tente de novo em instantes.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.local_shipping_rounded, size: 64, color: Color(0xFF1B7A43)),
              const SizedBox(height: 16),
              Text(
                'Estrada que Cuida',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Mais do que abastecer. Cuidar de quem move o Brasil.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Seu celular (com DDD)',
                  hintText: '(11) 99999-8888',
                  prefixIcon: Icon(Icons.phone_android),
                ),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _enviando ? null : _enviarCodigo,
                child: _enviando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Receber código por SMS'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
