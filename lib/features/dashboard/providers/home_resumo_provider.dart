import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Fase Home-Motorista-Saldos (pedido do Daniel, 19/07): resumo pra Home
// com dado do cliente (empresa/classificação Próprio-Agregado-Terceiro),
// saldo de cota do veículo, saldo de frete ativo e consumo do veículo —
// tudo calculado no banco pela RPC `motorista_home_resumo` (ver migração
// rpc_motorista_home_resumo), que já resolve a prioridade frete > cota
// (ver alocar_abastecimento_saldo). Aqui só desserializa.

class SaldoCota {
  final String tipo; // 'Valor' | 'Volume'
  final String periodicidade; // Abastecimento | Semana | Quinzena | Mes
  final double limite;
  final double consumido;
  final double saldo;

  const SaldoCota({
    required this.tipo,
    required this.periodicidade,
    required this.limite,
    required this.consumido,
    required this.saldo,
  });

  bool get emVolume => tipo == 'Volume';

  factory SaldoCota.fromJson(Map<String, dynamic> json) => SaldoCota(
    tipo: json['tipo'] as String,
    periodicidade: json['periodicidade'] as String,
    limite: (json['limite'] as num).toDouble(),
    consumido: (json['consumido'] as num).toDouble(),
    saldo: (json['saldo'] as num).toDouble(),
  );
}

class SaldoFrete {
  final String freteId;
  final String titulo;
  final String tipo; // 'Valor' | 'Volume'
  final double alocado;
  final double consumido;
  final double saldo;

  const SaldoFrete({
    required this.freteId,
    required this.titulo,
    required this.tipo,
    required this.alocado,
    required this.consumido,
    required this.saldo,
  });

  bool get emVolume => tipo == 'Volume';

  factory SaldoFrete.fromJson(Map<String, dynamic> json) => SaldoFrete(
    freteId: json['frete_id'] as String,
    titulo: json['titulo'] as String,
    tipo: json['tipo'] as String,
    alocado: (json['alocado'] as num).toDouble(),
    consumido: (json['consumido'] as num).toDouble(),
    saldo: (json['saldo'] as num).toDouble(),
  );
}

class ConsumoHoje {
  final double litros;
  final double valor;

  const ConsumoHoje({required this.litros, required this.valor});

  factory ConsumoHoje.fromJson(Map<String, dynamic> json) => ConsumoHoje(
    litros: (json['litros'] as num).toDouble(),
    valor: (json['valor'] as num).toDouble(),
  );
}

class MediasConsumo {
  final double? kmL;
  final double? valorPorLitro;

  const MediasConsumo({this.kmL, this.valorPorLitro});

  factory MediasConsumo.fromJson(Map<String, dynamic> json) => MediasConsumo(
    kmL: (json['km_l'] as num?)?.toDouble(),
    valorPorLitro: (json['valor_por_litro'] as num?)?.toDouble(),
  );
}

class PontoSerieDia {
  final DateTime dia;
  final double litros;
  final double valor;

  const PontoSerieDia({
    required this.dia,
    required this.litros,
    required this.valor,
  });

  factory PontoSerieDia.fromJson(Map<String, dynamic> json) => PontoSerieDia(
    dia: DateTime.parse(json['dia'] as String),
    litros: (json['litros'] as num).toDouble(),
    valor: (json['valor'] as num).toDouble(),
  );
}

class HomeResumo {
  final String status;
  final String? empresaNome;
  final String? classificacao;
  final String? placa;
  final SaldoCota? cota;
  final SaldoFrete? frete;
  final ConsumoHoje hoje;
  final MediasConsumo medias;
  final List<PontoSerieDia> serie7Dias;

  const HomeResumo({
    required this.status,
    this.empresaNome,
    this.classificacao,
    this.placa,
    this.cota,
    this.frete,
    required this.hoje,
    required this.medias,
    required this.serie7Dias,
  });

  factory HomeResumo.fromJson(Map<String, dynamic> json) => HomeResumo(
    status: json['status'] as String,
    empresaNome: json['empresa_nome'] as String?,
    classificacao: json['classificacao'] as String?,
    placa: json['placa'] as String?,
    cota: json['cota'] != null
        ? SaldoCota.fromJson(json['cota'] as Map<String, dynamic>)
        : null,
    frete: json['frete'] != null
        ? SaldoFrete.fromJson(json['frete'] as Map<String, dynamic>)
        : null,
    hoje: json['hoje'] != null
        ? ConsumoHoje.fromJson(json['hoje'] as Map<String, dynamic>)
        : const ConsumoHoje(litros: 0, valor: 0),
    medias: json['medias'] != null
        ? MediasConsumo.fromJson(json['medias'] as Map<String, dynamic>)
        : const MediasConsumo(),
    serie7Dias: (json['serie_7dias'] as List? ?? [])
        .map((e) => PontoSerieDia.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

final homeResumoProvider = FutureProvider.autoDispose<HomeResumo?>((ref) async {
  final resp = await SupabaseService.client.rpc('motorista_home_resumo');
  if (resp == null) return null;
  return HomeResumo.fromJson(resp as Map<String, dynamic>);
});
