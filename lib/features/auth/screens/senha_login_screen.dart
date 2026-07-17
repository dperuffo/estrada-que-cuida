import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/auth_provider.dart';

// Fase login-por-senha — tela mostrada quando `motorista_tem_senha` diz que
// esse telefone já tem senha cadastrada (ou seja, não é o primeiro acesso).
// Entrada normal: telefone + senha numérica de 6 dígitos, sem SMS.
class SenhaLoginScreen extends StatefulWidget {
  final String telefoneE164;

  const SenhaLoginScreen({super.key, required this.telefoneE164});

  @override
  State<SenhaLoginScreen> createState() => _SenhaLoginScreenState();
}

class _SenhaLoginScreenState extends State<SenhaLoginScreen> {
  final _senhaController = TextEditingController();
  bool _entrando = false;
  bool _enviandoRecuperacao = false;
  String? _erro;

  Future<void> _entrar() async {
    final senha = _senhaController.text.trim();
    if (senha.length != 6) {
      setState(() => _erro = 'Digite os 6 dígitos da sua senha.');
      return;
    }
    setState(() {
      _entrando = true;
      _erro = null;
    });
    try {
      await AuthService.entrarComSenha(telefoneE164: widget.telefoneE164, senha: senha);
      if (!mounted) return;
      // Sessão nova dispara o redirect do router pra '/' (Gate).
      context.go('/');
    } catch (e) {
      setState(() => _erro = 'Senha incorreta. Confira e tente de novo.');
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  /// "Esqueci minha senha" — reusa o SMS já existente como o "código
  /// temporário": ao confirmar o código, o motorista é obrigado a criar
  /// uma senha nova (ver OtpScreen com forcarNovaSenha: true).
  Future<void> _esqueciSenha() async {
    setState(() {
      _enviandoRecuperacao = true;
      _erro = null;
    });
    try {
      await AuthService.enviarCodigo(widget.telefoneE164);
      if (!mounted) return;
      context.push('/otp-redefinir', extra: widget.telefoneE164);
    } catch (e) {
      setState(() => _erro = 'Não consegui enviar o código. Tente de novo em instantes.');
    } finally {
      if (mounted) setState(() => _enviandoRecuperacao = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Digite sua senha')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Celular: ${widget.telefoneE164}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
              const SizedBox(height: 24),
              TextField(
                controller: _senhaController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(hintText: '••••••', counterText: ''),
                onSubmitted: (_) => _entrar(),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _entrando ? null : _entrar,
                child: _entrando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Entrar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _enviandoRecuperacao ? null : _esqueciSenha,
                child: _enviandoRecuperacao
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Esqueci minha senha'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
