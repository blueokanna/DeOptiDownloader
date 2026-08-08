import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_downloader/src/app/app.dart';
import 'package:scan_downloader/src/rust/api/transfer.dart';
import 'package:scan_downloader/src/rust/frb_generated.dart';

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  test('Rust self-test passes on host', () {
    final ok = runSelfTest();
    expect(ok, isTrue);
  });

  test('Frame size helpers are sane', () {
    final options = frameSizeOptions();
    expect(options, isNotEmpty);
    expect(options.last, lessThanOrEqualTo(2953));
    final supported = encryptionSupported();
    expect(supported, isA<bool>());
    final max = maxFileBytes();
    expect(max, 64 * 1024 * 1024);
  });

  test('Session manifest round-trips through the bridge', () {
    final packed = packFileFfi(
      name: 'manifest.txt',
      mimeType: 'text/plain',
      bytes: Uint8List.fromList(utf8.encode('hello over light')),
    );
    final session = senderCreate(
      container: packed.container,
      frameBytes: 1465,
      sessionId: 0x0cd1,
    );

    // Raw wire bytes: magic-prefixed rustbinary payload.
    final bytes = sessionManifestBytes(session: session);
    expect(bytes.length, greaterThan(4));
    expect(bytes.sublist(0, 4), [0x44, 0x4F, 0x54, 0x4D]); // "DOTM"

    // Decoding yields the file metadata used for the transfer preview.
    final info = decodeManifestFfi(bytes: bytes);
    expect(info, isNotNull);
    expect(info!.fileName, 'manifest.txt');
    expect(info.mimeType, 'text/plain');
    expect(info.sessionId, 0x0cd1);
    expect(info.frameBytes, 1465);
    expect(info.k, greaterThan(0));
    expect(info.totalLen, packed.container.length);

    // The QR variant renders a non-empty matrix.
    final qr = sessionManifestQr(session: session);
    expect(qr.width, greaterThan(0));
    expect(qr.cells.length, qr.width * qr.height);

    // A fountain frame is not mistaken for a manifest.
    expect(decodeManifestFfi(bytes: [0xD1, 0x0F, 0x00, 0x00, 0x00]), isNull);
  });

  testWidgets('Home page renders', (tester) async {
    await tester.pumpWidget(const DeOptiApp());
    await tester.pump();
    expect(find.text('DeOptiDownloader'), findsOneWidget);
    // Both mode cards are present.
    expect(find.byIcon(Icons.send_outlined), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
  });
}
