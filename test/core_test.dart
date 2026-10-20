import 'package:flutter_test/flutter_test.dart';
import '../tool/core_checks.dart' as checks;

void main() {
  test(
    'core safety, parsing, retry and cancellation contracts',
    checks.runCoreChecks,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
