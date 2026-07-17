import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_drawer.dart';

// Fase MFA-opcional — tela de "Segurança": mostra se já existe um fator
// TOTP verificado e deixa ativar/desativar. Sem estado global (Riverpod)
// de propósito: essa tela é a única que precisa dessa informação, então
// carrega direto via AuthService.mfaListarFatores() no initState.
class SegurancaScreen extends StatefulWidget {
  const SegurancaScreen({super.key});

  @override
  State<SegurancaScreen> createState() => _SegurancaScreenState();
}

class _SegurancaScreenState extends State<SegurancaScreen> {
  bool _carregando = true;
  Factor? _fatorAtivo;
  String? _erro;

  // Estado do fluxo de cadastro (só usado enquanto _fatorAtivo == null).
  bool _cadastrando = false;
  AuthMFAEnrollResponse? _cadastroEmAndamento;
  final _codigoCtrl = TextEditingController();
  bool _confirmando = false;
  String? _erroCadastro;

  // Alterar senha (Fase Segurança-2) — pedido do Daniel: "inserir mecanismo
  // de alteração de senha dentro do PWA motorista na aba Segurança". Exige a
  // senha atual antes de trocar (reautentica com AuthService.entrarComSenha,
  // mesma checagem do login normal) — evita que alguém com o celular
  // destravado troque a senha sem saber a atual.
  final _senhaAtualCtrl = TextEditingController();
  final _novaSenhaCtrl = TextEditingController();
  final _confirmarNovaSenhaCtrl = TextEditingController();
  bool _alterandoSenha = false;
  String? _erroSenha;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _senhaAtualCtrl.dispose();
    _novaSenhaCtrl.dispose();
    _confirmarNovaSenhaCtrl.dispose();
    super.dispose();
  }

  Future<void> _alterarSenha() async {
    final atual = _senhaAtualCtrl.text.trim();
    final nova = _novaSenhaCtrl.text.trim();
    final confirmar = _confirmarNovaSenhaCtrl.text.trim();

    if (atual.length != 6) {
      setState(() => _erroSenha = 'Digite os 6 dígitos da sua senha atual.');
      return;
    }
    if (nova.length != 6) {
      setState(() => _erroSenha = 'A nova senha precisa ter exatamente 6 números.');
      return;
    }
    if (nova != confirmar) {
      setState(() => _erroSenha = 'As senhas digitadas são diferentes.');
      return;
    }
    if (nova == atual) {
      setState(() => _erroSenha = 'A nova senha precisa ser diferente da atual.');
      return;
    }

    // auth.users.phone vem sem o "+" (mesmo formato usado no vínculo por
    // telefone) — telefoneE164 aqui precisa do "+", igual ao login normal.
    final telefone = SupabaseService.client.auth.currentUser?.phone;
    if (telefone == null || telefone.isEmpty) {
      setState(() => _erroSenha = 'Não consegui identificar seu telefone. Saia e entre de novo.');
      return;
    }

    setState(() {
      _alterandoSenha = true;
      _erroSenha = null;
    });
    try {
      await AuthService.entrarComSenha(telefoneE164: '+$telefone', senha: atual);
      await AuthService.definirSenha(nova);
      if (!mounted) return;
      setState(() {
        _alterandoSenha = false;
        _senhaAtualCtrl.clear();
        _novaSenhaCtrl.clear();
        _confirmarNovaSenhaCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada com sucesso!')));
    } catch (e) {
      setState(() {
        _erroSenha = 'Senha atual incorreta. Confira e tente de novo.';
        _alterandoSenha = false;
      });
    }
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final fatores = await AuthService.mfaListarFatores();
      final verificado = fatores.totp.where((f) => f.status == FactorStatus.verified);
      setState(() {
        _fatorAtivo = verificado.isEmpty ? null : verificado.first;
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Não consegui carregar suas configurações de segurança.';
        _carregando = false;
      });
    }
  }

  Future<void> _iniciarCadastro() async {
    setState(() {
      _cadastrando = true;
      _erroCadastro = null;
    });
    try {
      final resp = await AuthService.mfaIniciarCadastro();
      setState(() => _cadastroEmAndamento = resp);
    } catch (e) {
      setState(() {
        _erroCadastro = 'Não consegui iniciar o cadastro. Tente de novo.';
        _cadastrando = false;
      });
    }
  }

  Future<void> _confirmarCadastro() async {
    final cadastro = _cadastroEmAndamento;
    if (cadastro == null) return;
    final codigo = _codigoCtrl.text.trim();
    if (codigo.length != 6) {
      setState(() => _erroCadastro = 'Digite o código de 6 dígitos do app autenticador.');
      return;
    }
    setState(() {
      _confirmando = true;
      _erroCadastro = null;
    });
    try {
      await AuthService.mfaVerificarCodigo(factorId: cadastro.id, codigo: codigo);
      if (!mounted) return;
      setState(() {
        _cadastrando = false;
        _cadastroEmAndamento = null;
        _confirmando = false;
        _codigoCtrl.clear();
      });
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Verificação em duas etapas ativada!')));
    } catch (e) {
      setState(() {
        _erroCadastro = 'Código incorreto. Confira no app autenticador e tente de novo.';
        _confirmando = false;
      });
    }
  }

  Future<void> _cancelarCadastro() async {
    final cadastro = _cadastroEmAndamento;
    setState(() {
      _cadastrando = false;
      _cadastroEmAndamento = null;
      _codigoCtrl.clear();
      _erroCadastro = null;
    });
    // Fator "unverified" abandonado não atrapalha (não conta pra AAL),
    // mas evita deixar lixo pra trás.
    if (cadastro != null) {
      try {
        await AuthService.mfaDesativar(cadastro.id);
      } catch (_) {}
    }
  }

  Future<void> _desativar() async {
    final fator = _fatorAtivo;
    if (fator == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desativar verificação em duas etapas?'),
        content: const Text('Você vai voltar a entrar só com telefone e senha.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desativar')),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await AuthService.mfaDesativar(fator.id);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não consegui desativar agora.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Segurança')),
      drawer: const AppDrawer(),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Alterar senha', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Digite sua senha atual e a nova senha numérica de 6 dígitos.'),
                    const SizedBox(height: 20),
                    _blocoAlterarSenha(),
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text('Verificação em duas etapas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'Opcional. Além da senha, um app autenticador (Google Authenticator, Authy) gera um código de 6 dígitos que muda a cada 30 segundos, exigido a cada login.',
                    ),
                    const SizedBox(height: 20),
                    if (_fatorAtivo != null) _blocoAtivo() else _blocoCadastro(),
                  ],
                ),
    );
  }

  Widget _blocoAlterarSenha() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CampoSenha(controller: _senhaAtualCtrl, label: 'Senha atual'),
            const SizedBox(height: 12),
            _CampoSenha(controller: _novaSenhaCtrl, label: 'Nova senha'),
            const SizedBox(height: 12),
            _CampoSenha(controller: _confirmarNovaSenhaCtrl, label: 'Confirme a nova senha', onSubmitted: _alterarSenha),
            if (_erroSenha != null) ...[
              const SizedBox(height: 8),
              Text(_erroSenha!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _alterandoSenha ? null : _alterarSenha,
              child: _alterandoSenha
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Salvar nova senha'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blocoAtivo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.verified_user, color: Colors.green, size: 32),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Verificação em duas etapas está ativada.', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TextButton(onPressed: _desativar, child: const Text('Desativar')),
          ],
        ),
      ),
    );
  }

  Widget _blocoCadastro() {
    if (!_cadastrando) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            onPressed: _iniciarCadastro,
            child: const Text('Ativar verificação em duas etapas'),
          ),
          if (_erroCadastro != null) ...[
            const SizedBox(height: 8),
            Text(_erroCadastro!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
          ],
        ],
      );
    }

    final cadastro = _cadastroEmAndamento;
    if (cadastro == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final totp = cadastro.totp!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('1. Escaneie o QR code com o app autenticador', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: QrImageView(data: totp.uri, size: 200),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: totp.secret));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado.')));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Não consigo escanear — copiar código manual'),
              ),
            ),
            const Divider(height: 32),
            const Text('2. Digite o código de 6 dígitos gerado pelo app', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _codigoCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: const TextStyle(fontSize: 22, letterSpacing: 6),
              decoration: const InputDecoration(hintText: '000000', counterText: ''),
            ),
            if (_erroCadastro != null) ...[
              const SizedBox(height: 8),
              Text(_erroCadastro!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _confirmando ? null : _cancelarCadastro,
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirmando ? null : _confirmarCadastro,
                    child: _confirmando
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Confirmar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CampoSenha extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final VoidCallback? onSubmitted;

  const _CampoSenha({required this.controller, required this.label, this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 22, letterSpacing: 6),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, hintText: '••••••', counterText: ''),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
    );
  }
}
