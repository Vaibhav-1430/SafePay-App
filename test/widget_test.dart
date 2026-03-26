import 'package:flutter_test/flutter_test.dart';
import 'package:safepay/utils/app_constants.dart';

void main() {
  test('currency formatter returns INR symbol', () {
    final formatted = Formatters.formatCurrency(1200);
    expect(formatted.contains('₹'), isTrue);
  });
}
