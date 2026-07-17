import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_drawer.dart';
import '../providers/fretes_provider.dart';

final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

const _labelStatus = {
  'disponivel': 'Disponível',
  'aguardando_confirmacao': 'Aguardando sua confirmação',
  'aceito': 'Aceito',
  'em_andamento': 'Em andamento',
  'concluido': 'Concluído',
  'cancelado': 'Cancelado',
  'recusado': 'Recusado',
};

// Fretes (Fase Fretes) — "Uber de frete": mercado aberto com negociação de
// valor, ou frete atribuído direto (próprio/parceiro) só pra confirmar.
class FretesScreen extends StatefulWidget {
  const FretesScreen({super.key});

  @override
  State<FretesScreen> createState() => _FretesScreenState();
}

class _FretesScreenState extends State<FretesScreen> {
  bool _carregando = true;
  String? _erro;
  List<Frete> _mercado = [];
  List<(Negociacao, Frete)> _negociando = [];
  List<Frete> _atribuidos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final mercado = await buscarFretesMercado();
      final negociando = await buscarMinhasNegociacoes();
      final atribuidos = await buscarMeusFretesAtribuidos();
      if (!mounted) return;
      final idsNegociando = negociando.map((n) => n.$2.id).toSet();
      setState(() {
        _mercado = mercado.where((f) => !idsNegociando.contains(f.id)).toList();
        _negociando = negociando;
        _atribuidos = atribuidos;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is PostgrestException ? e.message : 'Não consegui carregar os fretes agora.';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fretes')),
      drawer: const AppDrawer(),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_atribuidos.isNotEmpty) ...[
                    const _TituloSecao('Meus fretes'),
                    ..._atribuidos.map((f) => _CardFrete(frete: f, onTap: () => _abrir(f.id))),
                    const SizedBox(height: 20),
                  ],
                  if (_negociando.isNotEmpty) ...[
                    const _TituloSecao('Em negociação'),
                    ..._negociando.map(
                      (par) => _CardFrete(
                        frete: par.$2,
                        subtitulo: 'Rodada ${par.$1.rodadaAtual} · ${_labelNegociacao(par.$1.status)}',
                        onTap: () => _abrir(par.$2.id),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  const _TituloSecao('Disponíveis pra negociar'),
                  if (_mercado.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Nenhum frete disponível no momento.', style: TextStyle(color: Colors.black54)),
                    ),
                  ..._mercado.map((f) => _CardFrete(frete: f, onTap: () => _abrir(f.id))),
                ],
              ),
            ),
    );
  }

  String _labelNegociacao(String status) {
    switch (status) {
      case 'aberta':
        return 'aguardando resposta';
      case 'aceita':
        return 'aceita';
      case 'recusada':
        return 'recusada';
      case 'retirada':
        return 'retirada';
      case 'perdida':
        return 'perdida pra outro motorista';
      default:
        return status;
    }
  }

  void _abrir(String freteId) async {
    await context.push('/fretes/$freteId');
    if (mounted) _carregar();
  }
}

class _TituloSecao extends StatelessWidget {
  final String texto;
  const _TituloSecao(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }
}

class _CardFrete extends StatelessWidget {
  final Frete frete;
  final String? subtitulo;
  final VoidCallback onTap;

  const _CardFrete({required this.frete, this.subtitulo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(frete.titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  Text(
                    _formatoMoeda.format(frete.valorOferecido),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.frota700, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${frete.origemLabel} → ${frete.destinoLabel}', style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
              const SizedBox(height: 6),
              Text(
                subtitulo ?? _labelStatus[frete.status] ?? frete.status,
                style: const TextStyle(fontSize: 11.5, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
