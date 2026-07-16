import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/auth_provider.dart';

// Tela 2 do login — motorista digita o código de 6 dígitos recebido por
// SMS. Ao confirmar, o Supabase cria a sessão (auth.uid()); dali em
// diante a RLS e a RPC de vínculo já enxergam esse usuário.
class OtpScreen extends StatefulWidget {
  final String telefoneE164;

  const OtpScreen({super.key, required this.telefoneE164});

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
      await AuthService.confirmarCodigo(telefoneE164: widget.telefoneE164, codigo: codigo);
      if (!mounted) return;
      // A sessão nova dispara o redirect do router pra '/' (Gate), que
      // decide se falta vínculo, adesão, ou já vai pro início.
      context.go('/');
    } catch (e) {
      setState(() => _erro = 'Código incorreto ou expirado. Confira e tente de novo.');
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  Future<void> _reenviar() async {
    setState(() => _reenviando = true);
    try {
      await AuthService.enviarCodigo(widget.telefoneE164);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código reenviado.')));
    } finally {
      if (mounted) setState(() => _reenviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirme o código')),
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
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
