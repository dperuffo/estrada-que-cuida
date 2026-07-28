import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/avisos_provider.dart';

// Fase Central-Avisos (28/07/2026) — sino no AppBar do Dashboard (única tela
// deste app com um "shell" fixo pós-login), com badge de não lidos.
// Complementado por um item "Avisos" no AppDrawer (reaproveitado em toda
// tela), já que aqui não existe um AppBar único compartilhado como nos
// shells do estudo-de-rede/flutter.
class SinoAvisos extends ConsumerWidget {
  const SinoAvisos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final naoLidos = ref.watch(avisosNaoLidosProvider);

    return IconButton(
      tooltip: 'Avisos',
      onPressed: () => context.push('/avisos'),
      icon: Badge(
        label: Text('$naoLidos'),
        isLabelVisible: naoLidos > 0,
        backgroundColor: const Color(0xFFEF4444),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
