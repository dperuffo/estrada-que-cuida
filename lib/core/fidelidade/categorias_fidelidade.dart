import 'package:flutter/material.dart';

// Espelha src/lib/fidelidadeCategorias.ts (web) — mesmas 7 categorias e
// mesma família de cores (tom ~700 do Tailwind), pra card ficar consistente
// entre o painel web (posto/cliente) e o app do motorista.
class EstiloCategoriaFidelidade {
  final String label;
  final Color cor;

  const EstiloCategoriaFidelidade({required this.label, required this.cor});
}

const Map<String, EstiloCategoriaFidelidade> estilosCategoriaFidelidade = {
  'conveniencia_posto': EstiloCategoriaFidelidade(
    label: 'Conveniência do Posto',
    cor: Color(0xFFB45309),
  ),
  'economia_imediata': EstiloCategoriaFidelidade(
    label: 'Economia Imediata',
    cor: Color(0xFF047857),
  ),
  'marketplace_cabine': EstiloCategoriaFidelidade(
    label: 'Marketplace da Cabine',
    cor: Color(0xFF0369A1),
  ),
  'saude_estrada': EstiloCategoriaFidelidade(
    label: 'Saúde na Estrada',
    cor: Color(0xFFBE123C),
  ),
  'universidade_estrada': EstiloCategoriaFidelidade(
    label: 'Universidade da Estrada',
    cor: Color(0xFF6D28D9),
  ),
  'clube_caminhao': EstiloCategoriaFidelidade(
    label: 'Clube do Caminhão',
    cor: Color(0xFF4338CA),
  ),
  'volte_para_casa': EstiloCategoriaFidelidade(
    label: 'Volte para Casa',
    cor: Color(0xFF0F766E),
  ),
};

const EstiloCategoriaFidelidade estiloCategoriaFidelidadePadrao =
    EstiloCategoriaFidelidade(label: 'Benefício', cor: Color(0xFF047857));

EstiloCategoriaFidelidade estiloCategoria(String categoria) =>
    estilosCategoriaFidelidade[categoria] ?? estiloCategoriaFidelidadePadrao;
