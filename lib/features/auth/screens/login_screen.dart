import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/auth_provider.dart';

// Tela 1 do app — motorista digita o celular (com DDD). Sem cadastro aqui:
// o cadastro (nome, CPF, CNH) já existe em `motoristas`, feito pela empresa
// dele. Fase login-por-senha: se esse celular já tem senha cadastrada
// (`motorista_tem_senha`), pedimos a senha (SenhaLoginScreen); senão é
// primeiro acesso e mandamos o código por SMS (OtpScreen), que depois
// obriga a criação da senha.
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

  Future<void> _continuar() async {
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
      // Fase login-por-senha: primeiro acesso continua sendo só SMS; nos
      // acessos seguintes (já com senha cadastrada) pedimos a senha em vez
      // de mandar SMS de novo.
      final jaTemSenha = await AuthService.temSenha(telefone);
      if (!mounted) return;
      if (jaTemSenha) {
        context.push('/senha', extra: telefone);
        return;
      }
      await AuthService.enviarCodigo(telefone);
      if (!mounted) return;
      context.push('/otp', extra: telefone);
    } catch (e) {
      // Mensagem específica por tipo de erro (sms_send_failed, rate limit
      // etc.) + log do erro real no console — ver AuthService.mensagemDeErro.
      setState(() => _erro = AuthService.mensagemDeErro(e, contexto: 'login'));
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
              // Logo FNI em destaque (Fase 17/07, pedido do Daniel: "logo
              // FNI imponente" no lugar do ícone de caminhão provisório).
              Image.asset('assets/images/logo-fni.png', height: 110, fit: BoxFit.contain),
              const SizedBox(height: 24),
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
                onPressed: _enviando ? null : _continuar,
                child: _enviando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Continuar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
