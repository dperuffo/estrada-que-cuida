import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../../../core/services/supabase_service.dart';
import '../utils/cores_bandeira.dart';
import '../utils/roteirizacao_algoritmo.dart';
import '../utils/roteirizacao_constantes.dart';

// Roteirização self-service do motorista (Fase 17/07) — mesmos serviços
// públicos e gratuitos usados no planejador do painel web
// (src/lib/geo.ts): Nominatim pra geocodificação e OSRM público pra
// cálculo de rota. Aqui chamados direto do app (sem depender do servidor
// Next.js), com os mesmos parâmetros/servidores pra manter resultado
// consistente entre as duas telas.
//
// Fase 17/07-3 — pedido do Daniel: cores de marcador por bandeira iguais ao
// painel web, filtro de combustível, campo de combustível já no tanque e
// preço/custo sugeridos por parada. A ordem de sugestão de abastecimentos
// reaproveita o mesmo motor do painel web (otimizarAbastecimento em
// roteirizacao_algoritmo.dart, port fiel de roteirizacaoAlgoritmo.ts) — só a
// origem dos candidatos muda: aqui só temos a base pública ANP (anp_postos +
// anp_precos_referencia), já que o motorista não está ligado a uma carteira
// de postos própria (postos_gf) como o painel web.

class PontoRota {
  final double lat;
  final double lon;

  const PontoRota({required this.lat, required this.lon});
}

class SugestaoLocal {
  final String label;
  final double lat;
  final double lon;

  const SugestaoLocal({required this.label, required this.lat, required this.lon});
}

/// Busca de local por texto livre via Nominatim (OpenStreetMap) — mesmo
/// serviço e mesmos parâmetros do painel web (geocodificar() em geo.ts).
Future<List<SugestaoLocal>> geocodificar(String texto) async {
  final termo = texto.trim();
  if (termo.length < 3) return [];

  final url = Uri.https('nominatim.openstreetmap.org', '/search', {
    'q': '$termo, Brasil',
    'format': 'json',
    'limit': '6',
    'countrycodes': 'br',
    'addressdetails': '1',
  });

  try {
    final resp = await http
        .get(url, headers: {'User-Agent': 'EstradaQueCuida-Flutter/1.0 (contato: d.peruffo@gmail.com)'})
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final itens = jsonDecode(resp.body) as List;
    final vistos = <String>{};
    final opcoes = <SugestaoLocal>[];
    for (final item in itens) {
      final mapa = item as Map<String, dynamic>;
      final addr = (mapa['address'] as Map<String, dynamic>?) ?? {};
      final cidade = (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['municipality'] ?? addr['county'] ?? '')
          .toString();
      final estado = (addr['state'] ?? '').toString();
      final label = cidade.isNotEmpty && estado.isNotEmpty
          ? '$cidade – $estado'
          : (estado.isNotEmpty
              ? estado
              : (mapa['display_name']?.toString().split(', ').take(2).join(', ') ?? termo));
      if (vistos.add(label)) {
        opcoes.add(SugestaoLocal(
          label: label,
          lat: double.parse(mapa['lat'] as String),
          lon: double.parse(mapa['lon'] as String),
        ));
      }
    }
    return opcoes;
  } catch (_) {
    return [];
  }
}

class VeiculoRoteirizacao {
  final String placa;
  final String? marca;
  final String? modelo;
  final double tanque;
  final double autonomia;
  final bool vinculoAtivo;
  // Fase Fretes-Compatibilidade-Veiculo (19/07) — 'Leve' | 'Pesado', vindo
  // do cadastro do veículo (cadastro_veiculos.tipo). Usado pra pré-filtrar
  // a lista de fretes de mercado aberto pelo que o motorista realmente
  // pode aceitar (a trava de verdade mora no banco, ver
  // compativel_veiculo_frete).
  final String? tipo;

  const VeiculoRoteirizacao({
    required this.placa,
    this.marca,
    this.modelo,
    required this.tanque,
    required this.autonomia,
    required this.vinculoAtivo,
    this.tipo,
  });

