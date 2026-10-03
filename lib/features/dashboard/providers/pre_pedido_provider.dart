import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Pré-Pedido (03/10/2026, pedido do Daniel): quando o cliente habilita o
// parâmetro de uso "Pré-Pedido", o motorista precisa informar o NÚMERO no
// posto (o caixa digita no PDV FNI). A RPC `meus_pre_pedidos_motorista`
// devolve só os Pré-Pedidos ATIVOS do motorista logado (direto pelo
// motorista, ou pela placa do veículo vinculado a ele) em empresas que
// exigem Pré-Pedido — então a lista vem vazia (e o cartão some) quando o
// parâmetro está desligado.
class ParadaPrePedido {
  final int ordem;
  final String? postoNome;
  final double? litros;
  final double? valor;
  final bool atendido;

  const ParadaPrePedido({
    required this.ordem,
    required this.postoNome,
    required this.litros,
    required this.valor,
    required this.atendido,
  });

  factory ParadaPrePedido.fromJson(Map<String, dynamic> j) => ParadaPrePedido(
    ordem: (j['ordem'] as num).toInt(),
    postoNome: j['postoNome'] as String?,
    litros: (j['litros'] as num?)?.toDouble(),
    valor: (j['valor'] as num?)?.toDouble(),
    atendido: j['atendido'] == true,
  );
}

class PrePedidoMotorista {
  final int numero;
  final String? placa;
  final String? empresaNome;
  final List<ParadaPrePedido> paradas;

  const PrePedidoMotorista({
    required this.numero,
    required this.placa,
    required this.empresaNome,
    required this.paradas,
  });

  factory PrePedidoMotorista.fromJson(Map<String, dynamic> j) =>
      PrePedidoMotorista(
        numero: (j['numero'] as num).toInt(),
        placa: j['placa'] as String?,
        empresaNome: j['empresaNome'] as String?,
        paradas: ((j['paradas'] as List?) ?? const [])
            .map((p) => ParadaPrePedido.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

final prePedidosMotoristaProvider =
    FutureProvider.autoDispose<List<PrePedidoMotorista>>((ref) async {
      final resp = await SupabaseService.client.rpc('meus_pre_pedidos_motorista');
      return ((resp as List?) ?? const [])
          .map((e) => PrePedidoMotorista.fromJson(e as Map<String, dynamic>))
          .toList();
    });
