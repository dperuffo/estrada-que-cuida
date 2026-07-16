import 'package:supabase_flutter/supabase_flutter.dart';

// Mesmo projeto Supabase do app de empresa/posto (nedthbeekvwzcjrhsghp) —
// "Estrada que Cuida" é um app separado, mas fala com o mesmo banco. Chave
// abaixo é a "anon"/"publishable" (pública, não secreta — a proteção real
// vem das políticas de RLS, não do sigilo desta chave).
class SupabaseService {
  static const String supabaseUrl = 'https://nedthbeekvwzcjrhsghp.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5lZHRoYmVla3Z3emNqcmhzZ2hwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNTUyMzUsImV4cCI6MjA5NDczMTIzNX0.VBgDNFAXysqX9HDiJYYjFxgtsP1zaj3LH1EbZQXH00E';

  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