  /// Autonomia total do tanque cheio, em km (tanque em litros × autonomia
  /// em km/l, ambos vindos do cadastro do veículo).
  double get autonomiaKm => tanque * autonomia;
}

/// Veículos do motorista pra roteirização inteligente (Fase 17/07-2) —
/// pedido do Daniel: "para a placa, o usuario deve selecionar a sua placa
/// na lista ou se tiver vinculo de placa e motorista, respeitar o vinculo,
/// capacidade do tanque é do cadastro da placa". Respeita o vínculo ativo
/// (parametros_vinculo_motorista_veiculo) quando existe; senão lista os
/// veículos ativos da empresa do motorista pra ele escolher. Tanque e
/// autonomia sempre vêm do cadastro do veículo, nunca digitados.
Future<List<VeiculoRoteirizacao>> buscarMeusVeiculos() async {
  try {
    final linhas = await SupabaseService.client.rpc('meus_veiculos_roteirizacao');
    return (linhas as List).map((l) {
      final mapa = l as Map<String, dynamic>;
      return VeiculoRoteirizacao(
        placa: mapa['placa'] as String,
        marca: mapa['marca'] as String?,
        modelo: mapa['modelo'] as String?,
        tanque: (mapa['tanque'] as num?)?.toDouble() ?? 0,
        autonomia: (mapa['autonomia'] as num?)?.toDouble() ?? 0,
        vinculoAtivo: mapa['vinculo_ativo'] as bool? ?? false,
        tipo: mapa['tipo'] as String?,
      );
    }).toList();
  } catch (_) {
    return [];
  }
}

/// Fase Fretes-Dados-Completos — pedido do Daniel (inspirado em telas de
/// outras plataformas de frete): calculadora de lucro pro motorista, "antes
/// de pegar a estrada, calcule seus custos e veja o quanto você vai
/// lucrar". Preço médio do combustível pelo NOME do estado (não a sigla) —
/// os endereços de frete guardam "cidade/estado" por extenso, então evita
/// precisar de outro de-para: normaliza o texto e casa direto com os
/// valores de `ufParaEstadoAnp` (já em maiúsculas sem acento). Cai pro nível
/// Brasil se não achar preço daquele estado especificamente.
Future<double?> buscarPrecoMedioCombustivelPorEstado(String categoriaAnp, String? nomeEstado) async {
  try {
    if (nomeEstado != null && nomeEstado.trim().isNotEmpty) {
      final estadoNormalizado = normalizarTexto(nomeEstado).toUpperCase();
      final estadoValido = ufParaEstadoAnp.values.contains(estadoNormalizado);
      if (estadoValido) {
        final linha = await SupabaseService.client
            .from('anp_precos_referencia')
            .select('preco_medio')
            .eq('nivel', 'estado')
            .eq('produto', categoriaAnp)
            .eq('estado', estadoNormalizado)
            .order('data_final', ascending: false)
            .limit(1)
            .maybeSingle();
        final preco = (linha?['preco_medio'] as num?)?.toDouble();
        if (preco != null) return preco;
      }
    }
    final linhaBrasil = await SupabaseService.client
        .from('anp_precos_referencia')
        .select('preco_medio')
        .eq('nivel', 'brasil')
        .eq('produto', categoriaAnp)
        .order('data_final', ascending: false)
        .limit(1)
        .maybeSingle();
    return (linhaBrasil?['preco_medio'] as num?)?.toDouble();
  } catch (_) {
    return null;
  }
}

/// Registra o evento "rota_calculada" pra alimentar a missão de gamificação
/// correspondente (fidelidade_missoes.tipo_metrica = 'rotas_calculadas') —
/// silencioso de propósito: uma falha aqui não pode atrapalhar o motorista
/// de ver o resultado da rota que ele acabou de calcular.
Future<void> registrarRotaCalculada() async {
  try {
    final motoristaId = await SupabaseService.client
        .from('motoristas')
        .select('id')
        .eq('auth_user_id', SupabaseService.client.auth.currentUser!.id)
        .maybeSingle();
    final id = motoristaId?['id'] as String?;
    if (id == null) return;
    await SupabaseService.client
        .from('fidelidade_eventos_engajamento')
        .insert({'motorista_id': id, 'tipo_evento': 'rota_calculada'});
  } catch (_) {
    // silencioso — não impacta o fluxo principal da roteirização
  }
}

