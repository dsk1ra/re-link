import 'package:application/src/features/pairing/domain/pairing_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats SAS into a stable 9-digit verification code', () {
    expect(
      formatPairingCode(
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      ),
      '999 896 491',
    );
  });

  test('pads shorter SAS prefixes when rendering the verification code', () {
    expect(formatPairingCode('0000000a'), '000 000 010');
  });

  test('falls back to grouped uppercase text for invalid hex input', () {
    expect(formatPairingCode('zz99dead'), 'ZZ99 DEAD');
  });

  test('returns null when no SAS is available', () {
    expect(formatPairingCode(null), isNull);
    expect(formatPairingCode('  '), isNull);
  });
}
