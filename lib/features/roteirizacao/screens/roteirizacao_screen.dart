import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_drawer.dart';
import '../providers/roteirizacao_provider.dart';

final _formatoKm = NumberFormat('#,##0.0', 'pt_BR');

// Roteirização self-service (Fase 17/07) — pedido do Daniel: "trazer as
// consultas de roteirização assim como tem no pwa cliente". Decisão
// (confirmada via pergunta ao usuário): versão simplificada e individual —
// o motorista planeja a PRÓPRIA rota (origem/destino, sem salvar), bem
// diferente do planejador completo do painel web (que é ligado à empresa,
// com múltiplas estratégias de comparação de preço — rotas_salvas não tem
// nenhum vínculo com motorista_id hoje). Mesmos serviços públicos e
// gratuitos (Nominatim + OSRM) chamados direto daqui.
class RoteirizacaoScreen extends StatefulWidget {
  const RoteirizacaoScreen({super.key});

  @override
  State<RoteirizacaoScreen> createState() => _RoteirizacaoScreenState();
}

class _RoteirizacaoScreenState extends State<RoteirizacaoScreen> {
  final _origemCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  SugestaoLocal? _origem;
  SugestaoLocal? _destino;

  bool _carregando = false;
  String? _erro;
  ResultadoRota? _resultado;
  List<PostoSugerido> _postos = [];

  // Placa/tanque/autonomia do veículo (Fase 17/07-2) — pedido do Daniel:
  // roteirização inteligente precisa saber a autonomia real do veículo pra
  // calcular ONDE o motorista realmente precisa abastecer, em vez de um
  // intervalo fixo de 80km igual pra qualquer caminhão.
  bool _carregandoVeiculos = true;
  List<VeiculoRoteirizacao> _veiculos = [];
  VeiculoRoteirizacao? _veiculoSelecionado;

  @override
  void initState() {
    super.initState();
    _carregarVeiculos();
  }

  Future<void> _carregarVeiculos() async {
    final veiculos = await buscarMeusVeiculos();
    if (!mounted) return;
    setState(() {
      _veiculos = veiculos;
      _veiculoSelecionado = veiculos.isNotEmpty ? veiculos.first : null;
      _carregandoVeiculos = false;
    });
  }

  @override
  void dispose() {
    _origemCtrl.dispose();
    _destinoCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarLocal({required bool origem}) async {
    final controller = origem ? _origemCtrl : _destinoCtrl;
    final termo = controller.text.trim();
    if (termo.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite pelo menos 3 letras pra buscar.')),
      );
      return;
    }
    setState(() => _carregando = true);
    final sugestoes = await geocodificar(termo);
    if (!mounted) return;
    setState(() => _carregando = false);

    if (sugestoes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum local encontrado. Tente outro termo (cidade + estado).')),
      );
      return;
    }

