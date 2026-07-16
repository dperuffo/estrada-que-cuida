import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.init();
  runApp(const ProviderScope(child: EstradaQueCuidaApp()));
}

class EstradaQueCuidaApp extends StatelessWidget {
  const EstradaQueCuidaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Estrada que Cuida',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.tema,
      routerConfig: appRouter,
    );
  }
}
