import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/services/inactivity_guard.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tema_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.init();
  runApp(const ProviderScope(child: EstradaQueCuidaApp()));
}

class EstradaQueCuidaApp extends StatelessWidget {
  const EstradaQueCuidaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return TemaHost(
      builder: (context, modo) => MaterialApp.router(
        title: 'Estrada que Cuida',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.temaClaro,
        darkTheme: AppTheme.temaEscuro,
        themeMode: modo,
        routerConfig: appRouter,
        // Fase Timeout-Inatividade (21/08/2026) — ver inactivity_guard.dart.
        builder: (context, child) =>
            InactivityGuard(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
