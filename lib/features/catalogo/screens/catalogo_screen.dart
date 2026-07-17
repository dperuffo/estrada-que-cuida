import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../dependentes/providers/dependentes_provider.dart';
import '../providers/catalogo_provider.dart';
import '../widgets/card_voucher.dart';

final _formatoPontos = NumberFormat.decimalPattern('pt_BR');

class CatalogoScreen extends ConsumerStatefulWidget {
  /// Se vier preenchida, a tela já abre filtrada nessa categoria (usado
  /// pelo atalho "Volte para casa" do Dashboard).
  final String? categoriaInicial;

  const CatalogoScreen({super.key, this.categoriaInicial});

  @override
  ConsumerState<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends ConsumerState<CatalogoScreen> {
  String? _categoria;

  @override
  void initState() {
    super.initState();
    _categoria = widget.categoriaInicial;
  }

  Future<void> _resgatar(ItemCatalogo item) async {
    final dependentes = await ref.read(dependentesProvider.future);
    if (!mounted) return;

    String? dependenteId;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(item.titulo),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resgatar por ${_formatoPontos.format(item.pontosNecessarios)} pontos?'),
              if (dependentes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Para quem?', style: TextStyle(fontWeight: FontWeight.bold)),
                RadioGroup<String?>(
                  groupValue: dependenteId,
                  onChanged: (v) => setState(() => dependenteId = v),
                  child: Column(
                    children: [
                      const RadioListTile<String?>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Para mim'),
                        value: null,
                      ),
                      ...dependentes.map((d) => RadioListTile<String?>(
                            contentPadding: EdgeInsets.zero,
                            title: Text(d.nome),
                            value: d.id,
                          )),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Resgatar')),
          ],
        ),
      ),
    );
    if (confirmar != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final resultado = await CatalogoService.resgatar(itemId: item.id, dependenteId: dependenteId);
      switch (resultado.status) {
        case 'ok':
          messenger.showSnackBar(const SnackBar(content: Text('Resgate feito! Acompanhe o status em "Meus resgates".')));
          break;
        case 'saldo_insuficiente':
          messenger.showSnackBar(SnackBar(
            content: Text('Saldo insuficiente — você tem ${resultado.saldo}, precisa de ${resultado.necessario}.'),
          ));
          break;
        case 'nao_aderido':
          messenger.showSnackBar(const SnackBar(content: Text('Sua adesão ao programa não está ativa.')));
          break;
        default:
          messenger.showSnackBar(const SnackBar(content: Text('Não foi possível resgatar esse item agora.')));
      }
      ref.invalidate(saldoPontosProvider);
      ref.invalidate(meusResgatesProvider);
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Não consegui resgatar agora. Tente de novo em instantes.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogoAsync = ref.watch(catalogoProvider(_categoria));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo'),
        actions: [
          IconButton(
            onPressed: () => context.push('/meus-resgates'),
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Meus resgates',
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _ChipCategoria(label: 'Todas', selecionado: _categoria == null, onTap: () => setState(() => _categoria = null)),
                ...categoriasCatalogo.map(
                  (c) => _ChipCategoria(
                    label: c.label,
                    selecionado: _categoria == c.codigo,
                    onTap: () => setState(() => _categoria = c.codigo),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: catalogoAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Não consegui carregar o catálogo agora.'),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: () => ref.invalidate(catalogoProvider(_categoria)), child: const Text('Tentar de novo')),
                    ],
                  ),
                ),
              ),
              data: (itens) {
                if (itens.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhum item disponível nessa categoria ainda.', textAlign: TextAlign.center),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: itens.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final item = itens[i];
                    return CardVoucher(
                      titulo: item.titulo,
                      descricao: item.descricao,
                      categoria: item.categoria,
                      parceiroNome: item.parceiroNome,
                      pontos: item.pontosNecessarios,
                      imagemUrl: item.imagemUrl,
                      acoes: Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          // Sobrescreve o `minimumSize: Size.fromHeight(48)`
                          // do tema global (largura cheia, pensado pros
                          // botões de login/adesão) — aqui o botão precisa
                          // ficar do tamanho do texto (ver footgun
                          // documentado em app_theme.dart).
                          style: ElevatedButton.styleFrom(minimumSize: const Size(64, 40)),
                          onPressed: () => _resgatar(item),
                          child: const Text('Resgatar'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipCategoria extends StatelessWidget {
  final String label;
  final bool selecionado;
  final VoidCallback onTap;

  const _ChipCategoria({required this.label, required this.selecionado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(label: Text(label), selected: selecionado, onSelected: (_) => onTap()),
    );
  }
}
