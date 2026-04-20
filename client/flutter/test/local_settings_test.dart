import 'package:application/src/features/settings/data/local_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<LocalSettings> createSettings([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return LocalSettings(prefs);
  }

  test('falls back to signaling host for generated STUN config', () async {
    final settings = await createSettings();

    expect(
      settings.resolveIceServersForSignalingDomain(
        'https://signal.example.com',
      ),
      [
        {'urls': 'stun:signal.example.com:3478'},
      ],
    );
  });

  test('uses dedicated ICE host when configured', () async {
    final settings = await createSettings();
    await settings.setIceHost('198.51.100.10');

    expect(
      settings.resolveIceServersForSignalingDomain(
        'https://signal.example.com',
      ),
      [
        {'urls': 'stun:198.51.100.10:3478'},
      ],
    );
  });

  test('preserves explicit port on dedicated ICE host', () async {
    final settings = await createSettings();
    await settings.setIceHost('stun.example.com:5349');

    expect(
      settings.defaultIceServersJsonForSignalingDomain(
        'https://signal.example.com',
      ),
      '[{"urls":"stun:stun.example.com:5349"}]',
    );
  });

  test('custom ICE JSON overrides generated ICE host', () async {
    final settings = await createSettings();
    await settings.setIceHost('198.51.100.10');
    await settings.setIceServersJson(
      '[{"urls":"stun:custom.example.com:3478"}]',
    );

    expect(
      settings.resolveIceServersForSignalingDomain(
        'https://signal.example.com',
      ),
      [
        {'urls': 'stun:custom.example.com:3478'},
      ],
    );
  });
}
