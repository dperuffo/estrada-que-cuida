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
  static const Color frota100 = Color(0xFFE7EAEF);

  // ---- Modo escuro (03/10/2026, pedido do Daniel: mesmo padrão claro /
  // escuro / automático do painel web). `dark` é atualizado por TemaHost
  // (theme/tema_host.dart) e força rebuild geral; os tokens abaixo trocam de
  // valor conforme ele — por isso são getters, não `const`.
  static bool dark = false;
  static Color _c(Color claro, Color escuro) => dark ? escuro : claro;

  static Color get frota700 => _c(const Color(0xFF4E5D77), const Color(0xFFCBD5E1));
  static Color get frota600 => _c(const Color(0xFF66748D), const Color(0xFFA3B1C6));
  static Color get frota500 => _c(const Color(0xFF4E5D77), const Color(0xFF94A3B8));
  static Color get frota50 => _c(const Color(0xFFF0F0F0), const Color(0xFF0F172A)); // fundo de página
  static Color get superficie => _c(Colors.white, const Color(0xFF1E293B)); // card/input
  static Color get superficieAlt => _c(const Color(0xFFF1F5F9), const Color(0xFF273449));
  static Color get bordaSuave => _c(const Color(0xFFE2E8F0), const Color(0xFF334155));
  static Color get bordaForte => _c(const Color(0xFFCBD5E1), const Color(0xFF475569));
  static Color get tintErro => _c(const Color(0xFFFEF2F2), const Color(0xFF3B1D1F));
  static Color get tintOk => _c(const Color(0xFFDCFCE7), const Color(0xFF14301F));
  static Color get tintAviso => _c(const Color(0xFFFEF3C7), const Color(0xFF3A2E10));
  static Color get fgErro => _c(const Color(0xFFB91C1C), const Color(0xFFFCA5A5));
  static Color get fgOk => _c(const Color(0xFF15803D), const Color(0xFF86EFAC));
  static Color get fgAviso => _c(const Color(0xFF92400E), const Color(0xFFFCD34D));
  static Color get fgInfo => _c(const Color(0xFF1D4ED8), const Color(0xFF93C5FD));
  // Escala de cinza (Colors.grey.shadeN) invertida no escuro, em tons slate.
  static Color get grey50 => _c(Colors.grey.shade50, const Color(0xFF1E293B));
  static Color get grey100 => _c(Colors.grey.shade100, const Color(0xFF1E293B));
  static Color get grey200 => _c(Colors.grey.shade200, const Color(0xFF334155));
  static Color get grey300 => _c(Colors.grey.shade300, const Color(0xFF475569));
  static Color get grey400 => _c(Colors.grey.shade400, const Color(0xFF64748B));
  static Color get grey500 => _c(Colors.grey, const Color(0xFF94A3B8));
  static Color get grey600 => _c(Colors.grey.shade600, const Color(0xFFA3B1C6));
  static Color get grey700 => _c(Colors.grey.shade700, const Color(0xFFCBD5E1));
  static Color get grey800 => _c(Colors.grey.shade800, const Color(0xFFE2E8F0));
  static Color get grey900 => _c(Colors.grey.shade900, const Color(0xFFF1F5F9));

  // Cores semânticas — mesmos códigos usados nos badges do painel web
  // (atualizadas na fase Design-ProFrotas-Divergencias junto com o resto
  // da paleta; eram Color(0xFF16A34A)/F59E0B/DC2626 — tons genéricos
  // Tailwind, agora os tons próprios do design system "frota").
  static const Color statusAtivo = Color(0xFF4DB956);
  static const Color statusAtencao = Color(0xFFE0A020);
  static const Color statusInativo = Color(0xFFD94F4F);

  /// Cor principal de ação (botões, ícones em destaque) — mantido como alias
  /// pra não quebrar quem já importa `corPrincipal`.
  static Color get corPrincipal => frota500;

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
  static Color get glassTexto => _c(const Color(0xFF1E293B), const Color(0xFFE2E8F0)); // slate-800
  static Color get glassTextoMuted => _c(const Color(0xFF64748B), const Color(0xFF94A3B8)); // slate-500
  static Color get glassIcone => _c(const Color(0xFF64748B), const Color(0xFF94A3B8)); // slate-500
  static const Color glassAcento = accento;

  // Antes um RadialGradient "anel de luz" (ver histórico de fases deste
  // arquivo); a fase Swiss-Minimalism pediu fundo LISO, sem blur/glow —
  // mantido assim na fase Design-ProFrotas-Divergencias. Mantido como
  // `Gradient` (não `Color`) só pra não precisar editar as ~29 telas que
  // fazem `BoxDecoration(gradient: AppTheme.glassNavGradient)`: um
  // gradiente com as DUAS paradas na mesma cor renderiza idêntico a uma
  // cor sólida.
  static Gradient get glassNavGradient =>
      LinearGradient(colors: [frota50, frota50]);

  // Radius único usado em card/botão/input no design atual do web
  // (tailwind.config.ts `borderRadius.xl = 14px`) — era 4px.
  static const double radius = 14;

  static ThemeData get temaClaro => _montar(Brightness.light);
  static ThemeData get temaEscuro => _montar(Brightness.dark);

  static ThemeData _montar(Brightness b) {
    final e = b == Brightness.dark;
    final fundo = e ? const Color(0xFF0F172A) : const Color(0xFFF0F0F0);
    final card = e ? const Color(0xFF1E293B) : Colors.white;
    final borda = e ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final bordaInput = e ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
    final primaria = e ? const Color(0xFF94A3B8) : const Color(0xFF4E5D77);
    final texto = e ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4E5D77),
        brightness: b,
        surface: e ? card : null,
      ),
      scaffoldBackgroundColor: fundo,
      canvasColor: fundo,
      dividerColor: borda,
      appBarTheme: AppBarTheme(
        backgroundColor: fundo,
        foregroundColor: primaria,
        centerTitle: true,
        iconTheme: IconThemeData(color: primaria),
        elevation: 0,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: fundo),
      dialogTheme: DialogThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
      cardTheme: CardThemeData(
        elevation: e ? 0 : 2,
        color: card,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0xFF4E5D77).withOpacity(0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borda),
        ),
      ),
      textTheme: ThemeData(brightness: b).textTheme.apply(bodyColor: texto, displayColor: texto),
      // ATENÇÃO: `Size.fromHeight(48)` deixa a LARGURA mínima infinita —
      // funciona bem pros botões de tela cheia (login, OTP, adesão), mas
      // quebra o layout (erro "BoxConstraints forces an infinite width")
      // em qualquer ElevatedButton colocado dentro de um Row sem Expanded.
      // Nesses casos, sobrescreva localmente com
      // `style: ElevatedButton.styleFrom(minimumSize: const Size(64, 40))`.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accento,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: e ? const Color(0xFFCBD5E1) : const Color(0xFF4E5D77),
          side: BorderSide(color: bordaInput, width: 1.5),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: bordaInput),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: primaria, width: 2),
        ),
        filled: true,
        fillColor: card,
      ),
    );
  }
}
