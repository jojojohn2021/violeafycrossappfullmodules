import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leafy_webapp/app/main_app.dart';
import 'package:leafy_webapp/providers/app_providers.dart';
import 'package:leafy_webapp/repositories/shopping_repository.dart';

void main() {
  testWidgets('Leafy app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shoppingRepositoryProvider.overrideWithValue(ShoppingRepository(firestore: null)),
        ],
        child: const LeafyMainApp(),
      ),
    );
    expect(find.byType(LeafyMainApp), findsOneWidget);
  });
}
