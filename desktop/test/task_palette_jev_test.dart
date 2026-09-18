import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/widgets/task_palette.dart';

RouteAnswer answer(String via, double confidence) => RouteAnswer(
  agentId: 'a1',
  machineId: 'm1',
  name: 'Agent',
  confidence: confidence,
  reason: '',
  candidates: const [],
  via: via,
);

void main() {
  test('Jev results always require chooser confirmation', () {
    expect(routeNeedsConfirmation(answer('jev', 1)), isTrue);
    expect(routeNeedsConfirmation(answer('jev-fallback', 1)), isTrue);
    expect(routeNeedsConfirmation(answer('model', 0.9)), isFalse);
  });
}
