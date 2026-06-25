import 'package:application/src/features/pairing/domain/models.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/presentation/pages/connection_pairing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders wide launcher actions without layout exceptions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionPairingPage(
          signalingBaseUrl: 'http://localhost:1',
          backend: _FakeSignalingBackend(),
        ),
      ),
    );

    expect(find.text('Create connection'), findsOneWidget);
    expect(find.text('Join connection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeSignalingBackend implements SignalingBackend {
  @override
  String? get clientId => null;

  @override
  String? get displayName => null;

  @override
  bool get isRegistered => false;

  @override
  String? get sessionToken => null;

  @override
  Future<void> dispose() async {}

  @override
  Future<HeartbeatResponse?> heartbeat() async => null;

  @override
  Future<RegisterResponse> register({required String deviceLabel}) async {
    return RegisterResponse(
      clientId: 'test-client',
      sessionToken: 'test-token',
      heartbeatIntervalSecs: 30,
      displayName: deviceLabel,
    );
  }
}
