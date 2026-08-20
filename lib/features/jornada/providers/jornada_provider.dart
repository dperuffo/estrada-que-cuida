import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Fase Grupo-1-item-4 (02/08/2026, benchmark FNI vs KMM) — controle de
// jornada do motorista: eventos pontuais, sem telemetria contínua. Dá pra
// saber o estado atual olhando só o último evento.
//
// Fase Painel-Jornada-Motorista (17/08/2026, pedido do Daniel: painel do
// gestor com indicadores de jornada) — dois eventos novos além dos
// originais ('inicio_jornada'/'inicio_descanso'): 'inicio_pausa' e
// 'fim_pausa', marcando uma parada curta (refeição, espera de carga/
// descarga, intervalo obrigatório) sem encerrar o dia. Sem isso não dava
// pra calcular tempo de condução contínua de verdade nem checar aderência
// à pausa exigida pela Lei do Motorista (13.103/2015) — só dava pra saber
// quando o motorista começou/parou de trabalhar no dia.

class JornadaEvento {
  final String id;
  final String
  tipoEvento; // 'inicio_jornada' | 'inicio_descanso' | 'inicio_pausa' | 'fim_pausa'
  final DateTime criadoEm;

  const JornadaEvento({
    required this.id,
    required this.tipoEvento,
    required this.criadoEm,
  });

  factory JornadaEvento.fromMap(Map<String, dynamic> m) => JornadaEvento(
    id: m['id'] as String,
    tipoEvento: m['tipo_evento'] as String,
    criadoEm: DateTime.parse(m['criado_em'] as String),
  );
}

// Só os últimos eventos bastam pra saber o estado atual — não precisa do
// histórico inteiro aqui (isso poderia virar uma tela de histórico depois).
final jornadaEventosProvider = FutureProvider.autoDispose<List<JornadaEvento>>((
  ref,
) async {
  final linhas = await SupabaseService.client
      .from('motoristas_jornada_eventos')
      .select()
      .order('criado_em', ascending: false)
      .limit(5);
  return (linhas as List)
      .map((l) => JornadaEvento.fromMap(l as Map<String, dynamic>))
      .toList();
});

// Fase Jornada-Gamificacao (02/08/2026, pedido do Daniel) — início de jornada
// e início de descanso passam a valer pontos de fidelidade e contar pra
// missões ("Primeira Jornada", "Rotina de Jornada", "Primeira Pausa",
// "Motorista Consciente"). Por isso o registro deixou de ser um insert
// direto na tabela (a política de RLS que permitia isso foi removida) e
// passou a chamar a RPC `registrar_evento_jornada_motorista`, que faz tudo
// isso atomicamente (grava o evento + credita pontos + loga engajamento) —
// mesmo padrão da RPC `registrar_inspecao_motorista`.
class RegistroJornada {
  final String status; // 'registrado' | 'nao_vinculado'
  final int? pontos;

  const RegistroJornada({required this.status, this.pontos});

  factory RegistroJornada.fromJson(Map<String, dynamic> json) =>
      RegistroJornada(
        status: json['status'] as String,
        pontos: (json['pontos'] as num?)?.round(),
      );
}

Future<RegistroJornada> registrarEventoJornada(String tipoEvento) async {
  final resp = await SupabaseService.client.rpc(
    'registrar_evento_jornada_motorista',
    params: {'p_tipo_evento': tipoEvento},
  );
  return RegistroJornada.fromJson(resp as Map<String, dynamic>);
}
