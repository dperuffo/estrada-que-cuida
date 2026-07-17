import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/providers/auth_provider.dart';

// Fase login-por-senha — tela de criação/redefinição da senha numérica de
// 6 dígitos. Reusada em dois lugares:
// 1. Inline no "portão" (PortaoEntradaScreen), pro motorista recém-vinculado
//    que ainda não tem senha (senha_definida = false) — obrigatório, sem
//    como pular.
// 2. Como rota '/definir-senha' no fluxo de "esqueci minha senha", depois
//    do motorista confirmar o código de SMS (ver OtpScreen).
class CriarSenhaScreen extends StatefulWidget {
  final VoidCallback onSalvo;
  final bool redefinicao;

  const CriarSenhaScreen({super.key, required this.onSalvo, this.redefinicao = false});

  @override
  State<CriarSenhaScreen> createState() => _CriarSenhaScreenState();
}

class _CriarSenhaScreenState extends State<CriarSenhaScreen> {
  final _senhaController = TextEditingController();
  final _confirmarController = TextEditingController();
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _senhaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final senha = _senhaController.text.trim();
    final confirmar = _confirmarController.text.trim();
    if (senha.length != 6) {
      setState(() => _erro = 'A senha precisa ter exatamente 6 números.');
      return;
    }
    if (senha != confirmar) {
      setState(() => _erro = 'As senhas digitadas são diferentes.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await AuthService.definirSenha(senha);
      widget.onSalvo();
    } catch (e) {
      setState(() => _erro = 'Não consegui salvar a senha agora. Tente de novo em instantes.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.redefinicao ? 'Crie uma nova senha' : 'Crie sua senha')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.redefinicao
                    ? 'Confirmamos seu celular. Agora crie uma nova senha numérica de 6 dígitos pra usar nos próximos acessos.'
                    : 'A partir de agora você entra com seu celular e uma senha numérica de 6 dígitos, sem precisar de SMS toda vez.',
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _senhaController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Nova senha', hintText: '••••••', counterText: ''),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmarController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Confirme a senha', hintText: '••••••', counterText: ''),
                onSubmitted: (_) => _salvar(),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                child: _salvando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Salvar senha'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
