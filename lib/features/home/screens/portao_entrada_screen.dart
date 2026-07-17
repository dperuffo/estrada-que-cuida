import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/motorista_provider.dart';
import '../../adesao/screens/adesao_screen.dart';
import '../../vinculo/screens/vinculo_screen.dart';
import '../../auth/screens/criar_senha_screen.dart';
import '../../dashboard/screens/dashboard_screen.dart';

// Rota "/" — decide o que mostrar assim que existe sessão (pós-OTP):
// 1. Ainda não vinculado a um cadastro de motorista -> VinculoScreen (pede CPF).
// 2. Vinculado mas ainda sem senha cadastrada (primeiro acesso) ->
//    CriarSenhaScreen (obrigatório, Fase login-por-senha).
// 3. Vinculado, com senha, mas sem adesão ativa -> AdesaoScreen.
// 4. Vinculado, com senha e aderido -> DashboardScreen (saldo, nível, atalhos).
class PortaoEntradaScreen extends ConsumerWidget {
  const PortaoEntradaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vinculoAsync = ref.watch(vinculoProvider(null));

    return vinculoAsync.when(
      loading: () => const _Carregando(),
      error: (e, _) => _Erro(onTentarNovamente: () => ref.invalidate(vinculoProvider(null))),
      data: (resultado) {
        switch (resultado.status) {
          case 'vinculado':
          case 'ja_vinculado':
            if (!resultado.senhaDefinida) {
              return CriarSenhaScreen(onSalvo: () => ref.invalidate(vinculoProvider(null)));
            }
            return _PosVinculo(motoristaId: resultado.motoristaId!, nome: resultado.nome);
          case 'ambiguo_requer_cpf':
          case 'nao_encontrado':
            return VinculoScreen(statusInicial: resultado.status);
          default:
            // sem_telefone_na_sessao / nao_autenticado — estado inesperado,
            // mais seguro é derrubar a sessão e voltar pro login.
            AuthService.sair();
            return const _Carregando();
        }
      },
    );
  }
}

class _PosVinculo extends ConsumerWidget {
  final String motoristaId;
  final String? nome;

  const _PosVinculo({required this.motoristaId, this.nome});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adesaoAsync = ref.watch(adesaoAtivaProvider);
    return adesaoAsync.when(
      loading: () => const _Carregando(),
      error: (e, _) => _Erro(onTentarNovamente: () => ref.invalidate(adesaoAtivaProvider)),
      data: (aderido) {
        if (!aderido) return AdesaoScreen(motoristaId: motoristaId, nome: nome);
        return DashboardScreen(motoristaId: motoristaId, nome: nome);
      },
    );
  }
}

class _Carregando extends StatelessWidget {
  const _Carregando();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _Erro extends StatelessWidget {
  final VoidCallback onTentarNovamente;

  const _Erro({required this.onTentarNovamente});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Não consegui carregar seus dados agora.'),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: onTentarNovamente, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      ),
    );
  }
}
