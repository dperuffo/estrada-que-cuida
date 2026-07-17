import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Catálogo de resgate — v1 simulado (sem parceiros reais, sem pagamento/
// entrega de verdade), gerido pelo admin no painel web. 6 categorias
// cobrindo os pilares do programa que não têm parceiro real ainda (ver
// PROPOSTA-FIDELIDADE-MOTORISTA.md, roadmap).
class CategoriaCatalogo {
  final String codigo;
  final String label;
  final IconData icone;

  const CategoriaCatalogo({required this.codigo, required this.label, required this.icone});
}

const List<CategoriaCatalogo> categoriasCatalogo = [
  CategoriaCatalogo(codigo: 'economia_imediata', label: 'Economia Imediata', icone: Icons.savings_outlined),
  CategoriaCatalogo(codigo: 'marketplace_cabine', label: 'Marketplace da Cabine', icone: Icons.storefront_outlined),
  CategoriaCatalogo(codigo: 'saude_estrada', label: 'Saúde na Estrada', icone: Icons.favorite_outline),
  CategoriaCatalogo(codigo: 'universidade_estrada', label: 'Universidade da Estrada', icone: Icons.school_outlined),
  CategoriaCatalogo(codigo: 'clube_caminhao', label: 'Clube do Caminhão', icone: Icons.groups_outlined),
  CategoriaCatalogo(codigo: 'volte_para_casa', label: 'Volte para Casa', icone: Icons.home_outlined),
];

class ItemCatalogo {
  final String id;
  final String categoria;
  final String titulo;
  final String? descricao;
  final String? parceiroNome;
  final int pontosNecessarios;

  ItemCatalogo({
    required this.id,
    required this.categoria,
    required this.titulo,
    this.descricao,
    this.parceiroNome,
    required this.pontosNecessarios,
  });

  factory ItemCatalogo.fromJson(Map<String, dynamic> json) {
    return ItemCatalogo(
      id: json['id'] as String,
      categoria: json['categoria'] as String,
      titulo: json['titulo'] as String,
      descricao: json['descricao'] as String?,
      parceiroNome: json['parceiro_nome'] as String?,
      pontosNecessarios: json['pontos_necessarios'] as int,
    );
  }
}

/// `categoria` null = todas.
final catalogoProvider = FutureProvider.autoDispose.family<List<ItemCatalogo>, String?>((ref, categoria) async {
  var query = SupabaseService.client
      .from('fidelidade_catalogo_itens')
      .select('id, categoria, titulo, descricao, parceiro_nome, pontos_necessarios')
      .eq('ativo', true);
  if (categoria != null) query = query.eq('categoria', categoria);
  final rows = await query.order('pontos_necessarios');
  return (rows as List).map((e) => ItemCatalogo.fromJson(e as Map<String, dynamic>)).toList();
});

class ResgateResultado {
  final String status;
  final int? saldo;
  final int? necessario;

  ResgateResultado({required this.status, this.saldo, this.necessario});

  factory ResgateResultado.fromJson(Map<String, dynamic> json) {
    return ResgateResultado(
      status: json['status'] as String,
      saldo: json['saldo'] as int?,
      necessario: json['necessario'] as int?,
    );
  }
}

class CatalogoService {
  static Future<ResgateResultado> resgatar({required String itemId, String? dependenteId}) async {
    final resp = await SupabaseService.client.rpc('resgatar_item_catalogo', params: {
      'p_item_id': itemId,
      'p_dependente_id': dependenteId,
    });
    return ResgateResultado.fromJson(resp as Map<String, dynamic>);
  }
}

class Resgate {
  final String id;
  final String categoria;
  final String titulo;
  final int pontosGastos;
  final String status;
  final DateTime solicitadoEm;

  Resgate({
    required this.id,
    required this.categoria,
    required this.titulo,
    required this.pontosGastos,
    required this.status,
    required this.solicitadoEm,
  });

  factory Resgate.fromJson(Map<String, dynamic> json) {
    return Resgate(
      id: json['id'] as String,
      categoria: json['categoria'] as String,
      titulo: json['titulo'] as String,
      pontosGastos: json['pontos_gastos'] as int,
      status: json['status'] as String,
      solicitadoEm: DateTime.parse(json['solicitado_em'] as String),
    );
  }
}

final meusResgatesProvider = FutureProvider.autoDispose<List<Resgate>>((ref) async {
  final rows = await SupabaseService.client
      .from('fidelidade_resgates')
      .select('id, categoria, titulo, pontos_gastos, status, solicitado_em')
      .order('solicitado_em', ascending: false);
  return (rows as List).map((e) => Resgate.fromJson(e as Map<String, dynamic>)).toList();
});
