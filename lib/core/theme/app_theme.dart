import 'package:flutter/material.dart';

// Paleta simples pro MVP — verde-estrada como cor principal. Sem
// pretensão de identidade visual final, só o suficiente pra não ficar no
// Material padrão cinza/roxo.
class AppTheme {
  static const Color corPrincipal = Color(0xFF1B7A43);

  static ThemeData get tema {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: corPrincipal),
      scaffoldBackgroundColor: const Color(0xFFF7F7F5),
      appBarTheme: const AppBarTheme(
        backgroundColor: corPrincipal,
        foregroundColor: Colors.white,
        centerTitle: true,
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
          backgroundColor: corPrincipal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
