String? formatPairingCode(String? sasHex) {
  final normalized = sasHex?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final prefixLength = normalized.length >= 12 ? 12 : normalized.length;
  final prefix = normalized.substring(0, prefixLength);

  try {
    final value = int.parse(prefix, radix: 16) % 1000000000;
    final digits = value.toString().padLeft(9, '0');
    return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
  } catch (_) {
    final safePrefix = prefix.toUpperCase();
    return safePrefix
        .replaceAllMapped(RegExp(r'.{1,4}'), (match) => '${match.group(0)} ')
        .trim();
  }
}
