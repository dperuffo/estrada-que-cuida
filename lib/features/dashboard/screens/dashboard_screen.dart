import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/sino_avisos.dart';
import '../../abastecimentos/providers/abastecimentos_provider.dart';
import '../../gamificacao/providers/missoes_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/home_resumo_provider.dart';

final _formatoPontos = NumberFormat.decimalPattern('pt_BR');
final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _formatoNumero = NumberFormat.decimalPattern('pt_BR');
final _formatoDiaCurto = DateFormat('dd/MM');

// Fase Home-interativa — pedido do Daniel (17/07): os botões que
// duplicavam o menu lateral saíram daqui (já dá pra chegar em todo lugar
// pelo Drawer). No lugar, a Home virou um resumo do que importa agora:
// nível/progresso, sugestões do momento (abastecimento parado pra
// confirmar, missão quase concluída) e as missões em si, com barra de
// progresso — sem precisar entrar em mais nenhuma tela pra saber "o que
// falta".
class DashboardScreen extends ConsumerWidget {
  final String motoristaId;
  final String? nome;

  const DashboardScreen({super.key, required this.motoristaId, this.nome});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primeiroNome = (nome ?? '').split(' ').first;
    final saldoAsync = ref.watch(saldoPontosProvider);
    final missoesAsync = ref.watch(missoesProvider);
    final pendentesAsync = ref.watch(abastecimentosPendentesProvider);
    final homeResumoAsync = ref.watch(homeResumoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Estrada que Cuida'), actions: const [SinoAvisos()]),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(saldoPontosProvider);
          ref.invalidate(missoesProvider);
          ref.invalidate(abastecimentosPendentesProvider);
          ref.invalidate(homeResumoProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              primeiroNome.isEmpty ? 'Olá!' : 'Olá, $primeiroNome!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Cartão do cliente/cota/frete — pedido do Daniel (19/07): quem
            // é o cliente, se o motorista é próprio/agregado/terceiro, e os
            // saldos de combustível (cota do veículo e, se houver, frete
            // ativo) logo no topo. Some da tela se ainda não tem vínculo de
            // veículo nem nada configurado — não força cartão vazio.
            homeResumoAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => const SizedBox.shrink(),
              data: (resumo) => resumo == null || resumo.status != 'ok'
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _CartaoCliente(resumo: resumo),
                    ),
            ),

            saldoAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Text('Não consegui carregar seu saldo agora.'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(saldoPontosProvider),
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
              data: (saldo) => _CartaoNivel(saldo: saldo),
            ),
            const SizedBox(height: 16),
            _CartaoVoltePraCasa(onTap: () => context.push('/catalogo', extra: 'volte_para_casa')),

            // Sugestões — cartões dinâmicos, só aparecem quando fazem
            // sentido pro motorista agora (nada de espaço vazio "avisando
            // que não há nada a avisar").
            ...pendentesAsync.maybeWhen(
              data: (pendentes) => pendentes.isEmpty
                  ? []
                  : [
                      const SizedBox(height: 20),
                      _CartaoSugestao(
                        icone: Icons.local_gas_station,
                        cor: const Color(0xFF1E6FBF),
                        titulo: pendentes.length == 1
                            ? '1 abastecimento esperando confirmação'
                            : '${pendentes.length} abastecimentos esperando confirmação',
                        subtitulo: 'Confirme pra não perder os pontos deles.',
                        onTap: () => context.push('/pendentes'),
                      ),
                    ],
              orElse: () => [],
            ),

