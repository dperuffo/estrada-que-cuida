import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/fidelidade/categorias_fidelidade.dart';

final _formatoPontosCard = NumberFormat.decimalPattern('pt_BR');
final _formatoDataCard = DateFormat('dd/MM/yyyy');

/// Card estilo "cupom de voucher" — pedido do Daniel (17/07): "em ambas as
/// visões, cliente, posto e motorista, deverão ser apresentados em cards,
/// coloridos, em formato de cupons de voucher, que contenham imagens dos
/// produtos e serviços, quantidade de pontos para resgate, número do
/// voucher, validade e descrição do benefício". Usado no Catálogo (sem
/// número de voucher — só existe depois do resgate) e em "Meus resgates"
/// (com número do voucher e validade). Mesmo design do card web
/// (CardVoucher.tsx em /parcerias-locais), pra ficar consistente entre as
/// duas telas.
class CardVoucher extends StatelessWidget {
  final String titulo;
  final String? descricao;
  final String categoria;
  final String? parceiroNome;
  final int pontos;
  final String? imagemUrl;
  final String? numeroVoucher;
  final DateTime? validoAte;
  final Widget? rodape;
  final Widget? acoes;

  const CardVoucher({
    super.key,
    required this.titulo,
    this.descricao,
    required this.categoria,
    this.parceiroNome,
    required this.pontos,
    this.imagemUrl,
    this.numeroVoucher,
    this.validoAte,
    this.rodape,
    this.acoes,
  });

  @override
  Widget build(BuildContext context) {
    final estilo = estiloCategoria(categoria);
    return Container(
      decoration: BoxDecoration(
        color: estilo.cor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: estilo.cor.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              SizedBox(
                height: 120,
                width: double.infinity,
                child: imagemUrl != null
                    ? Image.network(
                        imagemUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _Placeholder(estilo: estilo),
                      )
                    : _Placeholder(estilo: estilo),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: estilo.cor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_formatoPontosCard.format(pontos)} pts',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  estilo.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: estilo.cor,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (parceiroNome != null)
                  Text(
                    parceiroNome!,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                if (descricao != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    descricao!,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
                if (numeroVoucher != null || validoAte != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.only(top: 8),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.black12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (numeroVoucher != null)
                          Text(
                            'Voucher: $numeroVoucher',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.black54,
                            ),
                          ),
                        if (validoAte != null)
                          Text(
                            'Válido até ${_formatoDataCard.format(validoAte!)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (rodape != null) ...[const SizedBox(height: 8), rodape!],
                if (acoes != null) ...[const SizedBox(height: 8), acoes!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final EstiloCategoriaFidelidade estilo;

  const _Placeholder({required this.estilo});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: estilo.cor.withValues(alpha: 0.15),
      child: Center(
        child: Icon(
          Icons.confirmation_number_outlined,
          size: 36,
          color: estilo.cor,
        ),
      ),
    );
  }
}
