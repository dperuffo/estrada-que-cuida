import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/senha_login_screen.dart';
import '../../features/auth/screens/criar_senha_screen.dart';
import '../../features/home/screens/portao_entrada_screen.dart';
import '../../features/abastecimentos/screens/abastecimentos_pendentes_screen.dart';
import '../../features/extrato/screens/extrato_screen.dart';
import '../../features/gamificacao/screens/ranking_screen.dart';
import '../../features/gamificacao/screens/missoes_screen.dart';
import '../../features/catalogo/screens/catalogo_screen.dart';
import '../../features/catalogo/screens/meus_resgates_screen.dart';
import '../../features/dependentes/screens/dependentes_screen.dart';
import '../../features/roteirizacao/screens/roteirizacao_screen.dart';
import '../../features/fretes/screens/fretes_screen.dart';
import '../../features/fretes/screens/frete_detalhe_screen.dart';
import '../../features/financeiro/screens/financeiro_screen.dart';
import '../../features/chamados/screens/chamados_screen.dart';
import '../../features/chamados/screens/chamado_novo_screen.dart';
import '../../features/chamados/screens/chamado_detalhe_screen.dart';
import '../../features/avaliacao/screens/avaliar_screen.dart';
import '../../features/seguranca/screens/seguranca_screen.dart';
import '../../features/seguranca/screens/mfa_verificar_screen.dart';
import '../../features/avisos/screens/avisos_screen.dart';
import '../../features/inspecao_veicular/screens/inspecao_veicular_screen.dart';

// Faz o GoRouter reavaliar o `redirect` sempre que a sessão do Supabase
// muda (login/logout) — sem isso, o router só re-checa em navegações
// explícitas.
class _GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _sub;

  _GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: _GoRouterRefreshStream(SupabaseService.client.auth.onAuthStateChange),
  redirect: (context, state) {
    final sessao = SupabaseService.client.auth.currentSession;
    // Fase login-por-senha: '/senha' e '/otp-redefinir' também são
    // alcançados SEM sessão ainda (é ali que ela é criada), então entram
    // no mesmo grupo de '/login' e '/otp' pro redirect não expulsar o
    // motorista de volta pro login no meio do fluxo.
    final indoParaLoginOuOtp = state.matchedLocation == '/login' ||
        state.matchedLocation == '/otp' ||
        state.matchedLocation == '/senha' ||
        state.matchedLocation == '/otp-redefinir';
    if (sessao == null && !indoParaLoginOuOtp) return '/login';
    if (sessao != null && indoParaLoginOuOtp) return '/';

    // Fase MFA-opcional — "Camada 2": se o motorista tem um fator TOTP
    // verificado mas essa sessão ainda está em aal1 (acabou de logar com
    // telefone/senha e não confirmou o app autenticador ainda), força a
    // tela de código antes de liberar qualquer outra rota. Síncrono e
    // barato (getAuthenticatorAssuranceLevel não bate na rede).
    if (sessao != null) {
      final aal = SupabaseService.client.auth.mfa.getAuthenticatorAssuranceLevel();
      final precisaVerificarMfa =
          aal.nextLevel == AuthenticatorAssuranceLevels.aal2 && aal.currentLevel != AuthenticatorAssuranceLevels.aal2;
      final indoParaMfa = state.matchedLocation == '/mfa-verificar';
      if (precisaVerificarMfa && !indoParaMfa) return '/mfa-verificar';
      if (!precisaVerificarMfa && indoParaMfa) return '/';
    }

    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/otp',
      builder: (context, state) => OtpScreen(telefoneE164: state.extra as String),
    ),
    GoRoute(
      path: '/senha',
      builder: (context, state) => SenhaLoginScreen(telefoneE164: state.extra as String),
    ),
    GoRoute(
      path: '/otp-redefinir',
      builder: (context, state) => OtpScreen(telefoneE164: state.extra as String, forcarNovaSenha: true),
    ),
    GoRoute(
      path: '/definir-senha',
      builder: (context, state) => CriarSenhaScreen(onSalvo: () => context.go('/'), redefinicao: true),
    ),
    GoRoute(path: '/', builder: (context, state) => const PortaoEntradaScreen()),
    GoRoute(path: '/pendentes', builder: (context, state) => const AbastecimentosPendentesScreen()),
    GoRoute(path: '/extrato', builder: (context, state) => const ExtratoScreen()),
    GoRoute(path: '/ranking', builder: (context, state) => const RankingScreen()),
    GoRoute(path: '/missoes', builder: (context, state) => const MissoesScreen()),
    GoRoute(path: '/catalogo', builder: (context, state) => CatalogoScreen(categoriaInicial: state.extra as String?)),
    GoRoute(path: '/meus-resgates', builder: (context, state) => const MeusResgatesScreen()),
    GoRoute(path: '/dependentes', builder: (context, state) => DependentesScreen(motoristaId: state.extra as String)),
    GoRoute(path: '/roteirizacao', builder: (context, state) => const RoteirizacaoScreen()),
    GoRoute(path: '/fretes', builder: (context, state) => const FretesScreen()),
    GoRoute(
      path: '/fretes/:id',
      builder: (context, state) => FreteDetalheScreen(freteId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/financeiro', builder: (context, state) => const FinanceiroScreen()),
    GoRoute(path: '/chamados', builder: (context, state) => const ChamadosScreen()),
    GoRoute(path: '/chamados/novo', builder: (context, state) => const ChamadoNovoScreen()),
    GoRoute(
      path: '/chamados/:id',
      builder: (context, state) => ChamadoDetalheScreen(ticketId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/avaliar', builder: (context, state) => const AvaliarScreen()),
    GoRoute(path: '/seguranca', builder: (context, state) => const SegurancaScreen()),
    GoRoute(path: '/mfa-verificar', builder: (context, state) => const MfaVerificarScreen()),
    // Fase Central-Avisos (28/07/2026) — pedido do Daniel: "Central de
    // Avisos é uma funcionalidade do admin da aplicação para os clientes,
    // motoristas e postos".
    GoRoute(path: '/avisos', builder: (context, state) => const AvisosScreen()),
    // Fase Inspeção-pelo-Motorista (30/07/2026) — checklist de segurança
    // que o motorista preenche rotineiramente, virando engajamento de
    // fidelidade (RPC registrar_inspecao_motorista).
    GoRoute(path: '/inspecao-veicular', builder: (context, state) => const InspecaoVeicularScreen()),
  ],
);
