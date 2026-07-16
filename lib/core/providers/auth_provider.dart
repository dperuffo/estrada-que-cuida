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

  static Future<void> sair() {
    return _client.auth.signOut();
  }
}
