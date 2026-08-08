import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scan_downloader/main.dart' as app;
import 'package:scan_downloader/src/rust/api/transfer.dart';
import 'package:scan_downloader/src/rust/frb_generated.dart';

/// End-to-end integration test against the real Rust core:
/// 1. the in-process self-test (pack → send → receive → unpack),
/// 2. a full bridge round trip (pack → session → frame → QR matrix),
/// 3. the app boots and the home page renders.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets('Rust self-test passes', (WidgetTester tester) async {
    final ok = runSelfTest();
    expect(ok, isTrue);
  });

  testWidgets('Bridge round trip produces a valid QR matrix', (
    WidgetTester tester,
  ) async {
    final packed = packFileFfi(
      name: 'it.bin',
      mimeType: 'application/octet-stream',
      bytes: List<int>.generate(4096, (i) => i % 251),
    );
    expect(packed.container, isNotEmpty);

    final session = senderCreate(
      container: packed.container,
      frameBytes: 1000,
      sessionId: 0x0c_d1,
    );
    final info = senderInfo(session: session);
    expect(info.k, greaterThan(0));
    expect(info.qrVersion, inInclusiveRange(1, 40));

    final frame = senderNextQr(session: session);
    expect(frame.frame.bytes.length, 1000);
    expect(frame.qr.width * frame.qr.height, frame.qr.cells.length);
    expect(frame.qr.width, greaterThanOrEqualTo(21));

    // Every emitted frame carries the stream identity in its header.
    final frame2 = senderNextQr(session: session);
    expect(frame2.frame.seq, greaterThan(frame.frame.seq));
  });

  testWidgets('App boots and shows the home page', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('DeOptiDownloader'), findsOneWidget);
  });
}
