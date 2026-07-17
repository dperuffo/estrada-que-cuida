import 'dart:math' as math;

// Port fiel de src/lib/roteirizacaoScore.ts e src/lib/roteirizacaoAlgoritmo.ts
// (Gestão de Frotas) — pedido do Daniel: "a ordem de sugestao de
// abastecimentos ja esta construida na aplicacao web, é só aproveitar".
// Mesmas fórmulas e constantes do painel web, pra dar o mesmo resultado
// (dado o mesmo conjunto de candidatos) nas duas telas.

class ScorePosto {
  final double score; // 0-100
  final String grade; // A/B/C/D

  const ScorePosto({required this.score, required this.grade});
}

/// Score composto do posto — aqui no PWA motorista só usamos postos da base
/// pública ANP (sem os 10 campos de serviço que só existem em postos_gf),
/// então `servicosAtivos` sempre entra como 0 — mesmo comportamento que o
/// painel web já usa pra postos vindos da base ANP (ver montarPostosAnp em
/// actions.ts).
ScorePosto calcularScorePosto({
  double? precoPosto,
  double? precoReferenciaAnp,
  required int servicosAtivos,
  required int servicosTotal,
}) {
  double scorePreco = 50;
  if (precoReferenciaAnp != null && precoReferenciaAnp > 0 && precoPosto != null && precoPosto > 0) {
    final diff = (precoPosto - precoReferenciaAnp) / precoReferenciaAnp;
    scorePreco = (50 - diff * 500).clamp(0, 100);
  }

  double scoreServicos = 0;
  if (servicosTotal > 0) {
    scoreServicos = ((servicosAtivos / servicosTotal) * 100).clamp(0, 100);
  }

  const scoreDistancia = 50.0; // sem ponto de referência único nesta tela

  final score = 0.5 * scorePreco + 0.3 * scoreServicos + 0.2 * scoreDistancia;
  final grade = score >= 75 ? 'A' : (score >= 55 ? 'B' : (score >= 35 ? 'C' : 'D'));

  return ScorePosto(score: (score * 10).round() / 10, grade: grade);
}

class CandidatoAbastecimento {
  final String cnpj;
  final double km; // posição do posto na rota, a partir da origem (km)
  final double desvioKm; // distância do posto até a rota mais próxima (km)
  final double preco;
  final String grade; // A/B/C/D
  final String label;
  final double lat;
  final double lon;
  final String? bandeira;
  final String? uf;
  final String? municipio;

  const CandidatoAbastecimento({
    required this.cnpj,
    required this.km,
    required this.desvioKm,
    required this.preco,
    required this.grade,
    required this.label,
    required this.lat,
    required this.lon,
    this.bandeira,
    this.uf,
    this.municipio,
  });
}

class ParadaSugerida {
  final CandidatoAbastecimento posto;
  final String motivo; // otimizado / estrategico / emergencia
  final double fuelChegadaL;
  final double pctChegada;
  final int litrosSugeridos;
  final double custoAbastecimento;
  final double fuelAposL;
  final double pctApos;

  const ParadaSugerida({
    required this.posto,
    required this.motivo,
    required this.fuelChegadaL,
    required this.pctChegada,
    required this.litrosSugeridos,
    required this.custoAbastecimento,
    required this.fuelAposL,
    required this.pctApos,
  });
}

class PesosOtimizacao {
  final double preco;
  final double score;
  final double desvio;

  const PesosOtimizacao({required this.preco, required this.score, required this.desvio});
}

const Map<String, double> _gradePeso = {'A': 1.0, 'B': 0.75, 'C': 0.5, 'D': 0.25};

const double _nivelMinimoPct = 0.25; // nunca deixa o tanque abaixo de 25%
const double _pctBaixo = 0.65;
const double _vantagemPrecoMinima = 0.03;
const double _vantagemMetricaMinima = 1.05;
const int _litrosMinimos = 5;

