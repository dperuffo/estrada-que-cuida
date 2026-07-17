import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../../../core/services/supabase_service.dart';

// Roteirização self-service do motorista (Fase 17/07) — mesmos serviços
// públicos e gratuitos usados no planejador do painel web
// (src/lib/geo.ts): Nominatim pra geocodificação e OSRM público pra
// cálculo de rota. Aqui chamados direto do app (sem depender do servidor
// Next.js), com os mesmos parâmetros/servidores pra manter resultado
// consistente entre as duas telas.

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

  const VeiculoRoteirizacao({
    required this.placa,
    this.marca,
    this.modelo,
    required this.tanque,
    required this.autonomia,
    required this.vinculoAtivo,
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
      );
    }).toList();
  } catch (_) {
    return [];
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

double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
  const raioTerraKm = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return raioTerraKm * c;
}

/// Amostra a rota por DISTÂNCIA percorrida (não por índice de coordenada) —
/// garante cobertura proporcional em rotas curtas e longas. Ex.: uma
/// amostra a cada ~80km, no máximo `maxAmostras`.
List<PontoRota> _amostrarPorDistancia(List<PontoRota> coordenadas, {double intervaloKm = 80, int maxAmostras = 15}) {
  if (coordenadas.isEmpty) return [];
  final amostras = <PontoRota>[coordenadas.first];
  var acumulado = 0.0;
  for (var i = 1; i < coordenadas.length && amostras.length < maxAmostras; i++) {
    final anterior = coordenadas[i - 1];
    final atual = coordenadas[i];
    acumulado += _distanciaKm(anterior.lat, anterior.lon, atual.lat, atual.lon);
    if (acumulado >= intervaloKm) {
      amostras.add(atual);
      acumulado = 0;
    }
  }
  if (amostras.last != coordenadas.last && amostras.length < maxAmostras) {
    amostras.add(coordenadas.last);
  }
  return amostras;
}

class PostoSugerido {
  final String razaoSocial;
  final String? bandeira;
  final String? endereco;
  final String? municipio;
  final double lat;
  final double lon;
  final double distanciaKm;

  const PostoSugerido({
    required this.razaoSocial,
    this.bandeira,
    this.endereco,
    this.municipio,
    required this.lat,
    required this.lon,
    required this.distanciaKm,
  });
}

/// Postos ANP (base pública nacional, sem vínculo de empresa — RLS libera
/// leitura pra qualquer autenticado) próximos da rota. Faz UMA busca por
/// amostra ao longo do trajeto (não uma caixa gigante cobrindo a rota
/// inteira, que só devolvia postos concentrados numa ponta por causa do
/// limite de linhas) e pega o mais próximo de cada amostra — dá cobertura
/// espalhada do início ao fim da viagem.
Future<List<PostoSugerido>> buscarPostosProximos(List<PontoRota> coordenadas, {double intervaloKm = 80}) async {
  final amostras = _amostrarPorDistancia(coordenadas, intervaloKm: intervaloKm);
  if (amostras.isEmpty) return [];

  const raioBuscaGraus = 0.3; // ~30km
  final resultados = await Future.wait(amostras.map((amostra) async {
    try {
      final linhas = await SupabaseService.client
          .from('anp_postos')
          .select('razao_social, bandeira, endereco, municipio, latitude, longitude')
          .eq('ativo', true)
          .gte('latitude', amostra.lat - raioBuscaGraus)
          .lte('latitude', amostra.lat + raioBuscaGraus)
          .gte('longitude', amostra.lon - raioBuscaGraus)
          .lte('longitude', amostra.lon + raioBuscaGraus)
          .limit(80);

      PostoSugerido? maisProximo;
      var menorDistancia = double.infinity;
      for (final linha in (linhas as List)) {
        final mapa = linha as Map<String, dynamic>;
        final lat = (mapa['latitude'] as num?)?.toDouble();
        final lon = (mapa['longitude'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final d = _distanciaKm(lat, lon, amostra.lat, amostra.lon);
        if (d < menorDistancia) {
          menorDistancia = d;
          maisProximo = PostoSugerido(
            razaoSocial: (mapa['razao_social'] as String?) ?? 'Posto',
            bandeira: mapa['bandeira'] as String?,
            endereco: mapa['endereco'] as String?,
            municipio: mapa['municipio'] as String?,
            lat: lat,
            lon: lon,
            distanciaKm: d,
          );
        }
      }
      return maisProximo;
    } catch (_) {
      return null;
    }
  }));

  final vistos = <String>{};
  final postos = <PostoSugerido>[];
  for (final p in resultados) {
    if (p == null) continue;
    final chave = '${p.razaoSocial}|${p.municipio}';
    if (vistos.add(chave)) postos.add(p);
  }
  return postos;
}
