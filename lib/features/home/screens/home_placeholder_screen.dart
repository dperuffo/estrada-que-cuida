import 'package:flutter/material.dart';
import '../../../core/providers/auth_provider.dart';

// Placeholder até a próxima fase (Dashboard — saldo, nível, progresso).
// Confirma que o fluxo de login -> vínculo -> adesão terminou certo.
class HomePlaceholderScreen extends StatelessWidget {
  final String? nome;

  const HomePlaceholderScreen({super.key, this.nome});

  @override
  Widget build(BuildContext context) {
    final primeiroNome = (nome ?? '').split(' ').first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estrada que Cuida'),
        actions: [
          IconButton(
            onPressed: () => AuthService.sair(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF1B7A43), size: 56),
              const SizedBox(height: 16),
              Text(
                primeiroNome.isEmpty ? 'Tudo certo!' : 'Tudo certo, $primeiroNome!',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Seu cadastro está confirmado e sua adesão está ativa.\n'
                'O painel de pontos e nível chega na próxima fase.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
