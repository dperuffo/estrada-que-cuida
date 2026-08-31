import 'package:flutter/material.dart';

// Identidade visual FNI (Fase 17/07, pedido do Daniel: "seguir o design
// system de FNI, com as mesmas cores e layout") — extraída de
// tailwind.config.ts / globals.css do painel web "Gestão de Frotas"
// (família de cor "frota" + cores semânticas de status). Substitui a
// paleta verde provisória do MVP inicial.
class AppTheme {
  // Fase Design-System-Swiss-Minimalism (29/08/2026, pedido do Daniel:
  // "aplicar o mesmo design.md dos PWAs Motorista e Cliente, conforme
  // aplicado na web") — a web trocou de "Corporate Blue" (Dark Navy/Royal
  // Blue) pra "Minimalism & Swiss Style" em 27/08/2026 (ver
  // tailwind.config.ts/globals.css do painel web): off-black/branco/
  // cinza + acento taupe, cantos quase retos, superfícies lisas, SEM
  // blur/gradiente/glow. Este arquivo espelha os MESMOS valores — mesma
  // convenção já usada aqui antes ("nomes mantidos, só o valor muda"),
  // pra não precisar editar campo por campo nas ~29 telas que já
  // referenciam `AppTheme.frota*`/`AppTheme.glass*`.
  static const Color frota950 = Color(0xFF111111); // off-black — fundo do menu/drawer/AppBar
  static const Color frota900 = Color(0xFF1A1A1A);
  static const Color frota800 = Color(0xFF262626);
  static const Color frota700 = Color(0xFF404040);
  static const Color frota600 = Color(0xFF0D0D0D); // hover/darken do botão primário
  static const Color frota500 = Color(0xFF171717); // ação principal (botões, ícones em destaque)
  static const Color frota100 = Color(0xFFE5E5E5);
  static const Color frota50 = Color(0xFFF8FAFC); // fundo de página (slate-50, igual ao web)

  // Cores semânticas — mesmos códigos usados nos badges do painel web
  // (não mudaram na fase Swiss-Minimalism, só a paleta neutra mudou).
  static const Color statusAtivo = Color(0xFF16A34A);
  static const Color statusAtencao = Color(0xFFF59E0B);
  static const Color statusInativo = Color(0xFFDC2626);

  /// Cor principal de ação (botões, ícones em destaque) — mantido como alias
  /// pra não quebrar quem já importa `corPrincipal`.
  static const Color corPrincipal = frota500;

  // Único acento decorativo do tema Swiss Minimalism (design.md web:
  // "Taupe — Extended palette, decorative use") — usado em toques pontuais
  // (indicador de nível/pontos no drawer, item ativo do menu), nunca na
  // paleta funcional preto/branco/cinza dos botões/inputs.
  static const Color accento = Color(0xFFB38B6D);
  static const Color accentoLight = Color(0xFFC9A788);

  // Fase Design-System-Swiss-Minimalism — os nomes `glass*` datam da fase
  // "vidro" (20/08/2026) anterior; mantidos por estabilidade (usados em
  // ~29 telas), mas o VALOR agora segue a nova identidade "flat": texto
  // quase-branco/cinza sobre o fundo off-black do menu, sem opacidade
  // vidrada. Espelha .glass-nav-texto/-texto-muted/-icone/-acento do
  // globals.css web (slate-100/slate-400/slate-300/accento).
  static const Color glassTexto = Color(0xFFF1F5F9); // slate-100
  static const Color glassTextoMuted = Color(0xFF94A3B8); // slate-400
  static const Color glassIcone = Color(0xFFCBD5E1); // slate-300
  static const Color glassAcento = accento;

  // Antes um RadialGradient "anel de luz" (ver histórico de fases deste
  // arquivo); a fase Swiss-Minimalism pede fundo LISO, sem blur/glow —
  // igual ao `.glass-nav` da web (`bg-frota-950`, sólido). Mantido como
  // `Gradient` (não `Color`) só pra não precisar editar as ~29 telas que
  // fazem `BoxDecoration(gradient: AppTheme.glassNavGradient)`: um
  // gradiente com as DUAS paradas na mesma cor renderiza idêntico a uma
  // cor sólida.
  static const Gradient glassNavGradient = LinearGradient(
    colors: [frota950, frota950],
  );

  static ThemeData get tema {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: frota500,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: frota50, // slate-50, igual ao painel web
      appBarTheme: const AppBarTheme(
        backgroundColor: frota950,
        foregroundColor: Colors.white,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        elevation: 0, // Swiss Minimalism: superfície lisa, sem sombra de elevação
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: frota950),
      // Fase Design-System-Swiss-Minimalism (29/08/2026) — Card é usado em
      // quase toda tela sem estilo próprio (só `Card(child: ...)`). Espelha
      // `.card` do globals.css web: superfície branca SÓLIDA (sem
      // translucidez/opacidade da fase vidro anterior), 1px de borda cinza-
      // clara, sombra suave, cantos quase retos (a web usa 2px; 4px aqui é
      // a concessão prática pro toque em tela pequena — mesmo espírito
      // "sharp edges", sem ficar visualmente um glitch de renderização).
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: frota950.withOpacity(0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
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
          backgroundColor: frota500,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: frota700,
          side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5), // slate-300
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)), // slate-300
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: frota500, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
