import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Fase Inspeção-pelo-Motorista (30/07/2026) — pedido do Daniel: "A inspeção
// do veiculo tambem pode ser realizada pelo motorista, rotineiramente e,
// virar um item de engajamento do programa de fidelidade". Mesma lista de
// itens usada no checklist do gestor/painel web (src/lib/checklist.ts) e no
// PWA Cliente (checklist_veiculos_provider.dart) — mantida idêntica pra não
// divergir do histórico já registrado nas outras telas.
const itensInspecao = [
  'Pneus',
  'Freios',
  'Luzes',
  'Óleo e fluidos',
  'Cintos de segurança',
  'Extintor de incêndio',
  'Documentação (CRLV)',
  'Retrovisores',
  'Buzina',
  'Limpador de para-brisa',
  'Estepe',
  'Triângulo e macaco',
];

const itensCriticos = ['Pneus', 'Freios'];

// Veículo(s) do motorista logado, resolvido pela mesma RPC usada na
// Roteirização (`meus_veiculos_roteirizacao`) — reaproveitada aqui só pra
// preencher o seletor de placa do formulário, sem duplicar a lógica de
// vínculo motorista×veículo no client.
class VeiculoInspecao {
  final String placa;
  final String? marca;
  final String? modelo;

  const VeiculoInspecao({required this.placa, this.marca, this.modelo});

  String get rotulo => [marca, modelo].where((e) => e != null && e.isNotEmpty).join(' ').isEmpty
      ? placa
      : '$placa · ${[marca, modelo].where((e) => e != null && e.isNotEmpty).join(' ')}';
}

final veiculosInspecaoProvider = FutureProvider.autoDispose<List<VeiculoInspecao>>((ref) async {
  final resp = await SupabaseService.client.rpc('meus_veiculos_roteirizacao');
  return (resp as List).map((e) {
    final mapa = e as Map<String, dynamic>;
    return VeiculoInspecao(
      placa: mapa['placa'] as String,
      marca: mapa['marca'] as String?,
      modelo: mapa['modelo'] as String?,
    );
  }).toList();
});

// Histórico das inspeções que o próprio motorista já registrou, mais
// recente primeiro — mostrado no topo da tela pra ele acompanhar o que já
// fez sem precisar sair do app.
class InspecaoRegistrada {
  final int id;
  final String placa;
  final DateTime dataInspecao;
  final num? hodometro;
  final int itensNaoConformes;

  const InspecaoRegistrada({
    required this.id,
    required this.placa,
    required this.dataInspecao,
    this.hodometro,
    required this.itensNaoConformes,
  });

  factory InspecaoRegistrada.fromJson(Map<String, dynamic> json) {
    return InspecaoRegistrada(
      id: json['id'] as int,
      placa: json['placa'] as String,
      dataInspecao: DateTime.parse(json['data_inspecao'] as String),
      hodometro: json['hodometro'] as num?,
      itensNaoConformes: (json['itens_nao_conformes'] as num?)?.toInt() ?? 0,
    );
  }
}

// Leitura via RPC dedicada (`minhas_inspecoes_motorista`, SECURITY DEFINER)
// em vez de `.from('inspecoes_veiculos').select(...)` direto — as policies
// de RLS dessa tabela são todas amarradas ao JWT de e-mail do gestor
// (`empresas_do_usuario`), e a sessão do motorista (telefone+OTP) não tem
// esse claim, então um select direto retornaria sempre vazio.
final minhasInspecoesProvider = FutureProvider.autoDispose<List<InspecaoRegistrada>>((ref) async {
  final resp = await SupabaseService.client.rpc('minhas_inspecoes_motorista');
  return (resp as List).map((e) => InspecaoRegistrada.fromJson(e as Map<String, dynamic>)).toList();
});

class InspecaoResultado {
  final String status;
  final int? pontos;
  final int? itensNaoConformes;

  InspecaoResultado({required this.status, this.pontos, this.itensNaoConformes});

  factory InspecaoResultado.fromJson(Map<String, dynamic> json) {
    return InspecaoResultado(
      status: json['status'] as String,
      pontos: json['pontos'] as int?,
      itensNaoConformes: json['itens_nao_conformes'] as int?,
    );
  }
}

class InspecaoVeicularService {
  static Future<InspecaoResultado> registrar({
    required String placa,
    required DateTime dataInspecao,
    required num hodometro,
    required Map<String, bool> conformidadePorItem,
    required Map<String, String> observacoesPorItem,
  }) async {
    final itens = itensInspecao
        .map((item) => {
              'item': item,
              'critico': itensCriticos.contains(item),
              'conforme': conformidadePorItem[item] ?? true,
              'observacao': observacoesPorItem[item] ?? '',
            })
        .toList();

    final resp = await SupabaseService.client.rpc('registrar_inspecao_motorista', params: {
      'p_placa': placa,
      'p_data_inspecao': dataInspecao.toIso8601String().split('T').first,
      'p_hodometro': hodometro,
      'p_itens': itens,
    });
    return InspecaoResultado.fromJson(resp as Map<String, dynamic>);
  }
}
