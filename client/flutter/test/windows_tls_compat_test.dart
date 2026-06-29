import 'package:application/src/features/network/data/windows_tls_compat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled ISRG Root X1 PEM is a valid trusted certificate', () {
    // Throws TlsException/FormatException if the embedded PEM is corrupt.
    expect(createSecurityContextWithBundledRoots(), isNotNull);
  });
}
