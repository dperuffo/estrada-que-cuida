import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/auth_provider.dart';

// Fase MFA-opcional — "Camada 2" do login (rota /mfa-verificar): só é
// alcançada pelo redirect do router quando a sessão está em aal1 mas o
// motorista tem um fator TOTP verificado (nextLevel aal2). Pede o código
// de 6 dígitos do app autenticador antes de liberar o resto do app.
class MfaVerificarScreen extends StatefulWidget {
  const MfaVerificarScreen({super.key});

  @override
  State<MfaVerificarScreen> createState() => _MfaVerificarScreenState();
}

class _MfaVerificarScreenState extends State<MfaVerificarScreen> {
  final _codigoCtrl = TextEditingController();
  bool _verificando = false;
  String? _erro;
  String? _factorId;

  @override
  void initState() {
    super.initState();
    _carregarFator();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarFator() async {
    try {
      final fatores = await AuthService.mfaListarFatores();
      final verificado = fatores.totp.where((f) => f.status == FactorStatus.verified);
      if (verificado.isEmpty) {
        // Estado inesperado (fator foi desativado em outro dispositivo
        // entre o login e essa tela) — mais seguro é sair.
        await AuthService.sair();
        return;
      }
      setState(() => _factorId = verificado.first.id);
    } catch (_) {
      setState(() => _erro = 'Não consegui carregar a verificação. Tente de novo.');
    }
  }

  Future<void> _verificar() async {
    final factorId = _factorId;
    if (factorId == null) return;
    final codigo = _codigoCtrl.text.trim();
    if (codigo.length != 6) {
      setState(() => _erro = 'Digite o código de 6 dígitos do app autenticador.');
      return;
    }
    setState(() {
      _verificando = true;
      _erro = null;
    });
    try {
      await AuthService.mfaVerificarCodigo(factorId: factorId, codigo: codigo);
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      setState(() {
        _erro = 'Código incorreto ou expirado. Confira no app autenticador.';
        _verificando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificação em duas etapas'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Digite o código de 6 dígitos gerado pelo seu app autenticador.'),
              const SizedBox(height: 24),
              TextField(
                controller: _codigoCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(fontSize: 24, letterSpacing: 6),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(hintText: '000000', counterText: ''),
                onSubmitted: (_) => _verificar(),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: (_verificando || _factorId == null) ? null : _verificar,
                child: _verificando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verificar'),
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
