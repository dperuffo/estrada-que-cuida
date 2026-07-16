// Smoke test básico — só confirma que o app sobe sem lançar exceção até
// a tela de Login (sem sessão, é a rota inicial esperada).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:estrada_que_cuida/main.dart';

void main() {
  testWidgets('App sobe e mostra a tela de login sem sessão', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: EstradaQueCuidaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Estrada que Cuida'), findsWidgets);
    expect(find.text('Receber código por SMS'), findsOneWidget);
  });
}
