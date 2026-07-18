import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
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
  String? _erro;
  Frete? _frete;
  Negociacao? _negociacao;
  List<PostoRecomendado> _postos = [];
  List<EventoFrete> _eventos = [];
  List<AvaliacaoFrete> _avaliacoes = [];
  bool _processando = false;
  // Fase Fretes-Dados-Completos — pedido do Daniel: motorista precisa
  // saber se o ponto de coleta está longe dele ANTES de decidir aceitar.
  Position? _minhaPosicao;

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
    await _atualizar();
  }

  // Fase negociação — pedido do Daniel: a tela só buscava os dados do
  // frete uma vez, ao abrir. Se o cliente contrapunha depois disso, o
  // motorista continuava vendo "aguardando resposta do cliente" e os
  // botões de aceitar/contrapropor/recusar sumiam, porque a tela nunca
  // recarregava sozinha. `_atualizar` é a mesma busca, mas sem o
  // spinner de tela cheia — usada no pull-to-refresh e no botão de
  // atualizar do AppBar, pra não piscar a tela a cada toque.
  Future<void> _atualizar() async {
    try {
      final frete = await buscarFrete(widget.freteId);
      final negociacao = frete != null && frete.status == 'disponivel' ? await buscarMinhaNegociacao(widget.freteId) : null;
      final postos = frete != null ? await buscarPostosRecomendados(widget.freteId) : <PostoRecomendado>[];
      final eventos = frete != null ? await buscarEventosFrete(widget.freteId) : <EventoFrete>[];
      final avaliacoes = frete != null && frete.status == 'concluido' ? await buscarAvaliacoesFrete(widget.freteId) : <AvaliacaoFrete>[];
      // Só pergunta a localização quando ainda faz sentido decidir (mercado
      // aberto ou atribuição direta aguardando confirmação) — depois disso
      // o motorista já aceitou, não precisa mais do prompt do navegador.
      final precisaDistancia = frete != null && (frete.status == 'disponivel' || frete.status == 'aguardando_confirmacao');
      final posicao = precisaDistancia && _minhaPosicao == null ? await obterLocalizacaoAtual() : _minhaPosicao;
      if (!mounted) return;
      setState(() {
        _frete = frete;
        _negociacao = negociacao;
        _postos = postos;
        _eventos = eventos;
        _avaliacoes = avaliacoes;
        _minhaPosicao = posicao;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is PostgrestException ? e.message : 'Não consegui carregar o frete agora.';
        _carregando = false;
      });
    }
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
      appBar: AppBar(
        title: const Text('Detalhes do frete'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _carregando ? null : _atualizar,
          ),
        ],
      ),
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
              : _frete == null
              ? const Center(child: Text('Frete não encontrado.'))
              : RefreshIndicator(
                  onRefresh: _atualizar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _CartaoInfo(frete: _frete!, minhaPosicao: _minhaPosicao),
                      if (_frete!.coleta.preenchido || _frete!.entrega.preenchido) ...[
                        const SizedBox(height: 12),
                        _BlocoEndereco(titulo: '📍 Coleta', endereco: _frete!.coleta),
                        const SizedBox(height: 8),
                        _BlocoEndereco(titulo: '📍 Entrega', endereco: _frete!.entrega),
                      ],
                      const SizedBox(height: 20),
                      if (_frete!.status == 'aguardando_confirmacao') _blocoAtribuicaoDireta(),
                      if (_frete!.status == 'disponivel') _blocoNegociacao(),
                      if (_frete!.status == 'aceito' || _frete!.status == 'em_andamento') ..._blocoExecucao(),
                      if (_frete!.status == 'concluido') ..._blocoConcluido(),
                      if (_frete!.status == 'cancelado') const _Aviso('Esse frete foi cancelado pelo cliente.', cor: Colors.red),
                      if (_frete!.status == 'recusado') const _Aviso('Você recusou esse frete.', cor: Colors.black54),
                    ],
                  ),
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

  bool _jaTemEvento(String tipo) => _eventos.any((e) => e.tipoEvento == tipo);

  // Fase foto-evidência-checkpoints — pedido do Daniel: motorista anexa
  // foto nos checkpoints (posto pra abastecimento, chegada no destino, no
  // cliente pra entrega, ocorrências), pra o cliente ver na web. Obrigatória
  // em abasteceu/chegou_destino/concluido/ocorrencia (a RPC também valida
  // isso do lado do banco — ver migração foto_evidencia_checkpoints_frete),
  // opcional em saiu_origem/chegou_posto/parada.
  Future<Uint8List?> _capturarFoto() async {
    try {
      final foto = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
      if (foto == null) return null; // usuário cancelou — não é erro, não mostra nada
      return await foto.readAsBytes();
    } catch (e) {
      // Fase foto-evidência-checkpoints-3 — achado do Daniel: "não está
      // abrindo o fluxo da câmera" e o app não dizia por quê (erro era
      // engolido em silêncio). Mostra o motivo real agora — no navegador,
      // isso costuma ser permissão de câmera negada/bloqueada ou o
      // dispositivo não tendo câmera disponível.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não consegui abrir a câmera: $e')),
        );
      }
      return null;
    }
  }

  // Fase foto-evidência-checkpoints-2 — pedido do Daniel: "o aplicativo
  // precisa abrir automaticamente a câmera, o usuário tira a foto, confirma,
  // e a foto é enviada como evidência". `ImageSource.camera` já manda o
  // navegador abrir a câmera direto (sem passar pela galeria); o que faltava
  // era o passo de CONFIRMAR — antes a foto ia direto pro upload assim que
  // tirada, sem chance de ver se saiu ruim e tirar de novo antes de virar
  // evidência pro cliente decidir o pagamento do frete.
  Future<Uint8List?> _tirarFoto() async {
    while (true) {
      final bytes = await _capturarFoto();
      if (bytes == null || !mounted) return null;

      final confirmou = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Usar esta foto?'),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Tirar de novo')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
          ],
        ),
      );
      if (confirmou == true) return bytes;
      if (confirmou == null) return null; // fechou o diálogo sem escolher — cancela
      // false: volta pro topo do loop e abre a câmera de novo
      if (!mounted) return null;
    }
  }

  Future<bool> _perguntarQuerFoto() async {
    final resposta = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anexar uma foto?'),
        content: const Text('Opcional, mas ajuda o cliente a acompanhar a viagem.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Pular')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tirar foto')),
        ],
      ),
    );
    return resposta ?? false;
  }

  Future<void> _registrarEvento(
    String tipoEvento, {
    String? postoId,
    String? observacao,
    required bool fotoObrigatoria,
  }) async {
    Uint8List? fotoBytes;
    if (fotoObrigatoria) {
      fotoBytes = await _tirarFoto();
      if (fotoBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Esse checkpoint exige uma foto.')));
        }
        return;
      }
    } else if (await _perguntarQuerFoto()) {
      fotoBytes = await _tirarFoto();
    }
    if (!mounted) return;

    await _executar(() async {
      String? fotoPath;
      if (fotoBytes != null) {
        fotoPath = await enviarFotoEvidenciaFrete(freteId: widget.freteId, tipoEvento: tipoEvento, bytes: fotoBytes);
      }
      await registrarEventoFrete(
        widget.freteId,
        tipoEvento,
        postoRecomendadoId: postoId,
        observacao: observacao,
        fotoPath: fotoPath,
      );
    });
  }

  Future<void> _registrarComPosto(String tipoEvento, {required bool fotoObrigatoria}) async {
    String? postoId;
    if (_postos.isNotEmpty) {
      postoId = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Em qual posto?', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ..._postos.map(
                (p) => ListTile(
                  leading: const Icon(Icons.local_gas_station, color: AppTheme.frota600),
                  title: Text(p.nomePosto),
                  onTap: () => Navigator.pop(ctx, p.id),
                ),
              ),
              ListTile(title: const Text('Outro posto (não listado)'), onTap: () => Navigator.pop(ctx, null)),
            ],
          ),
        ),
      );
    }
    if (!mounted) return;
    await _registrarEvento(tipoEvento, postoId: postoId, fotoObrigatoria: fotoObrigatoria);
  }

  Future<void> _registrarOcorrencia() async {
    final observacao = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Descreva a ocorrência'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'O que aconteceu?'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Continuar')),
          ],
        );
      },
    );
    if (observacao == null || observacao.isEmpty) return;
    if (!mounted) return;
    await _registrarEvento('ocorrencia', observacao: observacao, fotoObrigatoria: true);
  }

  Future<void> _verFoto(String path) async {
    try {
      final url = await SupabaseService.client.storage.from('fretes-evidencias').createSignedUrl(path, 3600);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url))),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não consegui abrir a foto.')));
      }
    }
  }

  List<Widget> _blocoExecucao() {
    return [
      if (_postos.isNotEmpty) ...[
        const Text('Postos recomendados', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        ..._postos.map(
          (p) => Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.local_gas_station_outlined, color: AppTheme.frota600),
              title: Text(p.nomePosto, style: const TextStyle(fontSize: 13)),
              subtitle: p.itemCatalogoId != null
                  ? const Text('🎟️ tem benefício disponível — confira no Catálogo', style: TextStyle(fontSize: 11.5))
                  : (p.observacao != null ? Text(p.observacao!, style: const TextStyle(fontSize: 11.5)) : null),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      const Text('Acompanhamento da viagem', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 8),
      const Text(
        '📷 Foto obrigatória em: abasteceu, chegou no destino, concluir e ocorrência.',
        style: TextStyle(fontSize: 11, color: Colors.black54),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!_jaTemEvento('saiu_origem'))
            ElevatedButton.icon(
              onPressed: _processando ? null : () => _registrarEvento('saiu_origem', fotoObrigatoria: false),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Saí da origem'),
            ),
          OutlinedButton.icon(
            onPressed: _processando ? null : () => _registrarComPosto('chegou_posto', fotoObrigatoria: false),
            icon: const Icon(Icons.local_gas_station_outlined, size: 18),
            label: const Text('Cheguei num posto'),
          ),
          OutlinedButton.icon(
            onPressed: _processando ? null : () => _registrarComPosto('abasteceu', fotoObrigatoria: true),
            icon: const Icon(Icons.local_gas_station, size: 18),
            label: const Text('Abasteci 📷'),
          ),
          OutlinedButton.icon(
            onPressed: _processando ? null : () => _registrarEvento('parada', fotoObrigatoria: false),
            icon: const Icon(Icons.pause_circle_outline, size: 18),
            label: const Text('Parada'),
          ),
          OutlinedButton.icon(
            onPressed: _processando ? null : () => _registrarEvento('chegou_destino', fotoObrigatoria: true),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Cheguei no destino 📷'),
          ),
          OutlinedButton.icon(
            onPressed: _processando ? null : _registrarOcorrencia,
            icon: const Icon(Icons.report_problem_outlined, size: 18),
            label: const Text('Ocorrência 📷'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ElevatedButton.icon(
        onPressed: _processando ? null : () => _confirmarConcluir(),
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusAtivo, foregroundColor: Colors.white),
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Concluir frete 📷'),
      ),
      const SizedBox(height: 20),
      if (_eventos.isNotEmpty) _timeline(),
    ];
  }

  Future<void> _confirmarConcluir() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Concluir frete?'),
        content: const Text('Confirma que chegou no destino e finalizou a entrega?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Concluir')),
        ],
      ),
    );
    if (confirmar == true) {
      await _registrarEvento('concluido', fotoObrigatoria: true);
    }
  }

  Widget _timeline() {
    const labelEvento = {
      'saiu_origem': 'Saiu da origem',
      'chegou_posto': 'Chegou no posto',
      'abasteceu': 'Abasteceu',
      'parada': 'Parada',
      'chegou_destino': 'Chegou no destino',
      'ocorrencia': 'Ocorrência',
      'concluido': 'Concluiu o frete',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Linha do tempo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        ..._eventos.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(labelEvento[e.tipoEvento] ?? e.tipoEvento, style: const TextStyle(fontSize: 12.5))),
                if (e.fotoPath != null)
                  IconButton(
                    onPressed: () => _verFoto(e.fotoPath!),
                    icon: const Icon(Icons.photo_camera, size: 16, color: AppTheme.frota600),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                const SizedBox(width: 8),
                Text(
                  '${e.criadoEm.hour.toString().padLeft(2, '0')}:${e.criadoEm.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _blocoConcluido() {
    final avaliacaoMinha = _avaliacoes.where((a) => a.avaliador == 'motorista').isEmpty
        ? null
        : _avaliacoes.firstWhere((a) => a.avaliador == 'motorista');
    final avaliacaoCliente = _avaliacoes.where((a) => a.avaliador == 'cliente').isEmpty
        ? null
        : _avaliacoes.firstWhere((a) => a.avaliador == 'cliente');

    return [
      if (_eventos.isNotEmpty) ...[_timeline(), const SizedBox(height: 20)],
      const Text('Avaliação', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 8),
      if (avaliacaoCliente != null)
        Text('O cliente te avaliou: ${'★' * avaliacaoCliente.estrelas}', style: const TextStyle(fontSize: 13)),
      const SizedBox(height: 8),
      if (avaliacaoMinha == null)
        _FormularioAvaliacao(
          processando: _processando,
          onEnviar: (estrelas, comentario) =>
              _executar(() => avaliarFrete(widget.freteId, estrelas, comentario: comentario)),
        )
      else
        Text('Você avaliou o cliente: ${'★' * avaliacaoMinha.estrelas}', style: const TextStyle(fontSize: 13)),
    ];
  }
}

class _CartaoInfo extends StatelessWidget {
  final Frete frete;
  final Position? minhaPosicao;
  const _CartaoInfo({required this.frete, this.minhaPosicao});

  @override
  Widget build(BuildContext context) {
    final posicao = minhaPosicao;
    final distanciaAteColeta =
        posicao == null ? null : distanciaKm(posicao.latitude, posicao.longitude, frete.origemLat, frete.origemLon);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(frete.titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 6),
            Text('${frete.origemLabel} → ${frete.destinoLabel}', style: const TextStyle(fontSize: 14)),
            if (distanciaAteColeta != null) ...[
              const SizedBox(height: 6),
              Text(
                '📍 ${distanciaAteColeta.toStringAsFixed(0)} km até o ponto de coleta',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.frota700),
              ),
            ],
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
            if (frete.cargaComprimentoM != null || frete.cargaLarguraM != null || frete.cargaAlturaM != null) ...[
              const SizedBox(height: 6),
              Text(
                '📐 ${frete.cargaComprimentoM ?? '—'}m × ${frete.cargaLarguraM ?? '—'}m × ${frete.cargaAlturaM ?? '—'}m (C×L×A)',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
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

class _BlocoEndereco extends StatelessWidget {
  final String titulo;
  final EnderecoFrete endereco;
  const _BlocoEndereco({required this.titulo, required this.endereco});

  @override
  Widget build(BuildContext context) {
    if (!endereco.preenchido) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(endereco.linhaEndereco, style: const TextStyle(fontSize: 13)),
            if (endereco.cep != null) Text('CEP ${endereco.cep}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
            if (endereco.referencia != null)
              Text('Referência: ${endereco.referencia}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
            if (endereco.data != null || endereco.hora != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '🗓️ ${endereco.data ?? 'Data não informada'}${endereco.hora != null ? ' às ${endereco.hora!.substring(0, 5)}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
              ),
            if (endereco.contatoNome != null || endereco.contatoTelefone != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '👤 ${endereco.contatoNome ?? 'Contato'}${endereco.contatoTelefone != null ? ' — ${endereco.contatoTelefone}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
              ),
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

class _FormularioAvaliacao extends StatefulWidget {
  final bool processando;
  final void Function(int estrelas, String? comentario) onEnviar;

  const _FormularioAvaliacao({required this.processando, required this.onEnviar});

  @override
  State<_FormularioAvaliacao> createState() => _FormularioAvaliacaoState();
}

class _FormularioAvaliacaoState extends State<_FormularioAvaliacao> {
  int _estrelas = 5;
  final _comentarioCtrl = TextEditingController();

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: List.generate(5, (i) {
            final n = i + 1;
            return IconButton(
              onPressed: () => setState(() => _estrelas = n),
              icon: Icon(
                n <= _estrelas ? Icons.star : Icons.star_border,
                color: Colors.amber,
              ),
            );
          }),
        ),
        TextField(
          controller: _comentarioCtrl,
          decoration: const InputDecoration(labelText: 'Comentário (opcional)', isDense: true),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: widget.processando
              ? null
              : () => widget.onEnviar(_estrelas, _comentarioCtrl.text.trim().isEmpty ? null : _comentarioCtrl.text.trim()),
          child: const Text('Avaliar cliente'),
        ),
      ],
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
          style: ElevatedButton.styleFrom(minimumSize: const Size(88, 48)),
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
