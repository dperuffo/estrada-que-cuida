import 'dart:async';
import 'package:flutter/material.dart';
import '../providers/auth_provider.dart';
import '../router/app_router.dart';
import 'supabase_service.dart';

// Fase Timeout-Inatividade (21/08/2026, pedido do Daniel: "forçar logout
// após 30 min" nos PWAs) — mesma implementação do app cliente/posto
// (estudo-de-rede/flutter/lib/core/services/inactivity_guard.dart), só
// adaptada pro router deste app (`appRouter` é uma instância única de
// GoRouter, não vem de um Provider do Riverpod aqui). Ver comentário
// completo lá pras 2 camadas (Timer.periodic + WidgetsBindingObserver).
//
// Detalhe a mais deste app: o `appRouter` já tem `refreshListenable`
// ligado a `onAuthStateChange` (ver app_router.dart) — ou seja, assim que
// `signOut()` roda, o próprio GoRouter já reavalia o `redirect` sozinho e
// manda pro /login. O `.go('/login')` abaixo é só reforço/garantia de
// imediatismo, não é estritamente necessário aqui (mas não faz mal).
class InactivityGuard extends StatefulWidget {
  final Widget child;
  const InactivityGuard({super.key, required this.child});

  @override
  State<InactivityGuard> createState() => _InactivityGuardState();
}

class _InactivityGuardState extends State<InactivityGuard>
    with WidgetsBindingObserver {
  static const _tempoLimite = Duration(minutes: 30);
  static const _intervaloChecagem = Duration(seconds: 30);

  Timer? _timer;
  DateTime _ultimaInteracao = DateTime.now();
  bool _deslogando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_intervaloChecagem, (_) => _checarInatividade());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checarInatividade();
    }
  }

  void _registrarInteracao([PointerEvent? _]) {
    _ultimaInteracao = DateTime.now();
  }

  Future<void> _checarInatividade() async {
    if (_deslogando) return;
    if (SupabaseService.client.auth.currentSession == null) return;
    if (DateTime.now().difference(_ultimaInteracao) < _tempoLimite) return;

    _deslogando = true;
    try {
      await AuthService.sair();
      if (mounted) {
        appRouter.go('/login');
      }
    } finally {
      _deslogando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _registrarInteracao,
      onPointerMove: _registrarInteracao,
      onPointerSignal: _registrarInteracao,
      child: widget.child,
    );
  }
}
