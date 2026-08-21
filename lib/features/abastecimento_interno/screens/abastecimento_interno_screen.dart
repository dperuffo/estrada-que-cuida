import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/abastecimento_interno_provider.dart';

// Fase Abastecimento-Interno (21/08/2026, pedido do Daniel) — aba do PWA
// Motorista pra confirmar um abastecimento feito na garagem/tanque próprio
// da empresa (matriz ou filial), antes de sair pra rota. Mesmo estilo visual
// de InspecaoVeicularScreen (AppBar com o gradiente "liquid glass", Drawer
// padrão, formulário simples + confirmação por SnackBar).
class AbastecimentoInternoScreen extends ConsumerStatefulWidget {
  const AbastecimentoInternoScreen({super.key});

  @override
  ConsumerState<AbastecimentoInternoScreen> createState() =>
      _AbastecimentoInternoScreenState();
}

class _AbastecimentoInternoScreenState
    extends ConsumerState<AbastecimentoInternoScreen> {
  String? _empresaId;
  String? _placa;
  String? _combustivel;
  final _quantidadeCtrl = TextEditingController();
  final _arlaQuantidadeCtrl = TextEditingController();
  final _hodometroCtrl = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _quantidadeCtrl.dispose();
    _arlaQuantidadeCtrl.dispose();
    _hodometroCtrl.dispose();
    super.dispose();
  }

  bool get _ehDiesel =>
      (_combustivel ?? '').toLowerCase().startsWith('diesel');

  Future<void> _enviar(OpcoesAbastecimentoInterno opcoes) async {
    if (_empresaId == null) {
      setState(() => _erro = 'Selecione a empresa onde o abastecimento foi feito.');
      return;
    }
    if (_placa == null) {
      setState(() => _erro = 'Selecione o veículo.');
      return;
    }
    if (_combustivel == null) {
      setState(() => _erro = 'Selecione o combustível abastecido.');
      return;
    }
    final quantidade = num.tryParse(_quantidadeCtrl.text.replaceAll(',', '.'));
    if (quantidade == null || quantidade <= 0) {
      setState(() => _erro = 'Informe a quantidade abastecida (litros).');
      return;
    }
    final arlaQuantidade = _arlaQuantidadeCtrl.text.trim().isEmpty
        ? null
        : num.tryParse(_arlaQuantidadeCtrl.text.replaceAll(',', '.'));
    final hodometro = _hodometroCtrl.text.trim().isEmpty
        ? null
        : num.tryParse(_hodometroCtrl.text.replaceAll(',', '.'));

    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final resultado = await AbastecimentoInternoService.registrar(
        empresaId: _empresaId!,
        placa: _placa!,
        combustivel: _combustivel!,
        quantidade: quantidade,
        arlaQuantidade: arlaQuantidade,
        hodometro: hodometro,
      );

      if (!mounted) return;

      switch (resultado.status) {
        case 'registrado':
          final total = resultado.valorTotal ?? 0;
          final arlaTotal = resultado.arlaValorTotal;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                arlaTotal != null
                    ? 'Abastecimento interno confirmado! Combustível: R\$ ${total.toStringAsFixed(2)} · Arla32: R\$ ${arlaTotal.toStringAsFixed(2)}'
                    : 'Abastecimento interno confirmado! Valor total: R\$ ${total.toStringAsFixed(2)}',
              ),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _combustivel = null;
            _quantidadeCtrl.clear();
            _arlaQuantidadeCtrl.clear();
            _hodometroCtrl.clear();
          });
          break;
        case 'nao_vinculado':
          setState(() => _erro = 'Seu usuário não está vinculado a um cadastro de motorista.');
          break;
        case 'veiculo_nao_autorizado':
          setState(() => _erro = 'Esse veículo não está vinculado a você.');
          break;
        case 'empresa_nao_autorizada':
          setState(() => _erro = 'Essa empresa não faz parte do seu grupo econômico.');
          break;
        case 'posto_interno_nao_configurado':
          setState(() => _erro = 'Essa empresa ainda não tem um posto interno ativo configurado.');
          break;
        case 'combustivel_sem_preco_cadastrado':
          setState(() => _erro = 'Não há preço cadastrado para esse combustível nessa empresa. Avise seu gestor.');
          break;
        case 'arla_sem_preco_cadastrado':
          setState(() => _erro = 'Não há preço de Arla32 cadastrado nessa empresa. Avise seu gestor.');
          break;
        case 'quantidade_invalida':
          setState(() => _erro = 'Quantidade inválida.');
          break;
        default:
          setState(() => _erro = 'Não consegui registrar agora. Tente de novo em instantes.');
      }
    } catch (e) {
      setState(() => _erro = 'Não consegui registrar agora. Tente de novo em instantes.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final opcoesAsync = ref.watch(opcoesAbastecimentoInternoProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Abastecimento Interno'),
      ),
      drawer: const AppDrawer(),
      body: opcoesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Não consegui carregar os dados agora. Tente de novo em instantes.'),
          ),
        ),
        data: (opcoes) {
          if (opcoes.empresas.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Nenhuma empresa do seu grupo tem posto interno ativo configurado no momento.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final precos = _empresaId == null
              ? <String, num>{}
              : opcoes.precosPorCombustivel(_empresaId!);
          final combustiveisDisponiveis = precos.keys
              .where((c) => c != 'Arla32')
              .toList()
            ..sort();
          final precoSelecionado = _combustivel == null ? null : precos[_combustivel];
          final precoArla = precos['Arla32'];
          final quantidade = num.tryParse(_quantidadeCtrl.text.replaceAll(',', '.'));
          final valorPrevisto = (precoSelecionado != null && quantidade != null)
              ? precoSelecionado * quantidade
              : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Confirme aqui o abastecimento feito na garagem/tanque próprio da empresa, antes de sair pra rota. O preço é sempre o cadastrado pelo gestor — você não digita preço.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              if (opcoes.motoristaNome != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Motorista: ${opcoes.motoristaNome}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: _empresaId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Empresa (posto interno)',
                  border: OutlineInputBorder(),
                ),
                items: opcoes.empresas
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.empresaId,
                        child: Text(e.nome, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _empresaId = v;
                  _combustivel = null;
                }),
              ),
              const SizedBox(height: 12),
              if (opcoes.placas.isEmpty)
                const Text(
                  'Nenhum veículo vinculado a você no momento.',
                  style: TextStyle(color: Colors.black54),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _placa,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Veículo (placa)',
                    border: OutlineInputBorder(),
                  ),
                  items: opcoes.placas
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _placa = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _hodometroCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Hodômetro (km, opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_empresaId != null && combustiveisDisponiveis.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Essa empresa ainda não tem preço cadastrado pra nenhum combustível. Avise seu gestor.',
                    style: TextStyle(color: Colors.orange),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _combustivel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Combustível abastecido',
                    border: OutlineInputBorder(),
                  ),
                  items: combustiveisDisponiveis
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: _empresaId == null
                      ? null
                      : (v) => setState(() => _combustivel = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _quantidadeCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantidade abastecida (L)',
                  border: const OutlineInputBorder(),
                  helperText: precoSelecionado != null
                      ? 'Preço cadastrado: R\$ ${precoSelecionado.toStringAsFixed(3)}/L'
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (valorPrevisto != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Valor previsto: R\$ ${valorPrevisto.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (_ehDiesel && precoArla != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Arla32 (opcional, junto do Diesel)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _arlaQuantidadeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Quantidade de Arla32 (L, opcional)',
                    border: const OutlineInputBorder(),
                    helperText: 'Preço cadastrado: R\$ ${precoArla.toStringAsFixed(3)}/L',
                  ),
                ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _enviando ? null : () => _enviar(opcoes),
                child: _enviando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Confirmar abastecimento interno'),
              ),
            ],
          );
        },
      ),
    );
  }
}
