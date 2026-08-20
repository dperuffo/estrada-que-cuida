import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// Saldo = SOMA de todo o ledger (nunca um "saldo mágico" guardado à
// parte — auditável, ver PROPOSTA-FIDELIDADE-MOTORISTA.md seção 3). RLS
// já restringe a leitura só às linhas do próprio motorista, então basta
// somar tudo que vier.
final saldoPontosProvider = FutureProvider.autoDispose<int>((ref) async {
  final rows = await SupabaseService.client
      .from('fidelidade_pontos_ledger')
      .select('pontos');
  int soma = 0;
  for (final r in (rows as List)) {
    soma += (r as Map<String, dynamic>)['pontos'] as int;
  }
  return soma;
});

// Catálogo de níveis do MVP — fixo no código (não muda com frequência,
// conforme a proposta). `min` é o piso; o próximo nível começa onde este
// termina.
class NivelFidelidade {
  final String nome;
  final int min;
  final Color cor;
  final IconData icone;

  const NivelFidelidade({
    required this.nome,
    required this.min,
    required this.cor,
    required this.icone,
  });
}

const List<NivelFidelidade> niveisFidelidade = [
  NivelFidelidade(
    nome: 'Bronze',
    min: 0,
    cor: Color(0xFF8D5B2D),
    icone: Icons.shield_outlined,
  ),
  NivelFidelidade(
    nome: 'Prata',
    min: 10000,
    cor: Color(0xFF9E9E9E),
    icone: Icons.shield,
  ),
  NivelFidelidade(
    nome: 'Ouro',
    min: 30000,
    cor: Color(0xFFC9A227),
    icone: Icons.military_tech_outlined,
  ),
  NivelFidelidade(
    nome: 'Diamante',
    min: 70000,
    cor: Color(0xFF3AAFD9),
    icone: Icons.diamond_outlined,
  ),
  NivelFidelidade(
    nome: 'Herói da Estrada',
    min: 150000,
    cor: Color(0xFF1B7A43),
    icone: Icons.emoji_events,
  ),
];

NivelFidelidade nivelParaSaldo(int saldo) {
  var atual = niveisFidelidade.first;
  for (final n in niveisFidelidade) {
    if (saldo >= n.min) atual = n;
  }
  return atual;
}

/// null quando já está no último nível (Herói da Estrada).
NivelFidelidade? proximoNivel(int saldo) {
  for (final n in niveisFidelidade) {
    if (saldo < n.min) return n;
  }
  return null;
}