class ResultadoRota {
  final List<PontoRota> coordenadas;
  final double distanciaKm;
  final double duracaoMin;

  const ResultadoRota({required this.coordenadas, required this.distanciaKm, required this.duracaoMin});
}

const _servidoresOsrm = [
  'https://router.project-osrm.org/route/v1/driving',
  'https://routing.openstreetmap.de/routed-car/route/v1/driving',
];

/// Calcula a rota rodoviária via OSRM público — mesmos servidores (tentados
/// em sequência) do painel web (calcularRotaOsrm() em geo.ts).
Future<ResultadoRota?> calcularRota(PontoRota origem, PontoRota destino) async {
  final coordsStr = '${origem.lon},${origem.lat};${destino.lon},${destino.lat}';

  for (final servidor in _servidoresOsrm) {
    try {
      final url = Uri.parse('$servidor/$coordsStr?overview=full&geometries=geojson');
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) continue;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final rotas = json['routes'] as List?;
      if (rotas == null || rotas.isEmpty) continue;
      final rota = rotas.first as Map<String, dynamic>;
      final geometria = rota['geometry'] as Map<String, dynamic>;
      final coords = (geometria['coordinates'] as List)
          .map((c) => PontoRota(lat: (c as List)[1] as double, lon: c[0] as double))
          .toList();
      return ResultadoRota(
        coordenadas: coords,
        distanciaKm: (rota['distance'] as num) / 1000,
        duracaoMin: (rota['duration'] as num) / 60,
      );
    } catch (_) {
      continue;
    }
  }
  return null;
}

