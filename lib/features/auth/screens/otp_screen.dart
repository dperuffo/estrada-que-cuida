import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/auth_provider.dart';

import '../../../core/theme/app_theme.dart';

// Tela 2 do login — motorista digita o código de 6 dígitos recebido por
// SMS. Ao confirmar, o Supabase cria a sessão (auth.uid()); dali em
// diante a RLS e a RPC de vínculo já enxergam esse usuário.
//
// Fase login-por-senha: quando `forcarNovaSenha` é true (veio do fluxo
// "esqueci minha senha" na SenhaLoginScreen), o SMS funciona como o
// "código temporário" — ao confirmar, vamos direto pra '/definir-senha'
// em vez de '/' , obrigando a criar uma senha nova antes de continuar.
class OtpScreen extends StatefulWidget {
  final String telefoneE164;
  final bool forcarNovaSenha;

  const OtpScreen({
    super.key,
    required this.telefoneE164,
    this.forcarNovaSenha = false,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controller = TextEditingController();
  bool _confirmando = false;
  bool _reenviando = false;
  String? _erro;

  Future<void> _confirmar() async {
    final codigo = _controller.text.trim();
    if (codigo.length < 4) {
      setState(() => _erro = 'Digite o código recebido por SMS.');
      return;
    }
    setState(() {
      _confirmando = true;
      _erro = null;
    });
    try {
      await AuthService.confirmarCodigo(
        telefoneE164: widget.telefoneE164,
        codigo: codigo,
      );
      if (!mounted) return;
      if (widget.forcarNovaSenha) {
        // Fluxo "esqueci minha senha": SMS confirmado só prova que o
        // celular é dele — ainda falta cadastrar a senha nova.
        context.go('/definir-senha');
        return;
      }
      // A sessão nova dispara o redirect do router pra '/' (Gate), que
      // decide se falta vínculo, senha, adesão, ou já vai pro início.
      context.go('/');
    } on AuthException catch (e) {
      // otp_expired etc. ganham mensagem própria; código só errado continua
      // com a mensagem padrão de "confira e tente de novo".
      setState(
        () => _erro = e.code == 'otp_expired'
            ? AuthService.mensagemDeErro(e, contexto: 'otp')
            : 'Código incorreto ou expirado. Confira e tente de novo.',
      );
    } catch (e) {
      setState(() => _erro = AuthService.mensagemDeErro(e, contexto: 'otp'));
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  Future<void> _reenviar() async {
    setState(() => _reenviando = true);
    try {
      await AuthService.enviarCodigo(widget.telefoneE164);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Código reenviado.')));
    } catch (e) {
      // Antes o reenvio não tinha catch — falha do Twilio estourava sem
      // aviso nenhum pro motorista.
      if (!mounted) return;
      setState(
        () => _erro = AuthService.mensagemDeErro(e, contexto: 'otp-reenvio'),
      );
    } finally {
      if (mounted) setState(() => _reenviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Confirme o código'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enviamos um código por SMS para ${widget.telefoneE164}.'),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(hintText: '••••••'),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _confirmando ? null : _confirmar,
                child: _confirmando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Confirmar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _reenviando ? null : _reenviar,
                child: const Text('Reenviar código'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
