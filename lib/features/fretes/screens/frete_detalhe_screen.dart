import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/fretes_provider.dart';

final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

class FreteDetalheScreen extends StatefulWidget {
  final String freteId;
  const FreteDetalheScreen({super.key, required this.freteId});

  @override
  State<FreteDetalheScreen> createState() => _FreteDetalheScreenState();
}

class _FreteDetalheScreenState extends State<FreteDetalheScreen> {
  bool _carregando = true;
  Frete? _frete;
  Negociacao? _negociacao;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final frete = await buscarFrete(widget.freteId);
    final negociacao = frete != null && frete.status == 'disponivel' ? await buscarMinhaNegociacao(widget.freteId) : null;
    if (!mounted) return;
    setState(() {
      _frete = frete;
      _negociacao = negociacao;
      _carregando = false;
    });
  }

  String _mensagemErro(Object e) => e is PostgrestException ? e.message : 'Não foi possível completar a ação agora.';

  Future<void> _executar(Future<void> Function() acao) async {
    setState(() => _processando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await acao();
      await _carregar();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_mensagemErro(e))));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do frete')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _frete == null
              ? const Center(child: Text('Frete não encontrado.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _CartaoInfo(frete: _frete!),
                    const SizedBox(height: 20),
                    if (_frete!.status == 'aguardando_confirmacao') _blocoAtribuicaoDireta(),
                    if (_frete!.status == 'disponivel') _blocoNegociacao(),
                    if (_frete!.status == 'aceito' || _frete!.status == 'em_andamento')
                      const _Aviso('Frete aceito — combine os detalhes finais com o cliente e boa viagem!', cor: AppTheme.frota700),
                    if (_frete!.status == 'concluido') const _Aviso('Frete concluído.', cor: Colors.black54),
                    if (_frete!.status == 'cancelado') const _Aviso('Esse frete foi cancelado pelo cliente.', cor: Colors.red),
                    if (_frete!.status == 'recusado') const _Aviso('Você recusou esse frete.', cor: Colors.black54),
                  ],
                ),
    );
  }

  Widget _blocoAtribuicaoDireta() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Esse frete foi atribuído direto a você pelo cliente, no valor combinado acima.',
          style: TextStyle(color: Colors.black54, fontSize: 13),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _processando ? null : () => _executar(() => responderFreteDireto(widget.freteId, true)),
          child: const Text('Aceitar frete'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _processando ? null : () => _executar(() => responderFreteDireto(widget.freteId, false)),
          child: const Text('Recusar'),
        ),
      ],
    );
  }

  Widget _blocoNegociacao() {
    final negociacao = _negociacao;
    if (negociacao == null) {
      return _FormularioProposta(
        processando: _processando,
        onEnviar: (valor) => _executar(() => abrirNegociacaoFrete(widget.freteId, valor)),
      );
    }

    if (negociacao.status != 'aberta') {
      final texto = switch (negociacao.status) {
        'recusada' => 'O cliente recusou sua proposta.',
        'retirada' => 'Você retirou sua proposta.',
        'perdida' => 'Esse frete foi pra outro motorista.',
        _ => negociacao.status,
      };
      return _Aviso(texto, cor: Colors.black54);
    }

    final ultima = negociacao.ultimaRodada;
    final aguardandoCliente = ultima?.autor == 'motorista';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Histórico da negociação', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        ...negociacao.rodadas.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${r.autor == 'motorista' ? 'Você' : 'Cliente'} propôs ${_formatoMoeda.format(r.valorProposto)}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (aguardandoCliente)
          const _Aviso('Aguardando resposta do cliente.', cor: Colors.black54)
        else ...[
          ElevatedButton(
            onPressed: _processando ? null : () => _executar(() => aceitarNegociacaoFrete(negociacao.id)),
            child: Text('Aceitar ${_formatoMoeda.format(ultima!.valorProposto)}'),
          ),
          const SizedBox(height: 8),
          _FormularioProposta(
            processando: _processando,
            label: 'Contrapropor',
            onEnviar: (valor) => _executar(() => proporRodadaNegociacao(negociacao.id, valor)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _processando ? null : () => _executar(() => recusarNegociacaoFrete(negociacao.id)),
            child: const Text('Recusar / retirar proposta'),
          ),
        ],
      ],
    );
  }
}

class _CartaoInfo extends StatelessWidget {
  final Frete frete;
  const _CartaoInfo({required this.frete});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(frete.titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 6),
            Text('${frete.origemLabel} → ${frete.destinoLabel}', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 10),
            Text(
              _formatoMoeda.format(frete.valorOferecido),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppTheme.frota700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (frete.kmEstimado != null) Text('${frete.kmEstimado!.toStringAsFixed(0)} km', style: const TextStyle(fontSize: 12.5)),
                if (frete.tipoCarga != null) Text('Carga: ${frete.tipoCarga}', style: const TextStyle(fontSize: 12.5)),
                if (frete.pesoCargaKg != null) Text('${frete.pesoCargaKg!.toStringAsFixed(0)} kg', style: const TextStyle(fontSize: 12.5)),
                if (frete.dataSaidaPrevista != null) Text('Saída: ${frete.dataSaidaPrevista}', style: const TextStyle(fontSize: 12.5)),
              ],
            ),
            if (frete.descricao != null) ...[
              const SizedBox(height: 10),
              Text(frete.descricao!, style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;
  final Color cor;
  const _Aviso(this.texto, {required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Text(texto, style: TextStyle(color: cor, fontSize: 13)),
    );
  }
}

class _FormularioProposta extends StatefulWidget {
  final bool processando;
  final String label;
  final Future<void> Function(double valor) onEnviar;

  const _FormularioProposta({required this.processando, this.label = 'Propor valor', required this.onEnviar});

  @override
  State<_FormularioProposta> createState() => _FormularioPropostaState();
}

class _FormularioPropostaState extends State<_FormularioProposta> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor (R\$)', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: widget.processando
              ? null
              : () {
                  final valor = double.tryParse(_controller.text.replaceAll(',', '.'));
                  if (valor == null || valor <= 0) return;
                  widget.onEnviar(valor);
                },
          child: Text(widget.label),
        ),
      ],
    );
  }
}
