import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Fase Grupo-1-item-4 (02/08/2026, benchmark FNI vs KMM) — controle de
// jornada do motorista, versão simplificada: só dois botões ("Iniciar
// jornada" / "Iniciar descanso") gravando timestamps pontuais, sem
// telemetria contínua. Dá pra calcular quanto tempo o motorista está
// dirigindo sem parar olhando só o último evento — se o mais recente for
// 'inicio_jornada', ele está dirigindo desde aquele horário; se for
// 'inicio_descanso', está descansando desde aquele horário.

class JornadaEvento {
  final String id;
  final String tipoEvento; // 'inicio_jornada' | 'inicio_descanso'
  final DateTime criadoEm;

  const JornadaEvento({required this.id, required this.tipoEvento, required this.criadoEm});

  factory JornadaEvento.fromMap(Map<String, dynamic> m) => JornadaEvento(
        id: m['id'] as String,
        tipoEvento: m['tipo_evento'] as String,
        criadoEm: DateTime.parse(m['criado_em'] as String),
      );
}

// Só os últimos eventos bastam pra saber o estado atual — não precisa do
// histórico inteiro aqui (isso poderia virar uma tela de histórico depois).
final jornadaEventosProvider = FutureProvider.autoDispose<List<JornadaEvento>>((ref) async {
  final linhas = await SupabaseService.client
      .from('motoristas_jornada_eventos')
      .select()
      .order('criado_em', ascending: false)
      .limit(5);
  return (linhas as List).map((l) => JornadaEvento.fromMap(l as Map<String, dynamic>)).toList();
});

Future<void> registrarEventoJornada(String motoristaId, String tipoEvento) async {
  await SupabaseService.client.from('motoristas_jornada_eventos').insert({
    'motorista_id': motoristaId,
    'tipo_evento': tipoEvento,
  });
}
