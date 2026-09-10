import 'package:flutter/material.dart';

// Identidade visual FNI (Fase 17/07, pedido do Daniel: "seguir o design
// system de FNI, com as mesmas cores e layout") — extraída de
// tailwind.config.ts / globals.css do painel web "Gestão de Frotas"
// (família de cor "frota" + cores semânticas de status). Substitui a
// paleta verde provisória do MVP inicial.
class AppTheme {
  // Fase Design-System-Swiss-Minimalism (29/08/2026) → Fase Paleta-Clara
  // (04/09/2026) → Fase Design-ProFrotas-Divergencias (10/09/2026, pedido
  // do Daniel: "Vamos atualizar os PWAs cliente e motorista com o mesmo
  // design aplicado na aplicacao web") — a web trocou de "Swiss
  // Minimalism" (off-black/branco/cinza + acento taupe, cantos quase
  // retos) pra "Design-ProFrotas-Divergencias" em 09/09/2026 (ver
  // tailwind.config.ts/globals.css do painel web): paleta slate `frota`
  // ATUALIZADA (valores hex reais da escala, era aproximação em
  // off-black/cinza puro) + acento LARANJA (`accento` = #de6024, era
  // taupe #b38b6d) + cantos bem arredondados (radius 14, era 4) + sombra
  // suave difusa cor-de-ardósia (era sombra quase preta e chapada). Este
  // arquivo espelha os MESMOS valores — mesma convenção já usada aqui
  // antes ("nomes mantidos, só o valor muda"), pra não precisar editar
  // campo por campo nas ~29 telas que já referenciam
  // `AppTheme.frota*`/`AppTheme.glass*`.
  static const Color frota950 = Color(0xFF2B3444); // slate — tinta (sombra)
  static const Color frota900 = Color(0xFF333C4D);
  static const Color frota800 = Color(0xFF3D495F);
  static const Color frota700 = Color(0xFF4E5D77);
  static const Color frota600 = Color(0xFF66748D); // hover/darken do botão primário
  static const Color frota500 = Color(0xFF4E5D77); // ação principal (botões, ícones em destaque)
  static const Color frota100 = Color(0xFFE7EAEF);
  static const Color frota50 = Color(0xFFF0F0F0); // fundo de página, igual ao web

  // Cores semânticas — mesmos códigos usados nos badges do painel web
  // (atualizadas na fase Design-ProFrotas-Divergencias junto com o resto
  // da paleta; eram Color(0xFF16A34A)/F59E0B/DC2626 — tons genéricos
  // Tailwind, agora os tons próprios do design system "frota").
  static const Color statusAtivo = Color(0xFF4DB956);
  static const Color statusAtencao = Color(0xFFE0A020);
  static const Color statusInativo = Color(0xFFD94F4F);

  /// Cor principal de ação (botões, ícones em destaque) — mantido como alias
  /// pra não quebrar quem já importa `corPrincipal`.
  static const Color corPrincipal = frota500;

  // Único acento decorativo do tema (design.md web: "accento — Extended
  // palette, decorative/CTA use") — usado em toques pontuais (indicador de
  // nível/pontos no drawer, item ativo do menu, botão primário), nunca na
  // paleta funcional slate/branco dos textos/bordas.
  static const Color accento = Color(0xFFDE6024);
  static const Color accentoLight = Color(0xFFF0997B);
  static const Color accentoDark = Color(0xFFB84917);

  // Fase Paleta-Clara (04/09/2026) — com o menu agora claro (`frota50`),
  // texto/ícone invertem de claro-sobre-escuro pra escuro-sobre-claro.
  // Espelha .glass-nav-texto/-texto-muted/-icone/-acento do globals.css
  // web (slate-800/slate-500/slate-500/accento — inalterados na fase
  // Design-ProFrotas-Divergencias). Nomes `glass*` datam da fase "vidro"
  // (20/08/2026), mantidos por estabilidade (usados em ~29 telas).
  static const Color glassTexto = Color(0xFF1E293B); // slate-800
  static const Color glassTextoMuted = Color(0xFF64748B); // slate-500
  static const Color glassIcone = Color(0xFF64748B); // slate-500
  static const Color glassAcento = accento;

  // Antes um RadialGradient "anel de luz" (ver histórico de fases deste
  // arquivo); a fase Swiss-Minimalism pediu fundo LISO, sem blur/glow —
  // mantido assim na fase Design-ProFrotas-Divergencias. Mantido como
  // `Gradient` (não `Color`) só pra não precisar editar as ~29 telas que
  // fazem `BoxDecoration(gradient: AppTheme.glassNavGradient)`: um
  // gradiente com as DUAS paradas na mesma cor renderiza idêntico a uma
  // cor sólida.
  static const Gradient glassNavGradient = LinearGradient(
    colors: [frota50, frota50],
  );

  // Radius único usado em card/botão/input no design atual do web
  // (tailwind.config.ts `borderRadius.xl = 14px`) — era 4px.
  static const double radius = 14;

  static ThemeData get tema {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: frota500,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: frota50, // igual ao painel web
      appBarTheme: const AppBarTheme(
        backgroundColor: frota50,
        foregroundColor: frota500,
        centerTitle: true,
        iconTheme: IconThemeData(color: frota500),
        elevation: 0,
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: frota50),
      // Fase Design-ProFrotas-Divergencias (10/09/2026) — Card é usado em
      // quase toda tela sem estilo próprio (só `Card(child: ...)`). Espelha
      // `.card` do globals.css web: cantos bem arredondados (14px, era 4px)
      // e sombra suave e difusa cor-de-ardósia (era
      // `frota950.withOpacity(0.06)`, quase preta e chapada — CSS
      // `shadow-card: 0 12px 32px rgba(78,93,119,.12)`; aqui aproximado com
      // elevation + shadowColor, já que Flutter não tem blur de sombra
      // configurável por Card).
      cardTheme: CardThemeData(
        elevation: 2,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: frota700.withOpacity(0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: Color(0xFFE2E8F0)), // slate-200
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
          backgroundColor: accento,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: frota700,
          side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5), // slate-300
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)), // slate-300
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: frota500, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