    final escolhido = await showModalBottomSheet<SugestaoLocal>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: sugestoes
              .map((s) => ListTile(
                    leading: const Icon(Icons.location_on_outlined, color: AppTheme.frota600),
                    title: Text(s.label),
                    onTap: () => Navigator.pop(ctx, s),
                  ))
              .toList(),
        ),
      ),
    );
    if (escolhido == null || !mounted) return;
    setState(() {
      controller.text = escolhido.label;
      if (origem) {
        _origem = escolhido;
      } else {
        _destino = escolhido;
      }
    });
  }

  Future<void> _calcular() async {
    if (_origem == null || _destino == null) {
      setState(() => _erro = 'Escolha a origem e o destino antes de calcular.');
      return;
    }
    if (_veiculoSelecionado == null) {
      setState(() => _erro = 'Selecione a placa do veículo antes de calcular.');
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
      _resultado = null;
      _postos = [];
    });

    final origemPonto = PontoRota(lat: _origem!.lat, lon: _origem!.lon);
    final destinoPonto = PontoRota(lat: _destino!.lat, lon: _destino!.lon);
    final resultado = await calcularRota(origemPonto, destinoPonto);

    if (!mounted) return;
    if (resultado == null) {
      setState(() {
        _carregando = false;
        _erro = 'Não consegui calcular a rota agora. Tente de novo em instantes.';
      });
      return;
    }

    // Intervalo de abastecimento real do veículo (tanque × autonomia), com
    // 20% de margem de segurança pra não deixar o motorista chegar no
    // limite da reserva. Limitado entre 60km e 700km pra cobrir cadastros
    // incompletos ou tanques enormes sem gerar poucos/muitos demais pontos.
    final autonomiaKm = _veiculoSelecionado!.autonomiaKm;
    final intervaloKm = autonomiaKm > 0 ? (autonomiaKm * 0.8).clamp(60.0, 700.0) : 80.0;

    final postos = await buscarPostosProximos(resultado.coordenadas, intervaloKm: intervaloKm);
    if (!mounted) return;
    setState(() {
      _carregando = false;
      _resultado = resultado;
      _postos = postos;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roteirização')),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Informe sua origem e destino pra ver a distância, o tempo estimado e os pontos de abastecimento recomendados pra sua placa.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          _SeletorVeiculo(
            carregando: _carregandoVeiculos,
            veiculos: _veiculos,
            selecionado: _veiculoSelecionado,
            onSelecionar: (v) => setState(() => _veiculoSelecionado = v),
          ),
          const SizedBox(height: 16),
          _CampoLocal(label: 'Origem', controller: _origemCtrl, onBuscar: () => _buscarLocal(origem: true)),
          const SizedBox(height: 12),
          _CampoLocal(label: 'Destino', controller: _destinoCtrl, onBuscar: () => _buscarLocal(origem: false)),
          const SizedBox(height: 16),
          if (_erro != null) ...[
            Text(_erro!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            onPressed: _carregando ? null : _calcular,
            icon: const Icon(Icons.alt_route),
            label: Text(_carregando ? 'Calculando...' : 'Calcular rota'),
          ),
          if (_resultado != null) ...[
            const SizedBox(height: 24),
            _CartaoResultado(resultado: _resultado!, postos: _postos),
          ],
          if (_postos.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Pontos de abastecimento recomendados', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            const Text(
              'Calculados pela autonomia real da sua placa (tanque × km/l do cadastro). '
              'Mostramos o posto mais próximo de cada ponto — ainda não comparamos preço entre postos.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            ..._postos.map((p) => _CartaoPosto(posto: p)),
          ],
        ],
      ),
    );
  }
}

// Seletor de placa (Fase 17/07-2) — pedido do Daniel: "para a placa, o
// usuario deve selecionar a sua placa na lista ou se tiver vinculo de placa
// e motorista, respeitar o vinculo, capacidade do tanque é do cadastro da
// placa". Com vínculo ativo mostra a placa travada (sem dropdown); sem
// vínculo, lista as placas ativas da empresa pra escolher.
class _SeletorVeiculo extends StatelessWidget {
  final bool carregando;
  final List<VeiculoRoteirizacao> veiculos;
  final VeiculoRoteirizacao? selecionado;
  final ValueChanged<VeiculoRoteirizacao?> onSelecionar;

