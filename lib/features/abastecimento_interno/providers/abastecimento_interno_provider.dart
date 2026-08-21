import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Fase Abastecimento-Interno (21/08/2026, pedido do Daniel) — o veículo pode
// sair pra rota já abastecido na garagem própria do cliente (matriz ou
// filial), antes de qualquer parada em posto revendedor externo. O motorista
// confirma esse abastecimento aqui no app; ele já sobe pra visão do
// cliente/admin identificado como "Abastecimento Interno" (mesma tabela
// abastecimentos_internos usada pela tela web /abastecimentos, view
// abastecimentos_unificado com provedor='interno').
//
// Mesmo padrão de inspecao_veicular: 2 RPCs SECURITY DEFINER —
// `abastecimento_interno_formulario_motorista` (opções do formulário,
// resolve tudo a partir do auth.uid() do motorista) e
// `registrar_abastecimento_interno` (grava, com preço sempre resolvido no
// servidor — nunca confia no que vier do app).

class EmpresaPostoInterno {
  final String empresaId;
  final String nome;
  const EmpresaPostoInterno({required this.empresaId, required this.nome});
}

class PrecoPostoInterno {
  final String empresaId;
  final String combustivel;
  final num preco;
  const PrecoPostoInterno({
    required this.empresaId,
    required this.combustivel,
    required this.preco,
  });
}

class OpcoesAbastecimentoInterno {
  final String? motoristaId;
  final String? motoristaNome;
  final List<String> placas;
  final List<EmpresaPostoInterno> empresas;
  final List<PrecoPostoInterno> precos;

  const OpcoesAbastecimentoInterno({
    required this.motoristaId,
    required this.motoristaNome,
    required this.placas,
    required this.empresas,
    required this.precos,
  });

  // Combustíveis com preço cadastrado pra essa empresa — só esses fazem
  // sentido oferecer no seletor (evita escolher algo sem preço e tomar erro
  // só na hora de confirmar).
  Map<String, num> precosPorCombustivel(String empresaId) {
    return {
      for (final p in precos)
        if (p.empresaId == empresaId) p.combustivel: p.preco,
    };
  }

  static const empty = OpcoesAbastecimentoInterno(
    motoristaId: null,
    motoristaNome: null,
    placas: [],
    empresas: [],
    precos: [],
  );

  factory OpcoesAbastecimentoInterno.fromJson(Map<String, dynamic> json) {
    if (json['status'] != 'ok') return OpcoesAbastecimentoInterno.empty;
    return OpcoesAbastecimentoInterno(
      motoristaId: json['motoristaId'] as String?,
      motoristaNome: json['motoristaNome'] as String?,
      placas: (json['placas'] as List? ?? []).map((e) => e as String).toList(),
      empresas: (json['empresas'] as List? ?? [])
          .map(
            (e) => EmpresaPostoInterno(
              empresaId: (e as Map<String, dynamic>)['empresaId'] as String,
              nome: e['nome'] as String? ?? '',
            ),
          )
          .toList(),
      precos: (json['precos'] as List? ?? [])
          .map(
            (e) => PrecoPostoInterno(
              empresaId: (e as Map<String, dynamic>)['empresaId'] as String,
              combustivel: e['combustivel'] as String,
              preco: e['preco'] as num,
            ),
          )
          .toList(),
    );
  }
}

final opcoesAbastecimentoInternoProvider =
    FutureProvider.autoDispose<OpcoesAbastecimentoInterno>((ref) async {
      final resp = await SupabaseService.client.rpc(
        'abastecimento_interno_formulario_motorista',
      );
      return OpcoesAbastecimentoInterno.fromJson(resp as Map<String, dynamic>);
    });

// Fase Abastecimento-Interno — ajuste (21/08/2026, pedido do Daniel: "o
// hodometro não é opcional, é obrigatorio e ja tem que trazer a informação
// do hodometro atual em tela, automaticamente") — mesma RPC
// `ultimo_hodometro_veiculo` já usada no Checklist de Inspeção
// (ultimoHodometroInspecaoProvider): pega o maior hodômetro conhecido pro
// veículo (último abastecimento — já inclui o interno, via
// abastecimentos_unificado — ou última inspeção).
final ultimoHodometroAbastecimentoInternoProvider = FutureProvider.autoDispose
    .family<num?, String>((ref, placa) async {
      final resp = await SupabaseService.client.rpc(
        'ultimo_hodometro_veiculo',
        params: {'p_placa': placa},
      );
      return resp as num?;
    });

class AbastecimentoInternoResultado {
  final String status;
  final num? valorTotal;
  final num? arlaValorTotal;

  const AbastecimentoInternoResultado({
    required this.status,
    this.valorTotal,
    this.arlaValorTotal,
  });

  factory AbastecimentoInternoResultado.fromJson(Map<String, dynamic> json) {
    return AbastecimentoInternoResultado(
      status: json['status'] as String,
      valorTotal: json['valorTotal'] as num?,
      arlaValorTotal: json['arlaValorTotal'] as num?,
    );
  }
}

class AbastecimentoInternoService {
  static Future<AbastecimentoInternoResultado> registrar({
    required String empresaId,
    required String placa,
    required String combustivel,
    required num quantidade,
    num? arlaQuantidade,
    num? hodometro,
  }) async {
    final resp = await SupabaseService.client.rpc(
      'registrar_abastecimento_interno',
      params: {
        'p_empresa_id': empresaId,
        'p_placa': placa,
        'p_combustivel': combustivel,
        'p_quantidade': quantidade,
        'p_arla_quantidade': arlaQuantidade,
        'p_hodometro': hodometro,
      },
    );
    return AbastecimentoInternoResultado.fromJson(resp as Map<String, dynamic>);
  }
}
