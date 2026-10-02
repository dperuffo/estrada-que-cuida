import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/abastecimento_pdv_provider.dart';

// Sem locale explícito ("pt_BR") de propósito — o app nunca chama
// initializeDateFormatting() (nenhuma outra tela usa DateFormat com
// locale), então um DateFormat com locale explícito lança
// LocaleDataException em tempo de execução (achado real: tela ficava em
// branco, sem erro visível, no teste do Daniel). Mesmo padrão das demais
// telas (DateFormat('dd/MM/yyyy HH:mm') etc.) — só o padrão muda.
final _formatoHora = DateFormat('HH:mm');

// Fase 2 PDV (02/10/2026) — Tela 2 do fluxo: código + OTP. Mostra o
// código de 10 dígitos (fixo pra essa transação) e um OTP de 6 dígitos
// que muda a cada 30s — o motorista mostra os dois ao frentista, que
// digita no PDV pra validar (validar_codigo_abastecimento_pdv). O
// contador regressivo é decrementado localmente a cada segundo, mas
// ressincroniza com o servidor (obter_otp_atual_pdv) sempre que chega a
// zero — evita depender só do relógio do aparelho pra saber quando a
// janela de 30s realmente virou no banco.
class AbastecimentoPdvOtpScreen extends StatefulWidget {
  final int abastecimentoPdvId;
  final String? codigoInicial;
  final String? otpInicial;
  final DateTime? otpValidoAteTransacao;
  final String? nomeRevenda;

  const AbastecimentoPdvOtpScreen({
    super.key,
    required this.abastecimentoPdvId,
    this.codigoInicial,
    this.otpInicial,
    this.otpValidoAteTransacao,
    this.nomeRevenda,
  });

  @override
  State<AbastecimentoPdvOtpScreen> createState() => _AbastecimentoPdvOtpScreenState();
}

class _AbastecimentoPdvOtpScreenState extends State<AbastecimentoPdvOtpScreen> {
  String? _codigo;
  String? _otp;
  int _segundosRestantes = 30;
  Timer? _timer;
  bool _carregandoRefresh = false;
  String? _erro;
  String? _statusTransacao; // null enquanto não resincronizou 1x

  @override
  void initState() {
    super.initState();
    _codigo = widget.codigoInicial;
    _otp = widget.otpInicial;
    _resincronizar(iniciandoTimer: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resincronizar({bool iniciandoTimer = false}) async {
    setState(() => _carregandoRefresh = true);
    try {
      final r = await AbastecimentoPdvService.obterOtpAtual(widget.abastecimentoPdvId);
      if (!mounted) return;
      setState(() {
        _statusTransacao = r.status;
        if (r.status == 'aguardando_pdv') {
          _codigo = r.codigoAbastecimento ?? _codigo;
          _otp = r.otpAtual ?? _otp;
          _segundosRestantes = r.segundosRestantesJanela ?? 30;
          _erro = null;
        }
      });
      if (iniciandoTimer) _iniciarTimer();
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não consegui atualizar o código agora.');
    } finally {
      if (mounted) setState(() => _carregandoRefresh = false);
    }
  }

  void _iniciarTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_statusTransacao != 'aguardando_pdv') {
        _timer?.cancel();
        return;
      }
      if (_segundosRestantes <= 1) {
        _resincronizar();
      } else {
        setState(() => _segundosRestantes -= 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassNavGradient),
        ),
        foregroundColor: AppTheme.glassTexto,
        iconTheme: const IconThemeData(color: AppTheme.glassIcone),
        title: const Text('Código do abastecimento'),
      ),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.nomeRevenda != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                widget.nomeRevenda!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          const Text(
            'Mostre este código e este OTP ao frentista para confirmar o abastecimento no PDV.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          _buildCard(
            label: 'Código do abastecimento',
            valor: _codigo ?? '----------',
          ),
          const SizedBox(height: 16),
          _buildCardOtp(),
          if (widget.otpValidoAteTransacao != null) ...[
            const SizedBox(height: 16),
            Text(
              'Válido até ${_formatoHora.format(widget.otpValidoAteTransacao!.toLocal())}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ],
          if (_statusTransacao != null && _statusTransacao != 'aguardando_pdv') ...[
            const SizedBox(height: 20),
            Card(
              color: AppTheme.statusInativo.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _mensagemStatus(_statusTransacao!),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.statusInativo)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.push('/abastecimento-pdv/acompanhar/${widget.abastecimentoPdvId}'),
            child: const Text('Acompanhar confirmação'),
          ),
        ],
      ),
    );
  }

  String _mensagemStatus(String status) {
    switch (status) {
      case 'expirado':
        return 'Esse código expirou. Volte e inicie o abastecimento de novo.';
      case 'confirmado':
        return 'Esse abastecimento já foi confirmado pelo posto! Toque em "Acompanhar confirmação" para ver o resultado.';
      case 'negado':
        return 'Esse abastecimento foi negado pelo posto. Toque em "Acompanhar confirmação" para ver o motivo.';
      default:
        return 'Não é mais possível usar esse código.';
    }
  }

  Widget _buildCard({required String label, required String valor}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 8),
            Text(
              valor,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: AppTheme.frota700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardOtp() {
    final progresso = _segundosRestantes / 30;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            const Text('OTP (muda a cada 30s)', style: TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 8),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: progresso.clamp(0, 1),
                    strokeWidth: 4,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation(AppTheme.accento),
                  ),
                ),
                Text('$_segundosRestantes', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _otp ?? '------',
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
                color: AppTheme.accento,
              ),
            ),
            if (_carregandoRefresh) ...[
              const SizedBox(height: 8),
              const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