/// Motor de otimização de abastecimento — decide ONDE parar e QUANTO
/// abastecer em cada parada, com um algoritmo guloso com "olhar à frente"
/// (look-ahead). Port fiel de otimizarAbastecimento() em
/// roteirizacaoAlgoritmo.ts.
List<ParadaSugerida> otimizarAbastecimento({
  required List<CandidatoAbastecimento> candidatos,
  required double capacidadeTanqueL,
  required double autonomiaKmPorL,
  required double distanciaTotalRotaKm,
  required PesosOtimizacao pesos,
  String fillMode = 'normal', // 'normal' | 'minimo'
  double? combustivelInicialL,
  int maxParadas = 30,
}) {
  final rcap = capacidadeTanqueL;
  final raut = autonomiaKmPorL;
  final rd = distanciaTotalRotaKm;

  if (candidatos.isEmpty || raut <= 0 || rcap <= 0) return [];

  final rmin = rcap * _nivelMinimoPct;
  final alcanceEfetivoKm = (rcap - rmin) * raut;

  final precos = candidatos.map((c) => c.preco).where((p) => p.isFinite).toList();
  final pmin = precos.isEmpty ? 0.0 : precos.reduce(math.min);
  final pmax = precos.isEmpty ? 1.0 : precos.reduce(math.max);

  double metrica(CandidatoAbastecimento c) {
    final p = 1 - (c.preco - pmin) / math.max(pmax - pmin, 0.01);
    final g = _gradePeso[c.grade] ?? 0.25;
    final d = 1 - math.min(c.desvioKm / 5, 1);
    return pesos.preco * p + pesos.score * g + pesos.desvio * d;
  }

  final paradas = <ParadaSugerida>[];
  var pos = 0.0;
  var fuel = combustivelInicialL ?? rcap;
  final vistos = <String>{};
  double? ultimoPreco;

  for (var iter = 0; iter < maxParadas; iter++) {
    if (pos >= rd) break;

    final podeIr = (fuel - rmin) * raut;
    final alcancaSem = pos + podeIr;
    if (alcancaSem >= rd) break; // chega ao destino sem precisar parar

    final janela = candidatos.where((c) => pos < c.km && c.km <= alcancaSem && !vistos.contains(c.cnpj)).toList();
    final janelaEstendida = candidatos
        .where((c) => alcancaSem < c.km && c.km <= pos + alcanceEfetivoKm * 1.85 && !vistos.contains(c.cnpj))
        .toList();

    CandidatoAbastecimento best;
    String motivo;
    double? fillAlvoKm;

    if (janela.isEmpty) {
      final alemDoAlcance = candidatos.where((c) => c.km > pos && !vistos.contains(c.cnpj)).toList()
        ..sort((a, b) => a.km.compareTo(b.km));
      if (alemDoAlcance.isEmpty) break; // sem tanque para chegar em nenhum posto restante
      best = alemDoAlcance.first;
      motivo = 'emergencia';
    } else {
      final bestObrigatorio = janela.reduce((m, c) => metrica(c) > metrica(m) ? c : m);
      if (janelaEstendida.isNotEmpty) {
        final bestEstendido = janelaEstendida.reduce((m, c) => metrica(c) > metrica(m) ? c : m);
        if (metrica(bestEstendido) > metrica(bestObrigatorio) * _vantagemMetricaMinima &&
            bestEstendido.preco < bestObrigatorio.preco * (1 - _vantagemPrecoMinima)) {
          fillAlvoKm = bestEstendido.km;
        }
      }
      best = bestObrigatorio;
      motivo = fillAlvoKm != null ? 'estrategico' : 'otimizado';
    }

    final kmAte = best.km - pos;
    final fuelChegada = math.max(0.0, fuel - kmAte / raut);
    final pctChegada = (fuelChegada / rcap) * 100;

    if (motivo != 'emergencia' &&
        pctChegada >= _pctBaixo * 100 &&
        ultimoPreco != null &&
        best.preco >= ultimoPreco * (1 - _vantagemPrecoMinima) &&
        fillAlvoKm == null) {
      pos = best.km;
      fuel = fuelChegada;
      vistos.add(best.cnpj);
      continue;
    }

    final distRestante = rd - best.km;
    double litrosNecessarios;

    if (fillMode == 'minimo') {
      final proximosOrdenados = candidatos.where((c) => c.km > best.km && !vistos.contains(c.cnpj)).toList()
        ..sort((a, b) => a.km.compareTo(b.km));
      if (proximosOrdenados.isNotEmpty) {
        final distProx = proximosOrdenados.first.km - best.km;
        litrosNecessarios = (distProx / raut) * 1.1 + rmin - fuelChegada;
      } else {
        litrosNecessarios = (distRestante / raut) * 1.15 + rmin - fuelChegada;
      }
    } else if (fillAlvoKm != null) {
      final distAlvo = fillAlvoKm - best.km;
      litrosNecessarios = (distAlvo / raut) * 1.1 + rmin - fuelChegada;
    } else if (distRestante <= alcanceEfetivoKm) {
      litrosNecessarios = (distRestante / raut) * 1.15 + rmin - fuelChegada;
    } else {
      litrosNecessarios = rcap - fuelChegada;
    }

    var litrosFill = math.max(0.0, litrosNecessarios);
    litrosFill = math.min(litrosFill, rcap - fuelChegada);
    litrosFill = litrosFill.ceilToDouble();

    if (litrosFill < _litrosMinimos) {
      pos = best.km;
      fuel = fuelChegada;
      vistos.add(best.cnpj);
      continue;
    }

    final fuelApos = math.min(fuelChegada + litrosFill, rcap);
    final pctApos = (fuelApos / rcap) * 100;
    final custoAbastecimento = (litrosFill * best.preco * 100).round() / 100;

    paradas.add(ParadaSugerida(
      posto: best,
      motivo: motivo,
      fuelChegadaL: (fuelChegada * 10).round() / 10,
      pctChegada: (pctChegada * 10).round() / 10,
      litrosSugeridos: litrosFill.round(),
      custoAbastecimento: custoAbastecimento,
      fuelAposL: (fuelApos * 10).round() / 10,
      pctApos: (pctApos * 10).round() / 10,
    ));

    vistos.add(best.cnpj);
    ultimoPreco = best.preco;
    fuel = fuelApos;
    pos = best.km;
  }

  return paradas;
}