            const SizedBox(height: 28),
            const Text('Suas missões', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            const Text(
              'Complete missões pra ganhar pontos bônus, além dos pontos normais de cada abastecimento.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            missoesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    const Text('Não consegui carregar suas missões agora.'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(missoesProvider),
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
              data: (missoes) => _BlocoMissoes(missoes: missoes),
            ),

            // Seção de consumo — pedido do Daniel (19/07): volume e valor
            // abastecidos hoje, médias de consumo do veículo (KM/L e
            // R$/L) e gráfico dos últimos 7 dias. Some se ainda não há
            // veículo vinculado (nada pra mostrar).
            homeResumoAsync.maybeWhen(
              data: (resumo) => resumo == null || resumo.status != 'ok' || resumo.placa == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 28),
                      child: _SecaoConsumo(resumo: resumo),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// Badge "Próprio" / "Agregado" / "Terceiro" — cor muda conforme a
// classificação, só pra dar uma pista visual rápida.
class _BadgeClassificacao extends StatelessWidget {
  final String classificacao;

  const _BadgeClassificacao({required this.classificacao});

  @override
  Widget build(BuildContext context) {
    final cor = switch (classificacao) {
      'Próprio' => const Color(0xFF1B7A43),
      'Agregado' => const Color(0xFF1E6FBF),
      _ => const Color(0xFF9E7A00),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        classificacao,
        style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

// Barra de progresso de um saldo (cota ou frete) — verde quando sobra
// bastante, amarelo quando está acabando, vermelho quando estourou
// (saldo negativo, ainda assim mostra pra deixar claro que passou).
class _BarraSaldo extends StatelessWidget {
  final String rotulo;
  final double limite;
  final double saldo;
  final bool emVolume;
  // Fase Financeiro-Motorista-Ajuste — pedido do Daniel: o texto padrão
  // ("disponível"/"estourou") serve bem pra Cota (limite real, controlado
  // pelo cartão da rede), mas dava a entender que o saldo de frete é uma
  // carteira digital que o motorista "usa". Textos customizáveis por
  // chamada, mantendo o padrão pra Cota e trocando só na chamada de frete.
  final String textoDentroDoLimite;
  final String textoEstourou;

  const _BarraSaldo({
    required this.rotulo,
    required this.limite,
    required this.saldo,
    required this.emVolume,
    this.textoDentroDoLimite = 'disponível',
    this.textoEstourou = '(estourou)',
  });

  String _formata(double v) => emVolume ? '${_formatoNumero.format(v)} L' : _formatoMoeda.format(v);

  @override
  Widget build(BuildContext context) {
    final progresso = limite <= 0 ? 0.0 : (saldo / limite).clamp(0.0, 1.0);
    final estourou = saldo < 0;
    final cor = estourou
        ? Colors.redAccent
        : progresso < 0.2
            ? const Color(0xFFC97A00)
            : const Color(0xFF1B7A43);

    // Rótulo (pode incluir o título do frete, tamanho variável) numa linha
    // e o saldo embaixo, à parte — um Row com os dois lado a lado estourava
    // a largura do cartão quando o rótulo era comprido (achado do Daniel).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          estourou ? '${_formata(saldo)} $textoEstourou' : '${_formata(saldo)} $textoDentroDoLimite',
          style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: estourou ? 1.0 : progresso,
            minHeight: 8,
            backgroundColor: const Color(0xFFE5E5E0),
            valueColor: AlwaysStoppedAnimation(cor),
          ),
        ),
        const SizedBox(height: 2),
        Text('de ${_formata(limite)}', style: const TextStyle(color: Colors.black45, fontSize: 11.5)),
      ],
    );
  }
}

class _CartaoCliente extends StatelessWidget {
  final HomeResumo resumo;

  const _CartaoCliente({required this.resumo});

