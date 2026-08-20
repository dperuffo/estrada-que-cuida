import 'package:flutter/material.dart';

// Identidade visual FNI (Fase 17/07, pedido do Daniel: "seguir o design
// system de FNI, com as mesmas cores e layout") — extraída de
// tailwind.config.ts / globals.css do painel web "Gestão de Frotas"
// (família de cor "frota" + cores semânticas de status). Substitui a
// paleta verde provisória do MVP inicial.
class AppTheme {
  // "frota" — mesma família de cor do painel web, do mais escuro (fundo do
  // menu lateral) ao mais claro.
  static const Color frota950 = Color(0xFF0B1220); // fundo do menu/drawer
  static const Color frota900 = Color(0xFF0F2A4A);
  static const Color frota800 = Color(0xFF123A63);
  static const Color frota700 = Color(0xFF155080);
  static const Color frota600 = Color(0xFF0E7490); // destaque secundário
  static const Color frota500 = Color(0xFF0EA5E9); // ação principal / CTA
  static const Color frota100 = Color(0xFFE0F2FE);
  static const Color frota50 = Color(0xFFF0F9FF);

  // Cores semânticas — mesmos códigos usados nos badges do painel web.
  static const Color statusAtivo = Color(0xFF16A34A);
  static const Color statusAtencao = Color(0xFFF59E0B);
  static const Color statusInativo = Color(0xFFDC2626);

  /// Cor principal de ação (botões, ícones em destaque) — mantido como alias
  /// pra não quebrar quem já importa `corPrincipal`.
  static const Color corPrincipal = frota500;

  // Fase Liquid-Glass-PWA (20/08/2026, pedido do Daniel: aplicar nos PWAs
  // cliente e motorista o mesmo liquid glass já feito na web) — mesma
  // paleta do menu lateral web e do PWA cliente (ver globals.css:
  // .glass-nav/.glass-nav-*). O Flutter não tem "backdrop-filter"
  // aplicável via Theme a qualquer widget — o efeito vidro aqui vem da
  // combinação gradiente + opacidade + borda clara + sombra suave, sem
  // desfoque literal, mesma linguagem visual da web.
  //
  // Fase Liquid-Glass-Anel (20/08/2026, pedido do Daniel: "o cinza anterior
  // não ficou bom" — 3ª imagem de referência: fundo quase preto
  // azul-marinho, com um anel de luz azul-violeta brilhando só do lado
  // esquerdo, tipo borda de esfera/portal) — troca a paleta cinza da fase
  // anterior por esta nova, extraída por amostragem de pixel da imagem.
  // Nomes das constantes mantidos (glassBronze*) por estabilidade — só o
  // valor de cor mudou. O CSS da web usa várias camadas de
  // radial-gradient pro anel, mas o Flutter só aceita 1 gradient por
  // BoxDecoration — por isso aqui é um ÚNICO RadialGradient com centro
  // fora da tela (Alignment(-1.8, 0)) e paradas (stops) que criam
  // transparent->brilho->transparent, o mesmo truque de "buraco no meio"
  // que faz só a BORDA do círculo aparecer.
  static const Color glassBronzeClaro = Color(0xFF2A2A45);
  static const Color glassBronzeMedio = Color(0xFF1C1B2F);
  static const Color glassBronzeEscuro = Color(0xFF10101F);
  static const Color glassBrilho = Color(0xFF999ED9);
  static const Color glassBrilhoMedio = Color(0xFF8D94CA);
  static const Color glassTexto = Color(0xFFF5F5FA);
  static const Color glassTextoMuted = Color(0xFFA5A6C4);
  static const Color glassIcone = Color(0xFFE8E9F5);
  static const Color glassAcento = Color(0xFFFFD9A0);

  static const Gradient glassNavGradient = RadialGradient(
    center: Alignment(-1.8, 0.0),
    radius: 1.3,
    colors: [
      glassBronzeMedio,
      glassBronzeMedio,
      glassBrilhoMedio,
      glassBrilho,
      glassBronzeEscuro,
      glassBronzeClaro,
    ],
    stops: [0.0, 0.55, 0.6, 0.64, 0.7, 1.0],
  );

  static ThemeData get tema {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: frota500,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(
        0xFFF8FAFC,
      ), // slate-50, igual ao painel web
      appBarTheme: const AppBarTheme(
        backgroundColor: frota950,
        foregroundColor: Colors.white,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: frota950),
      // Fase Liquid-Glass-PWA (20/08/2026) — Card é usado em quase toda
      // tela sem estilo próprio (só `Card(child: ...)`, no visual padrão
      // do Material). Por ser um ponto central do Theme (igual ao `.card`
      // do globals.css na web), dá pra dar o efeito vidro (translúcido +
      // borda clara + sombra suave) em toda tela de uma vez, sem editar
      // arquivo por arquivo.
      cardTheme: CardThemeData(
        elevation: 1,
        color: Colors.white.withOpacity(0.82),
        surfaceTintColor: Colors.transparent,
        shadowColor: frota950.withOpacity(0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withOpacity(0.7)),
        ),
      ),
      // ATENÇÃO: `Size.fromHeight(48)` deixa a LARGURA mínima infinita —
      // funciona bem pros botões de tela cheia (login, OTP, adesão), mas
      // quebra o layout (erro "BoxConstraints forces an infinite width")
      // em qualquer ElevatedButton colocado dentro de um Row sem Expanded.
      // Nesses casos, sobrescreva localmente com
      // `style: ElevatedButton.styleFrom(minimumSize: const Size(64, 40))`
      // (ver exemplo em catalogo_screen.dart, botão "Resgatar").
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: frota500,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: frota700,
          side: const BorderSide(color: frota600),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
