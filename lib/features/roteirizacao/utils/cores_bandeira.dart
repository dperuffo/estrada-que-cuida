import 'package:flutter/material.dart';

// Port fiel de src/lib/coresBandeira.ts (Gestão de Frotas) — mesma regra de
// cor pedida pelo Daniel: Ipiranga = amarelo, Shell/Raízen = vermelho,
// BR/Petrobras/Vibra = verde. Demais bandeiras caem numa paleta fixa por
// hash estável do nome, então a mesma bandeira sempre vira a mesma cor
// (igual no painel web e aqui no PWA motorista).

enum CorMarcador {
  amarelo,
  vermelho,
  verde,
  azul,
  roxo,
  rosa,
  marrom,
  ciano,
  laranja,
  cinza,
}

const Map<CorMarcador, Color> coresHexBandeira = {
  CorMarcador.amarelo: Color(0xFFEAB308),
  CorMarcador.vermelho: Color(0xFFDC2626),
  CorMarcador.verde: Color(0xFF16A34A),
  CorMarcador.azul: Color(0xFF2563EB),
  CorMarcador.roxo: Color(0xFF7C3AED),
  CorMarcador.rosa: Color(0xFFDB2777),
  CorMarcador.marrom: Color(0xFF92400E),
  CorMarcador.ciano: Color(0xFF0891B2),
  CorMarcador.laranja: Color(0xFFEA580C),
  CorMarcador.cinza: Color(0xFF64748B),
};

const List<CorMarcador> _paletaOutras = [
  CorMarcador.azul,
  CorMarcador.roxo,
  CorMarcador.rosa,
  CorMarcador.marrom,
  CorMarcador.ciano,
  CorMarcador.laranja,
];

/// Maiúsculas, sem acento, espaços colapsados — mesma normalização usada no
/// web (normalizarTexto em utils.ts) pra comparar nomes de bandeira/estado/
/// município vindos de fontes com capitalização inconsistente.
String normalizarTexto(String? valor) {
  var s = (valor ?? '').toUpperCase().trim();
  const comAcento = 'ÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÇÑ';
  const semAcento = 'AAAAAAEEEEIIIIOOOOOUUUUCN';
  for (var i = 0; i < comAcento.length; i++) {
    s = s.replaceAll(comAcento[i], semAcento[i]);
  }
  return s.replaceAll(RegExp(r'\s+'), ' ');
}

/// Resolve a cor do marcador a partir da bandeira/distribuidora do posto.
CorMarcador corPorBandeira(String? bandeira) {
  final nome = normalizarTexto(bandeira);
  if (nome.isEmpty) return CorMarcador.cinza;

  if (nome.contains('IPIRANGA')) return CorMarcador.amarelo;
  if (nome.contains('SHELL') || nome.contains('RAIZEN'))
    return CorMarcador.vermelho;
  if (nome.contains('PETROBRAS') ||
      nome.contains('VIBRA') ||
      RegExp(r'\bBR\b').hasMatch(nome)) {
    return CorMarcador.verde;
  }

  var hash = 0;
  for (final codeUnit in nome.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0xFFFFFFFF;
  }
  return _paletaOutras[hash % _paletaOutras.length];
}

/// Rótulo em Title Case pra exibição — evita "Ale" e "ALE" aparecerem como
/// bandeiras diferentes na legenda só por causa de capitalização da fonte.
String formatarLabelBandeira(String? bandeira) {
  final texto = (bandeira ?? '').trim();
  if (texto.isEmpty) return 'Sem bandeira';
  return texto
      .toLowerCase()
      .split(' ')
      .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
      .join(' ');
}
