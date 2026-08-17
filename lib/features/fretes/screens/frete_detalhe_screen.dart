import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../roteirizacao/providers/roteirizacao_provider.dart';
import '../../roteirizacao/utils/roteirizacao_constantes.dart';
import '../providers/fretes_provider.dart';
import '../services/ocr_service.dart';

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
  // Fase ocr-documentos (04/08/2026) — leitura best-effort do canhoto/NF-e.
  final _ocrService = OcrService();

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
                      if (_frete!.status == 'disponivel' || _frete!.status == 'aguardando_confirmacao') ...[
                        const SizedBox(height: 12),
                        _CalculadoraLucro(frete: _frete!),
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
      // Fase Fretes-Aceitar-Direto-Mercado (19/07) — pedido do Daniel:
      // antes só dava pra propor outro valor; agora dá pra aceitar o valor
      // já anunciado (ou recusar/ignorar) direto, sem precisar negociar.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            onPressed: _processando ? null : () => _executar(() => aceitarFreteDisponivel(widget.freteId)),
            child: Text('Aceitar ${_formatoMoeda.format(_frete!.valorOferecido)}'),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('ou', style: TextStyle(color: Colors.black45, fontSize: 12))),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 8),
          _FormularioProposta(
            processando: _processando,
            onEnviar: (valor) => _executar(() => abrirNegociacaoFrete(widget.freteId, valor)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _processando ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Não me interessa'),
          ),
        ],
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
    String? codigoOcorrencia,
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
        codigoOcorrencia: codigoOcorrencia,
      );
    });
  }

  // Fase Botao-Panico (02/08/2026) — pede confirmação (evita clique
  // acidental), captura localização fresca (não reaproveita _minhaPosicao,
  // que só é preenchida antes de aceitar o frete e pode estar bem
  // desatualizada), registra o evento 'panico' e dispara o e-mail pra
  // operação. Não usa _executar porque precisa de uma mensagem de sucesso
  // diferente da padrão (silenciosa) — aqui a confirmação explícita
  // importa, é uma emergência.
  Future<void> _registrarPanico() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🚨 Alerta de emergência'),
        content: const Text(
          'Isso vai avisar a operação imediatamente, com sua localização atual. '
          'Use só em caso real de emergência.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar emergência'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _processando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final posicao = await obterLocalizacaoAtual();
      await registrarEventoFrete(widget.freteId, 'panico', lat: posicao?.latitude, lon: posicao?.longitude);
      await dispararAlertaPanicoFrete(widget.freteId);
      await _carregar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('🚨 Alerta enviado. A operação foi avisada.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_mensagemErro(e))));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
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

  // Fase P0.4 — pedido do plano: ocorrência precisa de um código
  // estruturado (atraso/avaria/recusa/reentrega/devolução), não só texto
  // livre — a RPC registrar_evento_frete já exige isso quando
  // tipo_evento='ocorrencia'.
  static const _labelCodigoOcorrencia = {
    'atraso': 'Atraso',
    'avaria': 'Avaria',
    'recusa': 'Recusa',
    'reentrega': 'Reentrega',
    'devolucao': 'Devolução',
  };

  Future<void> _registrarOcorrencia() async {
    final controller = TextEditingController();
    String? codigoSelecionado;

    final resultado = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Registrar ocorrência'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: codigoSelecionado,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tipo de ocorrência', isDense: true),
                  items: _labelCodigoOcorrencia.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => codigoSelecionado = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'Descreva o que aconteceu'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              TextButton(
                onPressed: codigoSelecionado == null
                    ? null
                    : () => Navigator.pop(ctx, (codigoSelecionado!, controller.text.trim())),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );
      },
    );
    if (resultado == null) return;
    if (!mounted) return;
    final (codigo, observacao) = resultado;
    await _registrarEvento(
      'ocorrencia',
      observacao: observacao.isEmpty ? null : observacao,
      codigoOcorrencia: codigo,
      fotoObrigatoria: true,
    );
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
      // Fase Botao-Panico (02/08/2026, Grupo 1 item 2 do benchmark FNI vs
      // KMM) — botão de emergência, separado dos checkpoints de rotina de
      // propósito (vermelho, largura total, com confirmação) pra não ter
      // risco de clique acidental nem se misturar com "Cheguei na origem"
      // etc. Sempre visível (não some depois de usado — pode acontecer mais
      // de uma emergência na mesma viagem).
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _processando ? null : _registrarPanico,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
          icon: const Icon(Icons.emergency_outlined),
          label: const Text('Alerta de emergência'),
        ),
      ),
      const SizedBox(height: 16),
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
          // Fase KPIs-Operacionais (02/08/2026) — checkpoint opcional extra,
          // alimenta o KPI de Tempo de Carga/Descarga na origem (Indicadores
          // da Frota, web). Sem gate sobre "Saí da origem" de propósito: já
          // existem fretes em andamento sem esse evento, e não seria certo
          // travar o botão de saída deles.
          if (!_jaTemEvento('chegou_origem'))
            ElevatedButton.icon(
              onPressed: _processando ? null : () => _registrarEvento('chegou_origem', fotoObrigatoria: false),
              icon: const Icon(Icons.flag_circle_outlined, size: 18),
              label: const Text('Cheguei na origem'),
            ),
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
        onPressed: _processando ? null : _confirmarEntrega,
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusAtivo, foregroundColor: Colors.white),
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Confirmar entrega ✍️'),
      ),
      const SizedBox(height: 20),
      if (_eventos.isNotEmpty) _timeline(),
      const SizedBox(height: 20),
      _ChatFrete(freteId: widget.freteId, motoristaId: _frete!.motoristaId!),
    ];
  }

  // Fase P0.4 (canhoto digital / POD) — pedido do plano: a conclusão do
  // frete passa a exigir nome do recebedor, foto do canhoto e assinatura na
  // tela (não só uma foto genérica como antes). A RPC confirmar_entrega_frete
  // grava tudo isso E o mesmo evento 'concluido' de sempre, então a
  // timeline/status continuam funcionando exatamente como já funcionavam.
  Future<Uint8List?> _capturarAssinatura() async {
    final controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    final bytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Assinatura do recebedor'),
        content: SizedBox(
          width: double.maxFinite,
          height: 220,
          child: Signature(controller: controller, backgroundColor: Colors.white),
        ),
        actions: [
          TextButton(onPressed: controller.clear, child: const Text('Limpar')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (controller.isEmpty) return;
              final png = await controller.toPngBytes();
              if (ctx.mounted) Navigator.pop(ctx, png);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return bytes;
  }

  Future<void> _confirmarEntrega() async {
    final fotoCanhoto = await _tirarFoto();
    if (fotoCanhoto == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A foto do canhoto é obrigatória.')));
      }
      return;
    }
    if (!mounted) return;

    // Fase ocr-documentos (04/08/2026, benchmark FNI vs KMM, Grupo 2) —
    // tenta ler o CPF do recebedor impresso no canhoto pra pré-preencher o
    // campo de documento no dialog abaixo. Best-effort: nunca bloqueia o
    // fluxo (nome escrito à mão não é confiável pra OCR nenhum, nem os
    // pagos — por isso só tentamos o documento, que costuma vir impresso).
    String? documentoSugerido;
    try {
      final leitura = await _ocrService.lerDocumento(fotoCanhoto);
      documentoSugerido = leitura.documentoRecebedor;
    } catch (_) {
      // best-effort — segue sem sugestão
    }
    if (!mounted) return;

    final dadosRecebedor = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) {
        final nomeCtrl = TextEditingController();
        final docCtrl = TextEditingController(text: documentoSugerido ?? '');
        return AlertDialog(
          title: const Text('Confirmar entrega'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome de quem recebeu')),
              const SizedBox(height: 8),
              TextField(
                controller: docCtrl,
                decoration: InputDecoration(
                  labelText: 'Documento (opcional)',
                  helperText: documentoSugerido != null ? 'Lido da foto — confira antes de continuar.' : null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(
              onPressed: () {
                if (nomeCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, (nomeCtrl.text.trim(), docCtrl.text.trim()));
              },
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    if (dadosRecebedor == null || !mounted) return;
    final (nomeRecebedor, documentoRecebedor) = dadosRecebedor;

    final assinatura = await _capturarAssinatura();
    if (assinatura == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A assinatura do recebedor é obrigatória.')));
      }
      return;
    }
    if (!mounted) return;

    await _executar(() async {
      final fotoPath = await enviarFotoEvidenciaFrete(freteId: widget.freteId, tipoEvento: 'canhoto', bytes: fotoCanhoto);
      final assinaturaPath = await enviarAssinaturaEntregaFrete(freteId: widget.freteId, bytes: assinatura);
      await confirmarEntregaFrete(
        widget.freteId,
        nomeRecebedor: nomeRecebedor,
        documentoRecebedor: documentoRecebedor.isEmpty ? null : documentoRecebedor,
        fotoCanhotoPath: fotoPath,
        assinaturaPath: assinaturaPath,
        lat: _minhaPosicao?.latitude,
        lon: _minhaPosicao?.longitude,
      );
    });
  }

  Widget _timeline() {
    const labelEvento = {
      'chegou_origem': 'Chegou na origem',
      'saiu_origem': 'Saiu da origem',
      'chegou_posto': 'Chegou no posto',
      'abasteceu': 'Abasteceu',
      'parada': 'Parada',
      'chegou_destino': 'Chegou no destino',
      'ocorrencia': 'Ocorrência',
      'concluido': 'Concluiu o frete',
      'panico': '🚨 Alerta de emergência',
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
                Expanded(
                  child: Text(
                    e.codigoOcorrencia != null
                        ? '${labelEvento[e.tipoEvento] ?? e.tipoEvento} — ${_labelCodigoOcorrencia[e.codigoOcorrencia] ?? e.codigoOcorrencia}'
                        : labelEvento[e.tipoEvento] ?? e.tipoEvento,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
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
      if (_frete!.motoristaId != null) ...[
        _ChatFrete(freteId: widget.freteId, motoristaId: _frete!.motoristaId!),
        const SizedBox(height: 20),
      ],
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
            if (frete.veiculosAceitos.isNotEmpty || frete.carroceriasAceitas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...frete.veiculosAceitos.map((v) => _tagDetalhe(v, AppTheme.frota700)),
                  ...frete.carroceriasAceitas.map((c) => _tagDetalhe(c, Colors.black54)),
                ],
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

// Fase Fretes-Dados-Completos — pedido do Daniel (inspirado em telas de
// outras plataformas de frete): "antes de pegar a estrada, calcule seus
// custos e veja o quanto você vai lucrar". Usa o mesmo tanque/autonomia já
// cadastrados do veículo (Roteirização) e o mesmo preço médio ANP por
// estado — nada digitado que já existe em algum cadastro.
class _CalculadoraLucro extends StatefulWidget {
  final Frete frete;
  const _CalculadoraLucro({required this.frete});

  @override
  State<_CalculadoraLucro> createState() => _CalculadoraLucroState();
}

class _CalculadoraLucroState extends State<_CalculadoraLucro> {
  List<VeiculoRoteirizacao> _veiculos = [];
  bool _carregandoVeiculos = true;
  VeiculoRoteirizacao? _veiculoSelecionado;
  String _combustivel = produtosPosto.first;
  late final TextEditingController _kmCtrl;

  bool _calculando = false;
  double? _precoMedio;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final kmInicial = widget.frete.kmEstimado ??
        distanciaKm(
          widget.frete.origemLat,
          widget.frete.origemLon,
          widget.frete.destinoLat,
          widget.frete.destinoLon,
        );
    _kmCtrl = TextEditingController(text: kmInicial.toStringAsFixed(0));
    _carregarVeiculos();
  }

  @override
  void dispose() {
    _kmCtrl.dispose();
    super.dispose();
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

  String? _estadoDoLabel(String label) {
    final partes = label.split(' – ');
    return partes.length > 1 ? partes.last.trim() : null;
  }

  Future<void> _calcular() async {
    final veiculo = _veiculoSelecionado;
    if (veiculo == null || veiculo.autonomia <= 0) {
      setState(() => _erro = 'Selecione um veículo com autonomia cadastrada.');
      return;
    }
    final km = double.tryParse(_kmCtrl.text.replaceAll(',', '.'));
    if (km == null || km <= 0) {
      setState(() => _erro = 'Informe uma distância válida.');
      return;
    }
    setState(() {
      _calculando = true;
      _erro = null;
    });
    final categoria = produtoParaCategoriaAnp[_combustivel] ?? _combustivel;
    final estado = _estadoDoLabel(widget.frete.origemLabel);
    final preco = await buscarPrecoMedioCombustivelPorEstado(categoria, estado);
    if (!mounted) return;
    setState(() {
      _precoMedio = preco;
      _calculando = false;
      if (preco == null) _erro = 'Não achei preço de referência pra esse combustível agora.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final km = double.tryParse(_kmCtrl.text.replaceAll(',', '.'));
    final veiculo = _veiculoSelecionado;
    final preco = _precoMedio;
    double? custoEstimado;
    double? lucroEstimado;
    double? margemPct;
    if (km != null && veiculo != null && veiculo.autonomia > 0 && preco != null) {
      custoEstimado = (km / veiculo.autonomia) * preco;
      lucroEstimado = widget.frete.valorOferecido - custoEstimado;
      margemPct = widget.frete.valorOferecido > 0 ? (lucroEstimado / widget.frete.valorOferecido) * 100 : null;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🧮 Calculadora de lucro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            const Text(
              'Antes de decidir, veja quanto esse frete deve custar de combustível e o quanto sobra pra você.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            if (_carregandoVeiculos)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_veiculos.isEmpty)
              const Text(
                'Cadastre um veículo com tanque e autonomia (mesmo cadastro da Roteirização) pra usar a calculadora.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              )
            else ...[
              DropdownButtonFormField<VeiculoRoteirizacao>(
                initialValue: _veiculoSelecionado,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Veículo', isDense: true, border: OutlineInputBorder()),
                items: _veiculos
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            '${v.placa}${v.modelo != null ? ' — ${v.modelo}' : ''}',
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _veiculoSelecionado = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _combustivel,
                      decoration: const InputDecoration(labelText: 'Combustível', isDense: true, border: OutlineInputBorder()),
                      items: produtosPosto.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setState(() => _combustivel = v ?? _combustivel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _kmCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Km', isDense: true, border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _calculando ? null : _calcular,
                child: Text(_calculando ? 'Calculando...' : 'Calcular'),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 6),
                Text(_erro!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              if (custoEstimado != null && lucroEstimado != null) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Custo estimado de combustível', style: TextStyle(fontSize: 12.5)),
                    Text(_formatoMoeda.format(custoEstimado), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Lucro estimado', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text(
                      _formatoMoeda.format(lucroEstimado),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: lucroEstimado >= 0 ? AppTheme.statusAtivo : Colors.red,
                      ),
                    ),
                  ],
                ),
                if (margemPct != null) ...[
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('${margemPct.toStringAsFixed(0)}% de margem sobre o valor do frete', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// Fase Grupo-1-item-3 (02/08/2026, benchmark FNI vs KMM) — chat com a
// operação, vinculado ao frete. Usa StreamBuilder sobre streamMensagensFrete
// (Realtime do supabase_flutter) — chega mensagem nova da empresa sem
// precisar de pull-to-refresh.
class _ChatFrete extends StatefulWidget {
  final String freteId;
  final String motoristaId;
  const _ChatFrete({required this.freteId, required this.motoristaId});

  @override
  State<_ChatFrete> createState() => _ChatFreteState();
}

class _ChatFreteState extends State<_ChatFrete> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _enviando = false;
  late final Stream<List<MensagemFrete>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = streamMensagensFrete(widget.freteId);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      await enviarMensagemFrete(widget.freteId, widget.motoristaId, texto);
      _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is PostgrestException ? e.message : 'Não consegui enviar. Tente de novo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💬 Chat com a operação', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            StreamBuilder<List<MensagemFrete>>(
              stream: _stream,
              builder: (context, snapshot) {
                final mensagens = snapshot.data ?? const <MensagemFrete>[];
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });
                return Container(
                  height: 220,
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.all(8),
                  child: mensagens.isEmpty
                      ? const Center(
                          child: Text('Nenhuma mensagem ainda.', style: TextStyle(fontSize: 12, color: Colors.black45)),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: mensagens.length,
                          itemBuilder: (context, i) {
                            final m = mensagens[i];
                            final souEu = m.remetenteTipo == 'motorista';
                            return Align(
                              alignment: souEu ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                                decoration: BoxDecoration(
                                  color: souEu ? AppTheme.frota600 : Colors.white,
                                  border: souEu ? null : Border.all(color: Colors.black12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      m.mensagem,
                                      style: TextStyle(fontSize: 13, color: souEu ? Colors.white : Colors.black87),
                                    ),
                                    Text(
                                      '${m.criadoEm.hour.toString().padLeft(2, '0')}:${m.criadoEm.minute.toString().padLeft(2, '0')}',
                                      style: TextStyle(fontSize: 10, color: souEu ? Colors.white70 : Colors.black45),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Escreva uma mensagem...', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _enviando ? null : _enviar,
                  icon: _enviando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send, color: AppTheme.frota600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _tagDetalhe(String texto, Color cor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(texto, style: TextStyle(fontSize: 10, color: cor)),
    );

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
