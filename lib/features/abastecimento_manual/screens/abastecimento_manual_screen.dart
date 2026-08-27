import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/abastecimento_manual_provider.dart';

// Fase OCR-Abastecimento-Externo (27/08/2026, pedido do Daniel: "o motorista
// tira foto, o sistema preenche litros/valor/posto sozinho — ataca o maior
// ponto de atrito hoje: digitação manual no aplicativo"). Fluxo: motorista
// escolhe veículo → tira foto do cupom fiscal do posto → o app lê a foto via
// OCR (rota do site, tesseract.js) e pré-preenche posto/combustível/litros/
// valor → motorista revisa/corrige tudo (nenhum campo é travado, o OCR é só
// sugestão) → envia. O lançamento entra PENDENTE — só conta nos indicadores
// e no financeiro depois que o gestor aprova na web (decisão do Daniel:
// diferente do Abastecimento Interno, que já entra confirmado).
class AbastecimentoManualScreen extends ConsumerStatefulWidget {
  const AbastecimentoManualScreen({super.key});

  @override
  ConsumerState<AbastecimentoManualScreen> createState() =>
      _AbastecimentoManualScreenState();
}

class _AbastecimentoManualScreenState
    extends ConsumerState<AbastecimentoManualScreen> {
  String? _empresaId;
  String? _placa;
  String? _combustivel;
  Uint8List? _fotoBytes;
  String? _ocrTexto;
  bool _lendoOcr = false;
  bool _enviando = false;
  String? _erro;

  final _postoCtrl = TextEditingController();
  final _litrosCtrl = TextEditingController();
  final _valorUnitarioCtrl = TextEditingController();
  final _valorTotalCtrl = TextEditingController();
  final _hodometroCtrl = TextEditingController();

  @override
  void dispose() {
    _postoCtrl.dispose();
    _litrosCtrl.dispose();
    _valorUnitarioCtrl.dispose();
    _valorTotalCtrl.dispose();
    _hodometroCtrl.dispose();
    super.dispose();
  }

  Future<void> _selecionarPlaca(String? placa) async {
    setState(() {
      _placa = placa;
      _hodometroCtrl.clear();
    });
    if (placa == null) return;
    final hod = await ref.read(
      ultimoHodometroAbastecimentoManualProvider(placa).future,
    );
    if (!mounted || _placa != placa) return;
    if (hod != null && hod > 0) {
      setState(() => _hodometroCtrl.text = hod.toStringAsFixed(0));
    }
  }

  // Mesmo padrão de câmera + confirmação já usado em
  // frete_detalhe_screen.dart (foto de evidência de checkpoint): abre a
  // câmera direto (sem passar pela galeria), mostra a foto e só usa depois
  // de confirmada — dá chance de tirar de novo se saiu ruim.
  Future<Uint8List?> _capturarFoto() async {
    try {
      final foto = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (foto == null) return null;
      return await foto.readAsBytes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não consegui abrir a câmera: $e')));
      }
      return null;
    }
  }

  Future<Uint8List?> _tirarFoto() async {
    while (true) {
      final bytes = await _capturarFoto();
      if (bytes == null || !mounted) return null;

      final confirmou = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Usar esta foto do cupom?'),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tirar de novo'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirmou == true) return bytes;
      if (confirmou == null) return null;
      if (!mounted) return null;
    }
  }

  Future<void> _fotografarELer() async {
    final bytes = await _tirarFoto();
    if (bytes == null || !mounted) return;

    setState(() {
      _fotoBytes = bytes;
      _lendoOcr = true;
      _erro = null;
    });

    final resultado = await OcrCupomAbastecimentoService().lerCupom(bytes);
    if (!mounted) return;

    setState(() {
      _lendoOcr = false;
      _ocrTexto = resultado.texto;
      if (resultado.postoNome != null && resultado.postoNome!.isNotEmpty) {
        _postoCtrl.text = resultado.postoNome!;
      }
      if (resultado.combustivel != null &&
          combustiveisAbastecimentoManual.contains(resultado.combustivel)) {
        _combustivel = resultado.combustivel;
      }
      if (resultado.litros != null) {
        _litrosCtrl.text = resultado.litros!.toStringAsFixed(3);
      }
      if (resultado.valorUnitario != null) {
        _valorUnitarioCtrl.text = resultado.valorUnitario!.toStringAsFixed(3);
      }
      if (resultado.valorTotal != null) {
        _valorTotalCtrl.text = resultado.valorTotal!.toStringAsFixed(2);
      }
    });

    if (resultado.erro != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${resultado.erro} Preencha os campos manualmente a partir da foto.',
          ),
        ),
      );
    }
  }

  Future<void> _enviar() async {
    if (_empresaId == null) {
      setState(() => _erro = 'Selecione a empresa dona do veículo.');
      return;
    }
    if (_placa == null) {
      setState(() => _erro = 'Selecione o veículo.');
      return;
    }
    if (_fotoBytes == null) {
      setState(() => _erro = 'Tire uma foto do cupom fiscal antes de enviar.');
      return;
    }
    if (_combustivel == null) {
      setState(() => _erro = 'Selecione o combustível abastecido.');
      return;
    }
    final litros = num.tryParse(_litrosCtrl.text.replaceAll(',', '.'));
    if (litros == null || litros <= 0) {
      setState(() => _erro = 'Informe a quantidade abastecida (litros).');
      return;
    }
    final valorTotal = num.tryParse(_valorTotalCtrl.text.replaceAll(',', '.'));
    if (valorTotal == null || valorTotal <= 0) {
      setState(() => _erro = 'Informe o valor total pago (do cupom).');
      return;
    }
    final hodometro = num.tryParse(_hodometroCtrl.text.replaceAll(',', '.'));
    if (hodometro == null || hodometro < 0) {
      setState(() => _erro = 'Informe o hodômetro atual (só números).');
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
      final opcoes = ref.read(opcoesAbastecimentoManualProvider).valueOrNull;
      final motoristaId = opcoes?.motoristaId;
      if (motoristaId == null) {
        setState(() => _erro = 'Não consegui identificar seu cadastro de motorista.');
        return;
      }

      final fotoPath = await enviarFotoCupomAbastecimento(
        motoristaId: motoristaId,
        bytes: _fotoBytes!,
      );

      final resultado = await AbastecimentoManualService.registrar(
        empresaId: _empresaId!,
        placa: _placa!,
        combustivel: _combustivel!,
        quantidade: litros,
        valorTotal: valorTotal,
        postoNome: _postoCtrl.text.trim().isEmpty ? 'Posto não identificado' : _postoCtrl.text.trim(),
        hodometro: hodometro,
        fotoPath: fotoPath,
        ocrTextoBruto: _ocrTexto,
      );

      if (!mounted) return;

      switch (resultado.status) {
        case 'registrado':
          final idTexto = resultado.codigoAbastecimento != null
              ? ' (ID ${resultado.codigoAbastecimento})'
              : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Abastecimento enviado$idTexto! Aguardando aprovação do gestor.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _combustivel = null;
            _fotoBytes = null;
            _ocrTexto = null;
            _postoCtrl.clear();
            _litrosCtrl.clear();
            _valorUnitarioCtrl.clear();
            _valorTotalCtrl.clear();
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
        case 'quantidade_invalida':
          setState(() => _erro = 'Quantidade inválida.');
          break;
        case 'valor_invalido':
          setState(() => _erro = 'Valor total inválido.');
          break;
        case 'hodometro_obrigatorio':
          setState(() => _erro = 'Informe o hodômetro atual (só números).');
          break;
        case 'foto_obrigatoria':
          setState(() => _erro = 'A foto do cupom é obrigatória.');
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
    final opcoesAsync = ref.watch(opcoesAbastecimentoManualProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Lançar Abastecimento'),
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
                  'Nenhuma empresa do seu grupo disponível no momento.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Abasteceu num posto fora da frota (fora da integração automática)? Tire uma foto do cupom fiscal — o app tenta preencher os campos sozinho, você só confere e envia. Fica pendente até seu gestor aprovar.',
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
                  labelText: 'Empresa',
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
                onChanged: (v) => setState(() => _empresaId = v),
              ),
              const SizedBox(height: 12),
              if (opcoes.placas.isEmpty)
                const Text(
                  'Nenhum veículo vinculado a você no momento.',
                  style: TextStyle(color: Colors.black54),
                )
              else ...[
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
                  onChanged: _selecionarPlaca,
                ),
                Builder(
                  builder: (context) {
                    if (_placa == null && opcoes.placas.length == 1) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _placa == null) {
                          _selecionarPlaca(opcoes.placas.first);
                        }
                      });
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _hodometroCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Hodômetro (km)',
                  border: OutlineInputBorder(),
                  helperText: 'Preenchido automaticamente — confira e corrija se preciso.',
                ),
              ),
              const SizedBox(height: 20),

              // --- Foto do cupom ---------------------------------------
              if (_fotoBytes == null)
                OutlinedButton.icon(
                  onPressed: _fotografarELer,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Tirar foto do cupom fiscal'),
                )
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_fotoBytes!, height: 160, fit: BoxFit.cover, width: double.infinity),
                ),
                const SizedBox(height: 8),
                if (_lendoOcr)
                  const Row(
                    children: [
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Lendo o cupom...'),
                    ],
                  )
                else
                  TextButton.icon(
                    onPressed: _fotografarELer,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tirar outra foto'),
                  ),
              ],

              const SizedBox(height: 16),
              const Text(
                'Confira os dados (preenchidos pela leitura da foto — corrija o que precisar):',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _postoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Posto',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _combustivel,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Combustível abastecido',
                  border: OutlineInputBorder(),
                ),
                items: combustiveisAbastecimentoManual
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _combustivel = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _litrosCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Litros',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _valorUnitarioCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Preço por litro (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _valorTotalCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Valor total pago (R\$)',
                  border: OutlineInputBorder(),
                  helperText: 'O valor que está no cupom — confira antes de enviar.',
                ),
              ),

              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                child: _enviando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enviar para aprovação'),
              ),
            ],
          );
        },
      ),
    );
  }
}
