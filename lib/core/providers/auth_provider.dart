import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

// Login do motorista é só por telefone + código OTP (SMS via Twilio,
// configurado no painel do Supabase) — sem senha. Este provider expõe o
// stream de mudança de sessão (login/logout) pro resto do app reagir.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return SupabaseService.client.auth.onAuthStateChange;
});

final sessaoAtualProvider = Provider<Session?>((ref) {
  ref.watch(authStateProvider);
  return SupabaseService.client.auth.currentSession;
});

class AuthService {
  static SupabaseClient get _client => SupabaseService.client;

  /// Envia o código OTP por SMS pro telefone informado (formato E.164,
  /// ex.: +5511999998888).
  static Future<void> enviarCodigo(String telefoneE164) {
    return _client.auth.signInWithOtp(phone: telefoneE164);
  }

  /// Confirma o código recebido por SMS. Se certo, cria a sessão
  /// (auth.uid()) que o resto do app (RLS, RPC de vínculo) já usa.
  static Future<void> confirmarCodigo({
    required String telefoneE164,
    required String codigo,
  }) {
    return _client.auth.verifyOTP(
      phone: telefoneE164,
      token: codigo,
      type: OtpType.sms,
    );
  }

  // Fase login-por-senha — pedido do Daniel: telefone+SMS só no primeiro
  // acesso; dali em diante o motorista entra com telefone + senha numérica
  // de 6 dígitos. Usa suporte nativo do Supabase Auth pra "phone + password"
  // (mesmo mecanismo de email+senha, só que com telefone como identificador).

  /// Chamado ANTES de autenticar (LoginScreen), pra decidir se mostra o
  /// campo de senha ou já dispara o SMS de primeiro acesso. RPC pública
  /// (SECURITY DEFINER, grant pra `anon`) porque ainda não existe sessão
  /// aqui — só olha a tabela `motoristas` por telefone.
  static Future<bool> temSenha(String telefoneE164) async {
    final resp = await _client.rpc('motorista_tem_senha', params: {'p_telefone': telefoneE164});
    return resp as bool? ?? false;
  }

  /// Login nos acessos seguintes ao primeiro: telefone + senha, sem SMS.
  static Future<void> entrarComSenha({
    required String telefoneE164,
    required String senha,
  }) {
    return _client.auth.signInWithPassword(phone: telefoneE164, password: senha);
  }

  /// Confirma a senha ATUAL sem criar uma sessão nova — achado real: usar
  /// `entrarComSenha` (signInWithPassword) só pra "verificar" a senha atual
  /// dentro do fluxo de troca disparava um evento SIGNED_IN, e pra
  /// motorista com TOTP (2FA) ativo isso derrubava a sessão de volta pro
  /// nível aal1 e o GoRouter redirecionava à força pra tela de MFA no meio
  /// da troca de senha — a nova senha só gravava se `updateUser` vencesse
  /// essa corrida contra o redirect, e nem sempre vencia. RPC
  /// `motorista_verificar_senha_atual` compara o hash bcrypt direto (mesmo
  /// mecanismo do GoTrue) sem mexer na sessão.
  static Future<bool> verificarSenhaAtual(String senha) async {
    final resp = await _client.rpc('motorista_verificar_senha_atual', params: {'p_senha': senha});
    return resp as bool? ?? false;
  }

  /// Define (ou redefine) a senha do motorista já autenticado — chamado
  /// tanto na criação da senha no primeiro acesso quanto no fluxo de
  /// "esqueci minha senha" (que reusa o SMS como o "código temporário").
  /// `updateUser` grava a senha no auth.users; a RPC marca
  /// `motoristas.senha_definida = true` (o "portão" do app olha essa flag).
  static Future<void> definirSenha(String senha) async {
    await _client.auth.updateUser(UserAttributes(password: senha));
    await _client.rpc('motorista_definir_senha');
  }

  static Future<void> sair() {
    return _client.auth.signOut();
  }

  // Fase MFA-opcional (TOTP) — camada extra de segurança em cima do
  // telefone+senha, sugerida pro Daniel: um app autenticador (Google
  // Authenticator/Authy) gera um código de 6 dígitos que muda a cada 30s,
  // independente da operadora de telefone (ao contrário de um segundo SMS,
  // que cairia junto num golpe de SIM swap). Nada disso é obrigatório —
  // fica como opção em "Segurança" no menu.

  /// Começa o cadastro de um fator TOTP: devolve o QR code (como URI
  /// otpauth://, que a SegurancaScreen redesenha localmente com
  /// qr_flutter) e o segredo (pra digitar manualmente se não der pra
  /// escanear).
  static Future<AuthMFAEnrollResponse> mfaIniciarCadastro() {
    return _client.auth.mfa.enroll(factorType: FactorType.totp, friendlyName: 'Estrada que Cuida');
  }

  /// Confirma o cadastro (ou verifica no login) com o código de 6 dígitos
  /// gerado pelo app autenticador. `challengeAndVerify` já faz o
  /// challenge+verify num passo só.
  static Future<AuthMFAVerifyResponse> mfaVerificarCodigo({required String factorId, required String codigo}) {
    return _client.auth.mfa.challengeAndVerify(factorId: factorId, code: codigo);
  }

  static Future<AuthMFAListFactorsResponse> mfaListarFatores() {
    return _client.auth.mfa.listFactors();
  }

  static Future<void> mfaDesativar(String factorId) {
    return _client.auth.mfa.unenroll(factorId);
  }

  /// Síncrono de propósito (não bate na rede) — usado no `redirect` do
  /// router pra saber se, depois do login normal (aal1), ainda falta
  /// confirmar o código do app autenticador (aal2).
  static AuthMFAGetAuthenticatorAssuranceLevelResponse mfaNivelAtual() {
    return _client.auth.mfa.getAuthenticatorAssuranceLevel();
  }
}
