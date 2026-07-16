import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/home/screens/portao_entrada_screen.dart';

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
  ],
);
