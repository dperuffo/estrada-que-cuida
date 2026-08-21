import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/motorista_provider.dart';
import '../theme/app_theme.dart';
import '../../features/dashboard/providers/dashboard_provider.dart';

final _formatoPontosDrawer = NumberFormat.decimalPattern('pt_BR');

// Máscara de telefone (Fase Segurança-2) — pedido do Daniel: "ajustar a
// máscara do telefone no menu principal". `motoristas.telefone` vem com
// formatos inconsistentes conforme a origem do cadastro (alguns já
// importados como "(11) 98569-7865", outros como dígitos crus
// "21909087653") — em vez de confiar no que já veio pronto, extrai só os
// dígitos e remonta sempre no mesmo padrão brasileiro.
String _formatarTelefone(String bruto) {
  var digitos = bruto.replaceAll(RegExp(r'\D'), '');
  // Remove o "55" do Brasil quando vier junto (ex.: telefoneE164 sem o "+",
  // 13 dígitos no total) — a máscara mostra só DDD + número, sem o país.
  if (digitos.length == 13 && digitos.startsWith('55')) {
    digitos = digitos.substring(2);
  }
  if (digitos.length == 11) {
    return '(${digitos.substring(0, 2)}) ${digitos.substring(2, 7)}-${digitos.substring(7)}';
  }
  if (digitos.length == 10) {
    return '(${digitos.substring(0, 2)}) ${digitos.substring(2, 6)}-${digitos.substring(6)}';
  }
  return bruto; // formato inesperado — mostra como veio, não quebra a tela
}

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
      backgroundColor: Colors.transparent,
      // Fase Liquid-Glass-PWA (20/08/2026, pedido do Daniel: "implementar
      // estas mudanças nos PWAs cliente e motorista") — todo o Drawer vira
      // uma única superfície bronze/champanhe contínua, igual ao <aside> da
      // web (e ao Drawer já atualizado do PWA cliente). Sem blur literal:
      // o drawer do celular fica sobre um scrim escuro, não sobre
      // conteúdo real pra desfocar.
      child: Container(
        decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Image.asset(
                        'assets/images/logo-fni.png',
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 16),
                    perfilAsync.when(
                      data: (perfil) => Text(
                        perfil?.nomeCompleto ?? 'Motorista',
                        style: const TextStyle(
                          color: AppTheme.glassTexto,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      loading: () => const Text(
                        'Carregando...',
                        style: TextStyle(
                          color: AppTheme.glassTextoMuted,
                          fontSize: 14,
                        ),
                      ),
                      error: (e, _) => const Text(
                        'Motorista',
                        style: TextStyle(
                          color: AppTheme.glassTexto,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    perfilAsync.maybeWhen(
                      data: (perfil) => perfil?.telefone != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _formatarTelefone(perfil!.telefone!),
                                style: const TextStyle(
                                  color: AppTheme.glassTextoMuted,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                      orElse: () => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 4),
                    saldoAsync.when(
                      data: (saldo) => Text(
                        'Nível ${nivelParaSaldo(saldo).nome} • ${_formatoPontosDrawer.format(saldo)} pontos',
                        style: const TextStyle(
                          color: AppTheme.glassAcento,
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
              const Divider(color: Colors.white24, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  // Fase reorganizacao-menu (04/08/2026, pedido do Daniel:
                  // "propor uma reorganizacao de menu no pwa motorista, com
                  // base no que foi implementado no pwa do cliente") — antes
                  // era uma lista única com 16 itens sem nenhuma divisão,
                  // mesmo problema que motivou o reagrupamento do menu do
                  // cliente/posto (ver home_screen.dart/posto_home_screen.dart
                  // no repo estudo-de-rede e layout.tsx na web). Mesma rota,
                  // ícone, badge e comentário de fase de cada item — só mudou
                  // em qual grupo está.
                  children: [
                    _grupo('Visão Geral'),
                    _ItemMenu(
                      icone: Icons.home_outlined,
                      label: 'Dashboard',
                      onTap: () => _ir(context, '/'),
                    ),

                    _grupo('Minhas Tarefas'),
                    _ItemMenu(
                      icone: Icons.local_gas_station_outlined,
                      label: 'Confirmar abastecimentos',
                      onTap: () => _ir(context, '/pendentes'),
                    ),
                    // Fase Inspeção-pelo-Motorista (30/07/2026) — pedido do
                    // Daniel: checklist de segurança do veículo, feito pelo
                    // próprio motorista, rotineiramente.
                    _ItemMenu(
                      icone: Icons.fact_check_outlined,
                      label: 'Checklist de inspeção',
                      onTap: () => _ir(context, '/inspecao-veicular'),
                    ),
                    // Fase Abastecimento-Interno (21/08/2026) — pedido do
                    // Daniel: confirmação, pelo motorista, do abastecimento
                    // feito na garagem própria da empresa (matriz/filial).
                    _ItemMenu(
                      icone: Icons.warehouse_outlined,
                      label: 'Abastecimento Interno',
                      onTap: () => _ir(context, '/abastecimento-interno'),
                    ),
                    _ItemMenu(
                      icone: Icons.alt_route_outlined,
                      label: 'Roteirização',
                      onTap: () => _ir(context, '/roteirizacao'),
                    ),
                    _ItemMenu(
                      icone: Icons.local_shipping_outlined,
                      label: 'Fretes',
                      onTap: () => _ir(context, '/fretes'),
                    ),

                    _grupo('Financeiro'),
                    _ItemMenu(
                      icone: Icons.account_balance_wallet_outlined,
                      label: 'Financeiro',
                      onTap: () => _ir(context, '/financeiro'),
                    ),

                    _grupo('Recompensas e Engajamento'),
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
                    _ItemMenu(
                      icone: Icons.flag_outlined,
                      label: 'Missões',
                      onTap: () => _ir(context, '/missoes'),
                    ),
                    _ItemMenu(
                      icone: Icons.leaderboard_outlined,
                      label: 'Ranking',
                      onTap: () => _ir(context, '/ranking'),
                    ),

                    _grupo('Conta e Ajuda'),
                    // Fase Central-Avisos (28/07/2026) — pedido do Daniel:
                    // "Central de Avisos é uma funcionalidade do admin da
                    // aplicação para os clientes, motoristas e postos". O
                    // sino (com badge) já fica no AppBar do Dashboard; aqui
                    // no Drawer (reaproveitado em toda tela) garante acesso
                    // mesmo fora da Home.
                    _ItemMenu(
                      icone: Icons.notifications_outlined,
                      label: 'Avisos',
                      onTap: () => _ir(context, '/avisos'),
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final perfil = ref.watch(meuPerfilProvider).valueOrNull;
                        return _ItemMenu(
                          icone: Icons.family_restroom_outlined,
                          label: 'Conta Família',
                          onTap: perfil == null
                              ? () {}
                              : () => _ir(
                                  context,
                                  '/dependentes',
                                  extra: perfil.id,
                                ),
                        );
                      },
                    ),
                    _ItemMenu(
                      icone: Icons.confirmation_number_outlined,
                      label: 'Chamados',
                      onTap: () => _ir(context, '/chamados'),
                    ),
                    _ItemMenu(
                      icone: Icons.star_outline,
                      label: 'Avaliar o app',
                      onTap: () => _ir(context, '/avaliar'),
                    ),
                    _ItemMenu(
                      icone: Icons.shield_outlined,
                      label: 'Segurança',
                      onTap: () => _ir(context, '/seguranca'),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
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
      ),
    );
  }

  void _ir(BuildContext context, String rota, {Object? extra}) {
    Navigator.of(context).pop();
    context.push(rota, extra: extra);
  }
}

// Fase reorganizacao-menu — cabeçalho de grupo temático, mesmo padrão visual
// (texto pequeno, maiúsculo, opaco) usado em home_screen.dart/
// posto_home_screen.dart (estudo-de-rede) e GrupoMenuLateral.tsx (web).
Widget _grupo(String label) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
  child: Text(
    label.toUpperCase(),
    style: const TextStyle(
      color: AppTheme.glassTextoMuted,
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.5,
    ),
  ),
);

class _ItemMenu extends StatelessWidget {
  final IconData icone;
  final String label;
  final VoidCallback onTap;

  const _ItemMenu({
    required this.icone,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icone, color: AppTheme.glassIcone, size: 22),
      title: Text(
        label,
        style: const TextStyle(color: AppTheme.glassTexto, fontSize: 14),
      ),
      onTap: onTap,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: Colors.white.withValues(alpha: 0.1),
    );
  }
}
