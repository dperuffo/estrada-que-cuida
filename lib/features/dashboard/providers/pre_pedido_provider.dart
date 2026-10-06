import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Pré-Pedido (03/10/2026, pedido do Daniel): quando o cliente habilita o
// parâmetro de uso "Pré-Pedido", o motorista informa SÓ o OTP rotativo (muda
// a cada 30 s) no caixa do posto, que o digita no PDV FNI. A RPC `meus_pre_pedidos_motorista`
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
  final String otp;
  final int segundosRestantes;
  final String? placa;
  final String? empresaNome;
  final List<ParadaPrePedido> paradas;

  const PrePedidoMotorista({
    required this.otp,
    required this.segundosRestantes,
    required this.placa,
    required this.empresaNome,
    required this.paradas,
  });

  factory PrePedidoMotorista.fromJson(Map<String, dynamic> j) =>
      PrePedidoMotorista(
        otp: j['otp'] as String,
        segundosRestantes: (j['segundosRestantes'] as num).toInt(),
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

// 06/10/2026 (pedido do Daniel) — no Pré-Pedido quem inicia e conclui o
// abastecimento é o caixa, no PDV; o motorista só informa o OTP. Por isso o app
// não passa pelas telas de acompanhamento/avaliação da jornada "Abastecer".
// Esta consulta (RPC `meu_abastecimento_pre_pedido_a_avaliar`) descobre o
// abastecimento confirmado via Pré-Pedido, nas últimas 24 h, que o motorista
// ainda não avaliou — a Home então o leva à MESMA tela de avaliação da jornada
// normal (posto, abastecimento, frentista/caixa).
class AbastecimentoAAvaliar {
  final int id;
  final String? postoNome;
  final String? placa;

  const AbastecimentoAAvaliar({required this.id, required this.postoNome, required this.placa});

  factory AbastecimentoAAvaliar.fromJson(Map<String, dynamic> j) => AbastecimentoAAvaliar(
        id: (j['id'] as num).toInt(),
        postoNome: j['postoNome'] as String?,
        placa: j['placa'] as String?,
      );
}

// Consulta a cada 10 s enquanto a Home está aberta (o caixa conclui sem aviso ao
// app). Falha de rede só tenta de novo no próximo ciclo.
final avaliacaoPrePedidoPendenteProvider = StreamProvider.autoDispose<AbastecimentoAAvaliar?>((ref) async* {
  while (true) {
    try {
      final resp = await SupabaseService.client.rpc('meu_abastecimento_pre_pedido_a_avaliar');
      yield resp == null ? null : AbastecimentoAAvaliar.fromJson(resp as Map<String, dynamic>);
    } catch (_) {
      // best-effort
    }
    await Future.delayed(const Duration(seconds: 10));
  }
});

// Abastecimentos que o usuário dispensou nesta sessão (botão "Agora não").
final avaliacoesDispensadasProvider = StateProvider<Set<int>>((ref) => <int>{});
