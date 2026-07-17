import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/motorista_provider.dart';
import '../theme/app_theme.dart';
import '../../features/dashboard/providers/dashboard_provider.dart';

final _formatoPontosDrawer = NumberFormat.decimalPattern('pt_BR');

// Menu lateral com a identidade FNI — pedido do Daniel (17/07): "criar um
// menu no pwa motorista assim como no pwa cliente, com a Logo FNI, com os
// dados do motorista e com as cores e identidade visual de FNI". Espelha a
// estrutura do sidebar do painel web (fundo escuro frota-950, logo num
// cartão branco, nome do usuário + informação de contexto logo abaixo,
// itens de navegação em lista) — só que como Drawer (aberto pelo ícone
// hamburguer), já que o app é mobile e não tem espaço pra um sidebar fixo
// como no desktop. Busca o próprio perfil (meuPerfilProvider), então pode
// ser adicionado em QUALQUER tela sem precisar passar motoristaId/nome.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfilAsync = ref.watch(meuPerfilProvider);
    final saldoAsync = ref.watch(saldoPontosProvider);

    return Drawer(
      backgroundColor: AppTheme.frota950,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // O logo FNI é escuro sobre fundo branco — "some" se
                  // colocado direto no frota-950, por isso o cartão branco
                  // (mesma solução usada no painel web).
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Image.asset('assets/images/logo-fni.png', height: 32, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 16),
                  perfilAsync.when(
                    data: (perfil) => Text(
                      perfil?.nomeCompleto ?? 'Motorista',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    loading: () => const Text('Carregando...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    error: (e, _) => const Text('Motorista', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                  perfilAsync.maybeWhen(
                    data: (perfil) => perfil?.telefone != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(perfil!.telefone!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          )
                        : const SizedBox.shrink(),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 4),
                  saldoAsync.when(
                    data: (saldo) => Text(
                      'Nível ${nivelParaSaldo(saldo).nome} • ${_formatoPontosDrawer.format(saldo)} pontos',
                      style: const TextStyle(
                        color: AppTheme.frota500,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _ItemMenu(icone: Icons.home_outlined, label: 'Dashboard', onTap: () => _ir(context, '/')),
                  _ItemMenu(
                    icone: Icons.local_gas_station_outlined,
                    label: 'Confirmar abastecimentos',
                    onTap: () => _ir(context, '/pendentes'),
                  ),
                  _ItemMenu(
                    icone: Icons.card_giftcard_outlined,
                    label: 'Catálogo de benefícios',
                    onTap: () => _ir(context, '/catalogo'),
                  ),
                  _ItemMenu(
                    icone: Icons.confirmation_number_outlined,
                    label: 'Meus resgates',
                    onTap: () => _ir(context, '/meus-resgates'),
                  ),
                  _ItemMenu(
                    icone: Icons.receipt_long_outlined,
                    label: 'Extrato de pontos',
                    onTap: () => _ir(context, '/extrato'),
                  ),
                  _ItemMenu(icone: Icons.flag_outlined, label: 'Missões', onTap: () => _ir(context, '/missoes')),
                  _ItemMenu(icone: Icons.leaderboard_outlined, label: 'Ranking', onTap: () => _ir(context, '/ranking')),
                  _ItemMenu(
                    icone: Icons.alt_route_outlined,
                    label: 'Roteirização',
                    onTap: () => _ir(context, '/roteirizacao'),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final perfil = ref.watch(meuPerfilProvider).valueOrNull;
                      return _ItemMenu(
                        icone: Icons.family_restroom_outlined,
                        label: 'Conta Família',
                        onTap: perfil == null ? () {} : () => _ir(context, '/dependentes', extra: perfil.id),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            _ItemMenu(
              icone: Icons.logout,
              label: 'Sair',
              onTap: () {
                Navigator.of(context).pop();
                AuthService.sair();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _ir(BuildContext context, String rota, {Object? extra}) {
    Navigator.of(context).pop();
    context.push(rota, extra: extra);
  }
}

class _ItemMenu extends StatelessWidget {
  final IconData icone;
  final String label;
  final VoidCallback onTap;

  const _ItemMenu({required this.icone, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icone, color: Colors.white70, size: 22),
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      onTap: onTap,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: Colors.white.withValues(alpha: 0.1),
    );
  }
}