  @override
  Widget build(BuildContext context) {
    final cota = resumo.cota;
    final frete = resumo.frete;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.apartment_outlined, color: Colors.black54, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    resumo.empresaNome ?? 'Cliente',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (resumo.classificacao != null) _BadgeClassificacao(classificacao: resumo.classificacao!),
              ],
            ),
            if (cota != null || frete != null) ...[
              const SizedBox(height: 18),
              if (frete != null) ...[
                _BarraSaldo(
                  rotulo: 'Orçamento de combustível — frete: ${frete.titulo}',
                  limite: frete.alocado,
                  saldo: frete.saldo,
                  emVolume: frete.emVolume,
                  textoDentroDoLimite: 'restantes do orçamento',
                  textoEstourou: 'de orçamento estourado',
                ),
                const SizedBox(height: 4),
                const Text(
                  'É só acompanhamento — o desconto é automático conforme você abastece pela rede, sem carteira pra usar no app.',
                  style: TextStyle(color: Colors.black45, fontSize: 11.5),
                ),
                if (cota != null) const SizedBox(height: 16),
              ],
              if (cota != null)
                _BarraSaldo(
                  rotulo: 'Cota de combustível (${cota.periodicidade.toLowerCase()})',
                  limite: cota.limite,
                  saldo: cota.saldo,
                  emVolume: cota.emVolume,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IndicadorConsumo extends StatelessWidget {
  final String rotulo;
  final String valor;
  final IconData icone;

  const _IndicadorConsumo({required this.rotulo, required this.valor, required this.icone});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F3EF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icone, color: const Color(0xFF1E6FBF), size: 22),
            const SizedBox(height: 6),
            Text(valor, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 2),
            Text(rotulo, style: const TextStyle(color: Colors.black54, fontSize: 11.5), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SecaoConsumo extends StatelessWidget {
  final HomeResumo resumo;

  const _SecaoConsumo({required this.resumo});

  @override
  Widget build(BuildContext context) {
    final medias = resumo.medias;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Seu consumo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          'Hoje: ${_formatoNumero.format(resumo.hoje.litros)} L · ${_formatoMoeda.format(resumo.hoje.valor)}',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _IndicadorConsumo(
              rotulo: 'Média KM/L (30 dias)',
              valor: medias.kmL == null ? '—' : '${medias.kmL!.toStringAsFixed(2)} km/L',
              icone: Icons.speed_outlined,
            ),
            const SizedBox(width: 12),
            _IndicadorConsumo(
              rotulo: 'Média R\$/L (30 dias)',
              valor: medias.valorPorLitro == null ? '—' : _formatoMoeda.format(medias.valorPorLitro),
              icone: Icons.local_gas_station_outlined,
            ),
          ],
        ),
        if (resumo.serie7Dias.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Litros abastecidos — últimos 7 dias', style: TextStyle(color: Colors.black54, fontSize: 12.5)),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: _GraficoBarrasDiario(pontos: resumo.serie7Dias),
          ),
        ],
      ],
    );
  }
}

// Gráfico de barras simples (sem dependência nova) — 1 barra por dia dos
// últimos 7 dias, altura proporcional aos litros abastecidos. Rótulo do
// dia embaixo, valor em litros em cima da barra quando > 0.
class _GraficoBarrasDiario extends StatelessWidget {
  final List<PontoSerieDia> pontos;

  const _GraficoBarrasDiario({required this.pontos});

  @override
  Widget build(BuildContext context) {
    final maximo = pontos.map((p) => p.litros).fold<double>(0, (a, b) => a > b ? a : b);
    const alturaMax = 92.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: pontos.map((p) {
        final altura = maximo <= 0 ? 0.0 : (p.litros / maximo) * alturaMax;
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (p.litros > 0)
              Text(_formatoNumero.format(p.litros), style: const TextStyle(fontSize: 10, color: Colors.black54)),
            const SizedBox(height: 4),
            Container(
              width: 22,
              height: altura < 3 && p.litros > 0 ? 3 : altura,
              decoration: BoxDecoration(
                color: const Color(0xFF1E6FBF),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
            const SizedBox(height: 6),
            Text(_formatoDiaCurto.format(p.dia), style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
          ],
        );
      }).toList(),
    );
  }
}

