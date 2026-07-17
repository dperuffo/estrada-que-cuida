import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
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
    final indoParaLoginOuOtp = state.matchedLocation == '/login' || state.matchedLocation == '/otp';
    if (sessao == null && !indoParaLoginOuOtp) return '/login';
    if (sessao != null && indoParaLoginOuOtp) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/otp',
      builder: (context, state) => OtpScreen(telefoneE164: state.extra as String),
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
  ],
);