  const _SeletorVeiculo({
    required this.carregando,
    required this.veiculos,
    required this.selecionado,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Carregando seu veículo...', style: TextStyle(color: Colors.black54)),
          ],
        ),
      );
    }

    if (veiculos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: const Text(
          'Não encontramos nenhum veículo cadastrado pra você calcular a autonomia. '
          'Fale com sua empresa pra vincular uma placa.',
          style: TextStyle(fontSize: 12.5, color: Colors.black87),
        ),
      );
    }

    final vinculoAtivo = veiculos.length == 1 && veiculos.first.vinculoAtivo;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, color: AppTheme.frota600, size: 20),
                const SizedBox(width: 8),
                Text(
                  vinculoAtivo ? 'Sua placa (vínculo ativo)' : 'Selecione sua placa',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (vinculoAtivo)
              _InfoVeiculo(veiculo: veiculos.first)
            else
              DropdownButtonFormField<VeiculoRoteirizacao>(
                initialValue: selecionado,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                items: veiculos
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text('${v.placa}${v.modelo != null ? ' — ${v.modelo}' : ''}'),
                        ))
                    .toList(),
                onChanged: onSelecionar,
              ),
            if (!vinculoAtivo && selecionado != null) ...[
              const SizedBox(height: 8),
              _InfoVeiculo(veiculo: selecionado!),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoVeiculo extends StatelessWidget {
  final VeiculoRoteirizacao veiculo;

  const _InfoVeiculo({required this.veiculo});

  @override
  Widget build(BuildContext context) {
    final autonomiaKm = veiculo.autonomiaKm;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        Text('Placa: ${veiculo.placa}', style: const TextStyle(fontSize: 12.5)),
        if (veiculo.tanque > 0) Text('Tanque: ${veiculo.tanque.toStringAsFixed(0)} L', style: const TextStyle(fontSize: 12.5)),
        if (veiculo.autonomia > 0) Text('Autonomia: ${veiculo.autonomia.toStringAsFixed(1)} km/l', style: const TextStyle(fontSize: 12.5)),
        if (autonomiaKm > 0) Text('Alcance: ~${autonomiaKm.toStringAsFixed(0)} km', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _CampoLocal extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onBuscar;

  const _CampoLocal({required this.label, required this.controller, required this.onBuscar});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onBuscar(),
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Digite a cidade e busque...',
        suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: onBuscar),
      ),
    );
  }
}

class _CartaoResultado extends StatelessWidget {
  final ResultadoRota resultado;
  final List<PostoSugerido> postos;

  const _CartaoResultado({required this.resultado, required this.postos});

  @override
  Widget build(BuildContext context) {
    final horas = resultado.duracaoMin ~/ 60;
    final minutos = (resultado.duracaoMin % 60).round();
    final tempoTexto = horas > 0 ? '${horas}h ${minutos}min' : '${minutos}min';

    final pontosRota = resultado.coordenadas.map((p) => LatLng(p.lat, p.lon)).toList();
    final origem = pontosRota.first;
    final destino = pontosRota.last;
    final limites = LatLngBounds.fromPoints(pontosRota);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Metrica(icone: Icons.straighten, valor: '${_formatoKm.format(resultado.distanciaKm)} km', label: 'Distância'),
                ),
                Expanded(
                  child: _Metrica(icone: Icons.schedule, valor: tempoTexto, label: 'Tempo estimado'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Mapa OSM de verdade (tiles públicos, sem chave de API) —
            // pedido do Daniel (17/07): "quero o mapa OSM assim como tenho
            // na visão do cliente na web", com origem/destino/postos
            // plotados igual ao planejador do painel.
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 320,
                child: FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(bounds: limites, padding: const EdgeInsets.all(32)),
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.fni.estradaquecuida',
                    ),
                    PolylineLayer(
                      polylines: [Polyline(points: pontosRota, color: AppTheme.frota500, strokeWidth: 4)],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: origem,
                          width: 36,
                          height: 36,
                          child: const Icon(Icons.trip_origin, color: AppTheme.statusAtivo, size: 28),
                        ),
                        Marker(
                          point: destino,
                          width: 36,
                          height: 36,
                          child: const Icon(Icons.location_on, color: AppTheme.statusInativo, size: 34),
                        ),
                        for (final posto in postos)
                          Marker(
                            point: LatLng(posto.lat, posto.lon),
                            width: 30,
                            height: 30,
                            child: const Icon(Icons.local_gas_station, color: AppTheme.frota700, size: 24),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 9, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metrica extends StatelessWidget {
  final IconData icone;
  final String valor;
  final String label;

  const _Metrica({required this.icone, required this.valor, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, color: AppTheme.frota600, size: 28),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(valor, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(label, style: const TextStyle(color: Colors.black54, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _CartaoPosto extends StatelessWidget {
  final PostoSugerido posto;

  const _CartaoPosto({required this.posto});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.local_gas_station, color: AppTheme.frota600),
        title: Text(posto.razaoSocial, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(
          [
            if (posto.bandeira != null) posto.bandeira!,
            if (posto.municipio != null) posto.municipio!,
          ].join(' • '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text('${_formatoKm.format(posto.distanciaKm)} km', style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ),
    );
  }
}
