import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/catalogo_provider.dart';

final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

const Map<String, String> _labelStatus = {
  'solicitado': 'Solicitado',
  'em_andamento': 'Em andamento',
  'concluido': 'Concluído',
  'cancelado': 'Cancelado',
};

const Map<String, Color> _corStatus = {
  'solicitado': Colors.black54,
  'em_andamento': Color(0xFF9E7A00),
  'concluido': Color(0xFF1B7A43),
  'cancelado': Colors.redAccent,
};

class MeusResgatesScreen extends ConsumerWidget {
  const MeusResgatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resgatesAsync = ref.watch(meusResgatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meus resgates')),
      body: resgatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não consegui carregar seus resgates agora.'),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () => ref.invalidate(meusResgatesProvider), child: const Text('Tentar de novo')),
              ],
            ),
          ),
        ),
        data: (resgates) {
          if (resgates.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Você ainda não resgatou nenhum item do catálogo.', textAlign: TextAlign.center),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(meusResgatesProvider),
            child: ListView.separated(
              itemCount: resgates.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = resgates[i];
                return ListTile(
                  title: Text(r.titulo),
                  subtitle: Text('${_formatoData.format(r.solicitadoEm)} • ${r.pontosGastos} pontos'),
                  trailing: Text(
                    _labelStatus[r.status] ?? r.status,
                    style: TextStyle(color: _corStatus[r.status] ?? Colors.black54, fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
