// Port fiel de trechos de src/lib/constants.ts (Gestão de Frotas) usados na
// Roteirização: lista de combustíveis vendidos no posto (mesmo filtro do
// painel web) e o de-para UF <-> nome do estado como a ANP grafa no
// relatório oficial (usado pra achar o preço de referência por
// município/estado/Brasil em anp_precos_referencia).

/// Combustíveis que aparecem no seletor da Roteirização — mesma lista do
/// painel web (PRODUTOS_POSTO em constants.ts).
const List<String> produtosPosto = [
  'Gasolina Comum',
  'Gasolina Aditivada',
  'Gasolina Alta Octanagem',
  'Etanol Comum',
  'Etanol Aditivado',
  'Diesel S-10 Comum',
  'Diesel S-10 Aditivado',
  'Diesel S-500 Comum',
  'Diesel S-500 Aditivado',
  'GNV',
  'GLP',
];

/// Categoria oficial ANP de cada produto — usada pra buscar o preço em
/// anp_precos_referencia.produto (a ANP agrupa comum/aditivado numa única
/// categoria por combustível).
const Map<String, String> produtoParaCategoriaAnp = {
  'Diesel S-500 Comum': 'OLEO DIESEL',
  'Diesel S-500 Aditivado': 'OLEO DIESEL',
  'Diesel S-10 Comum': 'OLEO DIESEL S10',
  'Diesel S-10 Aditivado': 'OLEO DIESEL S10',
  'Etanol Comum': 'ETANOL HIDRATADO',
  'Etanol Aditivado': 'ETANOL HIDRATADO',
  'Gasolina Comum': 'GASOLINA COMUM',
  'Gasolina Aditivada': 'GASOLINA ADITIVADA',
  'Gasolina Alta Octanagem': 'GASOLINA ADITIVADA',
  'GNV': 'GNV',
  'GLP': 'GLP',
};

/// Nome do estado como a ANP grafa no relatório oficial (maiúsculas, sem
/// acento) — pra casar a UF (sigla) do posto com a coluna "estado" de
/// anp_precos_referencia.
const Map<String, String> ufParaEstadoAnp = {
  'AC': 'ACRE',
  'AL': 'ALAGOAS',
  'AP': 'AMAPA',
  'AM': 'AMAZONAS',
  'BA': 'BAHIA',
  'CE': 'CEARA',
  'DF': 'DISTRITO FEDERAL',
  'ES': 'ESPIRITO SANTO',
  'GO': 'GOIAS',
  'MA': 'MARANHAO',
  'MT': 'MATO GROSSO',
  'MS': 'MATO GROSSO DO SUL',
  'MG': 'MINAS GERAIS',
  'PA': 'PARA',
  'PB': 'PARAIBA',
  'PR': 'PARANA',
  'PE': 'PERNAMBUCO',
  'PI': 'PIAUI',
  'RJ': 'RIO DE JANEIRO',
  'RN': 'RIO GRANDE DO NORTE',
  'RS': 'RIO GRANDE DO SUL',
  'RO': 'RONDONIA',
  'RR': 'RORAIMA',
  'SC': 'SANTA CATARINA',
  'SP': 'SAO PAULO',
  'SE': 'SERGIPE',
  'TO': 'TOCANTINS',
};