double _haversineKm(PontoRota a, PontoRota b) {
  const raioTerraKm = 6371.0;
  final dLat = (b.lat - a.lat) * math.pi / 180;
  final dLon = (b.lon - a.lon) * math.pi / 180;
  final lat1 = a.lat * math.pi / 180;
  final lat2 = b.lat * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return raioTerraKm * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

PontoRota _projetarPontoNoSegmento(PontoRota ponto, PontoRota a, PontoRota b) {
  final dx = b.lon - a.lon;
  final dy = b.lat - a.lat;
  final comprimento2 = dx * dx + dy * dy;
  if (comprimento2 == 0) return a;
  var t = ((ponto.lon - a.lon) * dx + (ponto.lat - a.lat) * dy) / comprimento2;
  t = t.clamp(0.0, 1.0);
  return PontoRota(lat: a.lat + t * dy, lon: a.lon + t * dx);
}

List<double> _distanciasAcumuladas(List<PontoRota> rota) {
  final acc = <double>[0];
  for (var i = 1; i < rota.length; i++) {
    acc.add(acc[i - 1] + _haversineKm(rota[i - 1], rota[i]));
  }
  return acc;
}

class _PosicaoNaRota {
  final double km;
  final double desvioKm;
  const _PosicaoNaRota({required this.km, required this.desvioKm});
}

/// Km percorrido (a partir da origem) e desvio (km) do ponto até o trecho
/// mais próximo da rota — usado pra saber "em que km da viagem" cada posto
/// candidato fica e se ele está perto o bastante do trajeto. Port fiel de
/// posicaoNaRotaKm() em geo.ts.
_PosicaoNaRota _posicaoNaRotaKm(PontoRota ponto, List<PontoRota> rota, List<double> distanciasAcumuladasKm) {
  if (rota.isEmpty) return const _PosicaoNaRota(km: 0, desvioKm: double.infinity);
  var melhorDist = double.infinity;
  var melhorKm = 0.0;
  for (var i = 0; i < rota.length - 1; i++) {
    final a = rota[i];
    final b = rota[i + 1];
    final proj = _projetarPontoNoSegmento(ponto, a, b);
    final d = _haversineKm(ponto, proj);
    if (d < melhorDist) {
      melhorDist = d;
      final distSegmento = _haversineKm(a, b);
      final distAteProjecao = _haversineKm(a, proj);
      final fracao = distSegmento > 0 ? distAteProjecao / distSegmento : 0;
      melhorKm = distanciasAcumuladasKm[i] + fracao * (distanciasAcumuladasKm[i + 1] - distanciasAcumuladasKm[i]);
    }
  }
  return _PosicaoNaRota(km: melhorKm, desvioKm: melhorDist);
}

class _BoundingBox {
  final double minLat, maxLat, minLon, maxLon;
  const _BoundingBox({required this.minLat, required this.maxLat, required this.minLon, required this.maxLon});
}

/// Divide a rota em pedaços de até `passoKm` (capado a `maxSegmentos`) e
/// devolve uma caixa por pedaço — em vez de uma caixa única cobrindo a rota
/// inteira, que numa viagem longa vira um retângulo enorme e faz a consulta
/// (com .limit) descartar candidatos reais perto do corredor. Port fiel de
/// construirBoundingBoxesDaRota() em geo.ts.
List<_BoundingBox> _construirBoundingBoxes(
  List<PontoRota> rota,
  List<double> distanciasAcumuladasKm,
  double margemGraus, {
  double passoKm = 150,
  int maxSegmentos = 20,
}) {
  if (rota.isEmpty) return [];
  final totalKm = distanciasAcumuladasKm.last;
  final passoEfetivoKm = math.max(passoKm, totalKm / maxSegmentos);

  final boxes = <_BoundingBox>[];
  var inicioIdx = 0;
  var inicioKm = 0.0;
  for (var i = 1; i < rota.length; i++) {
    final ultimoPonto = i == rota.length - 1;
    if (distanciasAcumuladasKm[i] - inicioKm >= passoEfetivoKm || ultimoPonto) {
      final fatia = rota.sublist(inicioIdx, i + 1);
      final lats = fatia.map((p) => p.lat);
      final lons = fatia.map((p) => p.lon);
      boxes.add(_BoundingBox(
        minLat: lats.reduce(math.min) - margemGraus,
        maxLat: lats.reduce(math.max) + margemGraus,
        minLon: lons.reduce(math.min) - margemGraus,
        maxLon: lons.reduce(math.max) + margemGraus,
      ));
      inicioIdx = i;
      inicioKm = distanciasAcumuladasKm[i];
    }
  }
  return boxes;
}

/// Busca os postos ANP (base pública nacional) no corredor da rota (até
/// `raioCorredorKm` de desvio), resolve o preço do combustível escolhido pela
/// cascata oficial ANP (município → estado → Brasil) e monta os candidatos
/// pro algoritmo de otimização. Sem preço registrado pra esse combustível
/// nessa região, o posto fica de fora (não dá pra decidir se compensa parar
/// ali sem saber o preço).
Future<List<CandidatoAbastecimento>> buscarCandidatosAbastecimento({
  required List<PontoRota> coordenadas,
  required String combustivel,
  double raioCorredorKm = 5,
}) async {
  final categoria = produtoParaCategoriaAnp[combustivel];
  if (categoria == null) return [];

  final acumuladas = _distanciasAcumuladas(coordenadas);
  final margemGraus = raioCorredorKm / 100;
  final boxes = _construirBoundingBoxes(coordenadas, acumuladas, margemGraus);
  if (boxes.isEmpty) return [];

  final postosBrutos = <String, Map<String, dynamic>>{};
  for (final box in boxes) {
    try {
      final linhas = await SupabaseService.client
          .from('anp_postos')
          .select('cnpj, razao_social, municipio, uf, bandeira, latitude, longitude')
          .eq('ativo', true)
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .not('cnpj', 'is', null)
          .gte('latitude', box.minLat)
          .lte('latitude', box.maxLat)
          .gte('longitude', box.minLon)
          .lte('longitude', box.maxLon)
          .limit(3000);
      for (final l in (linhas as List)) {
        final m = l as Map<String, dynamic>;
        final cnpj = m['cnpj'] as String?;
        if (cnpj != null) postosBrutos[cnpj] = m;
      }
    } catch (_) {
      continue;
    }
  }
  if (postosBrutos.isEmpty) return [];

  // Km na rota + desvio de cada posto, filtrando quem está longe do corredor.
  final candidatosBrutos = <Map<String, dynamic>>[];
  for (final m in postosBrutos.values) {
    final lat = (m['latitude'] as num?)?.toDouble();
    final lon = (m['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) continue;
    final pos = _posicaoNaRotaKm(PontoRota(lat: lat, lon: lon), coordenadas, acumuladas);
    if (pos.desvioKm <= raioCorredorKm) {
      candidatosBrutos.add({...m, '_km': pos.km, '_desvioKm': pos.desvioKm});
    }
  }
  if (candidatosBrutos.isEmpty) return [];

  // Estados presentes no corredor — só busca preço de referência dos estados
  // que realmente têm posto candidato, em vez do Brasil inteiro.
  final estados = candidatosBrutos
      .map((m) => m['uf'] as String?)
      .whereType<String>()
      .map((uf) => ufParaEstadoAnp[uf.toUpperCase()])
      .whereType<String>()
      .toSet()
      .toList();

  final precoPorMunicipio = <String, double>{};
  final precoPorEstado = <String, double>{};
  double? precoBrasil;

  try {
    if (estados.isNotEmpty) {
      final municData = await SupabaseService.client
          .from('anp_precos_referencia')
          .select('municipio, estado, preco_medio, data_final')
          .eq('nivel', 'municipio')
          .eq('produto', categoria)
          .inFilter('estado', estados)
          .order('data_final', ascending: false);
      for (final l in (municData as List)) {
        final m = l as Map<String, dynamic>;
        final precoMedio = (m['preco_medio'] as num?)?.toDouble();
        if (precoMedio == null) continue;
        final chave = '${m['municipio']}__${m['estado']}';
        precoPorMunicipio.putIfAbsent(chave, () => precoMedio);
      }

      final estData = await SupabaseService.client
          .from('anp_precos_referencia')
          .select('estado, preco_medio, data_final')
          .eq('nivel', 'estado')
          .eq('produto', categoria)
          .inFilter('estado', estados)
          .order('data_final', ascending: false);
      for (final l in (estData as List)) {
        final m = l as Map<String, dynamic>;
        final precoMedio = (m['preco_medio'] as num?)?.toDouble();
        if (precoMedio == null) continue;
        precoPorEstado.putIfAbsent(m['estado'] as String, () => precoMedio);
      }
    }

    final brasilData = await SupabaseService.client
        .from('anp_precos_referencia')
        .select('preco_medio')
        .eq('nivel', 'brasil')
        .eq('produto', categoria)
        .order('data_final', ascending: false)
        .limit(1)
        .maybeSingle();
    precoBrasil = (brasilData?['preco_medio'] as num?)?.toDouble();
  } catch (_) {
    // segue com o que já tiver resolvido (pode ficar sem preço Brasil)
  }

  final candidatos = <CandidatoAbastecimento>[];
  for (final m in candidatosBrutos) {
    final uf = m['uf'] as String?;
    final estadoAnp = uf != null ? ufParaEstadoAnp[uf.toUpperCase()] : null;
    final municipioNorm = m['municipio'] != null ? normalizarTexto(m['municipio'] as String) : '';
    final preco = (estadoAnp != null ? precoPorMunicipio['${municipioNorm}__$estadoAnp'] : null) ??
        (estadoAnp != null ? precoPorEstado[estadoAnp] : null) ??
        precoBrasil;
    final cnpj = m['cnpj'] as String?;
    if (preco == null || cnpj == null) continue;

    final score = calcularScorePosto(precoPosto: preco, precoReferenciaAnp: null, servicosAtivos: 0, servicosTotal: 10);

    candidatos.add(CandidatoAbastecimento(
      cnpj: cnpj,
      km: m['_km'] as double,
      desvioKm: m['_desvioKm'] as double,
      preco: preco,
      grade: score.grade,
      label: (m['razao_social'] as String?) ?? cnpj,
      lat: (m['latitude'] as num).toDouble(),
      lon: (m['longitude'] as num).toDouble(),
      bandeira: m['bandeira'] as String?,
      uf: uf,
      municipio: m['municipio'] as String?,
    ));
  }

  return candidatos;
}
