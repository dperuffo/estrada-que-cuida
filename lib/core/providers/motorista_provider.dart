import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';

// Status possíveis devolvidos pela função `vincular_motorista_auth` no
// banco (SECURITY DEFINER — ver migração criar_funcao_vincular_motorista_auth):
//   ja_vinculado      -> este auth.uid() já está ligado a um motorista.
//   vinculado         -> achou 1 motorista só pelo telefone (ou telefone+CPF)
//                        e acabou de ligar agora.
//   ambiguo_requer_cpf -> mais de um motorista com esse telefone; precisa
//                        de CPF pra desempatar.
//   nao_encontrado    -> nenhum motorista com esse telefone (e CPF, se veio)
//                        está cadastrado em nenhuma empresa ainda.
//   sem_telefone_na_sessao / nao_autenticado -> erro de sessão.
class VinculoResultado {
  final String status;
  final String? motoristaId;
  final String? nome;

  VinculoResultado({required this.status, this.motoristaId, this.nome});

  factory VinculoResultado.fromJson(Map<String, dynamic> json) {
    return VinculoResultado(
      status: json['status'] as String,
      motoristaId: json['motorista_id'] as String?,
      nome: json['nome'] as String?,
    );
  }
}

/// Chama a RPC de vínculo. `cpf` só é necessário quando o resultado
/// anterior veio `ambiguo_requer_cpf` ou `nao_encontrado`.
final vinculoProvider = FutureProvider.autoDispose.family<VinculoResultado, String?>((ref, cpf) async {
  // Passar null explícito equivale a omitir o parâmetro — a função no
  // banco já tem `p_cpf text default null`.
  final resp = await SupabaseService.client.rpc('vincular_motorista_auth', params: {'p_cpf': cpf});
  return VinculoResultado.fromJson(resp as Map<String, dynamic>);
});

/// true se o motorista já aderiu ao programa (linha `ativo` em
/// fidelidade_adesoes) — RLS já restringe a leitura só à linha dele.
final adesaoAtivaProvider = FutureProvider.autoDispose<bool>((ref) async {
  final rows = await SupabaseService.client
      .from('fidelidade_adesoes')
      .select('id')
      .eq('status', 'ativo')
      .limit(1);
  return (rows as List).isNotEmpty;
});

class PerfilMotorista {
  final String id;
  final String nomeCompleto;
  final String? telefone;

  PerfilMotorista({required this.id, required this.nomeCompleto, this.telefone});

  factory PerfilMotorista.fromJson(Map<String, dynamic> json) {
    return PerfilMotorista(
      id: json['id'] as String,
      nomeCompleto: json['nome_completo'] as String,
      telefone: json['telefone'] as String?,
    );
  }
}

// Perfil básico do motorista logado — usado pelo AppDrawer (menu lateral)
// pra mostrar nome/telefone sem cada tela precisar replicar esses dados via
// construtor. RPC SECURITY DEFINER (meu_perfil_motorista) filtra por
// auth_user_id = auth.uid() internamente.
final meuPerfilProvider = FutureProvider.autoDispose<PerfilMotorista?>((ref) async {
  final resp = await SupabaseService.client.rpc('meu_perfil_motorista');
  final lista = resp as List;
  if (lista.isEmpty) return null;
  return PerfilMotorista.fromJson(lista.first as Map<String, dynamic>);
});