// Atalho de destaque — pilar "Volte para Casa" do programa: se o
// motorista está cansado e precisa de ajuda pra voltar com segurança, o
// benefício está a 1 toque, sem precisar navegar pelo catálogo inteiro.
class _CartaoVoltePraCasa extends StatelessWidget {
  final VoidCallback onTap;

  const _CartaoVoltePraCasa({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFEAF5EE),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.home_outlined, color: Color(0xFF1B7A43), size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cansado na estrada?', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Veja os benefícios de Volte para Casa.', style: TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartaoNivel extends StatelessWidget {
  final int saldo;

  const _CartaoNivel({required this.saldo});

  @override
  Widget build(BuildContext context) {
    final nivel = nivelParaSaldo(saldo);
    final proximo = proximoNivel(saldo);
    final progresso = proximo == null ? 1.0 : (saldo - nivel.min) / (proximo.min - nivel.min);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(nivel.icone, color: nivel.cor, size: 32),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nível ${nivel.nome}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${_formatoPontos.format(saldo)} pontos', style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progresso.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: const Color(0xFFE5E5E0),
                valueColor: AlwaysStoppedAnimation(nivel.cor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              proximo == null
                  ? 'Você alcançou o nível máximo — parabéns!'
                  : 'Faltam ${_formatoPontos.format(proximo.min - saldo)} pontos para ${proximo.nome}',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

// Cartão de sugestão genérico — usado tanto pra "abastecimento parado"
// quanto pra qualquer outra dica futura que dependa de dado do momento
// (não é fixo, cada instância decide se aparece ou não).
class _CartaoSugestao extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _CartaoSugestao({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: cor.withValues(alpha: 0.08),
      margin: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icone, color: cor, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(subtitulo, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

// Mostra até 3 missões — as ainda não concluídas primeiro (mais perto de
// bater a meta primeiro, pra dar aquele empurrão), concluídas por
// último. Se tiver mais que isso, um link leva pra lista completa.
class _BlocoMissoes extends StatelessWidget {
  final List<MissaoProgresso> missoes;

  const _BlocoMissoes({required this.missoes});

  @override
  Widget build(BuildContext context) {
    if (missoes.isEmpty) {
      return const Text('Nenhuma missão disponível no momento.', style: TextStyle(color: Colors.black45));
    }

    final pendentes = missoes.where((m) => !m.concluida).toList()
      ..sort((a, b) {
        final progA = a.meta == 0 ? 0.0 : a.progresso / a.meta;
        final progB = b.meta == 0 ? 0.0 : b.progresso / b.meta;
        return progB.compareTo(progA); // mais perto de concluir primeiro
      });
    final concluidas = missoes.where((m) => m.concluida).toList();
    final ordenadas = [...pendentes, ...concluidas];
    final destaque = ordenadas.take(3).toList();
    final temMais = missoes.length > destaque.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...destaque.map((m) => _CartaoMissao(missao: m)),
        if (temMais) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => context.push('/missoes'),
            child: const Text('Ver todas as missões'),
          ),
        ],
      ],
    );
  }
}

class _CartaoMissao extends StatelessWidget {
  final MissaoProgresso missao;

  const _CartaoMissao({required this.missao});

  @override
  Widget build(BuildContext context) {
    final progresso = missao.meta == 0 ? 0.0 : missao.progresso / missao.meta;
    final cor = missao.concluida ? const Color(0xFF1B7A43) : const Color(0xFF1E6FBF);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(missao.iconeData, color: missao.concluida ? cor : Colors.black38, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(missao.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (!missao.concluida) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progresso.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: const Color(0xFFE5E5E0),
                        valueColor: AlwaysStoppedAnimation(cor),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Faltam ${(missao.meta - missao.progresso).clamp(0, missao.meta)} — +${missao.bonus} pontos ao concluir',
                      style: const TextStyle(color: Colors.black54, fontSize: 12.5),
                    ),
                  ] else
                    Text(
                      'Concluída — +${missao.bonus} pontos',
                      style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
