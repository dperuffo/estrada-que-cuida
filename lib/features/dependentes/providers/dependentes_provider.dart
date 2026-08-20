import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// "Conta Família" v1 — motorista cadastra dependentes (sem login próprio
// pra eles) e pode resgatar itens do catálogo "para" um deles. RLS já
// restringe tudo ao próprio motorista (auth_user_id).
class Dependente {
  final String id;
  final String nome;
  final String? parentesco;
  final DateTime? dataNascimento;

  Dependente({
    required this.id,
    required this.nome,
    this.parentesco,
    this.dataNascimento,
  });

  factory Dependente.fromJson(Map<String, dynamic> json) {
    return Dependente(
      id: json['id'] as String,
      nome: json['nome'] as String,
      parentesco: json['parentesco'] as String?,
      dataNascimento: json['data_nascimento'] != null
          ? DateTime.parse(json['data_nascimento'] as String)
          : null,
    );
  }
}

final dependentesProvider = FutureProvider.autoDispose<List<Dependente>>((
  ref,
) async {
  final rows = await SupabaseService.client
      .from('fidelidade_dependentes')
      .select('id, nome, parentesco, data_nascimento')
      .order('nome');
  return (rows as List)
      .map((e) => Dependente.fromJson(e as Map<String, dynamic>))
      .toList();
});

class DependentesService {
  static Future<void> adicionar({
    required String motoristaId,
    required String nome,
    String? parentesco,
    DateTime? dataNascimento,
  }) {
    return SupabaseService.client.from('fidelidade_dependentes').insert({
      'motorista_id': motoristaId,
      'nome': nome,
      'parentesco': parentesco,
      'data_nascimento': dataNascimento?.toIso8601String().substring(0, 10),
    });
  }

  static Future<void> remover(String id) {
    return SupabaseService.client
        .from('fidelidade_dependentes')
        .delete()
        .eq('id', id);
  }
}
