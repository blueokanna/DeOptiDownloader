import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_downloader/src/app/app.dart';
import 'package:scan_downloader/src/app/settings_controller.dart';
import 'package:scan_downloader/src/app/theme/app_themes.dart';
import 'package:scan_downloader/src/app/theme/wallpaper.dart';
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

  test('JRC self-test passes on host (0.1.2 judge-recoverable)', () {
    final ok = jrcSelfTest();
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

  test(
    'every ColorSpec and ColorStyle combination builds in light and dark',
    () {
      for (final spec in ColorSpec.values) {
        for (final style in ColorStyle.values) {
          final light = buildTheme(spec, style, brightness: Brightness.light);
          final dark = buildTheme(spec, style, brightness: Brightness.dark);
          expect(light.colorScheme.brightness, Brightness.light);
          expect(dark.colorScheme.brightness, Brightness.dark);
          expect(light.useMaterial3, isTrue);
          expect(dark.useMaterial3, isTrue);
        }
      }

      final amoled = buildTheme(
        ColorSpec.indigo,
        ColorStyle.expressive,
        brightness: Brightness.dark,
        amoled: true,
      );
      expect(amoled.colorScheme.surface, Colors.black);
      expect(amoled.scaffoldBackgroundColor, Colors.black);
    },
  );

  test('wallpaper blur updates preserve the selected background', () {
    final builtin = const WallpaperSpec.builtin('aurora').copyWith(blur: 12);
    expect(builtin.kind, WallpaperKind.builtin);
    expect(builtin.assetId, 'aurora');
    expect(builtin.effectiveBlur, 12);

    final custom = const WallpaperSpec.custom('custom.png').copyWith(blur: 30);
    expect(custom.kind, WallpaperKind.custom);
    expect(custom.imagePath, 'custom.png');
    expect(custom.effectiveBlur, 24);
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

  test('JRC keygen → pack → judge-recover round-trips through the bridge', () {
    if (!encryptionSupported()) {
      return; // Web build without the encryption feature.
    }
    final pair = jrcKeygenFfi();
    expect(pair.publicKey.length, 32);
    expect(pair.secretKey.length, 32);

    final payload = Uint8List.fromList(utf8.encode('judge says: hello'));
    final packed = packFileJrcFfi(
      name: 'judge.txt',
      mimeType: 'text/plain',
      bytes: payload,
      judgePublicKey: pair.publicKey,
    );
    expect(packed.envelope, isNotEmpty);
    // The envelope is a JRC transcript, not a DCF3 container.
    expect(packed.envelope.sublist(0, 4), [
      0x4A,
      0x52,
      0x43,
      0x01,
    ]); // "JRC\x01"

    final file = unpackFileJrcFfi(
      envelope: packed.envelope,
      judgeSecretKey: pair.secretKey,
    );
    expect(file.name, 'judge.txt');
    expect(file.bytes, payload);
  });

  testWidgets('Home page renders', (tester) async {
    final settings = AppSettings.create();
    await tester.pumpWidget(DeOptiApp(settings: settings));
    await tester.pump();
    expect(find.text('DeOptiDownloader'), findsOneWidget);
    // Both mode cards are present.
    expect(find.byIcon(Icons.send_outlined), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
  });

  testWidgets('settings page has no narrow-screen layout overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settings = AppSettings.create();
    await tester.pumpWidget(DeOptiApp(settings: settings));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.fling(find.byType(ListView), const Offset(0, -1200), 1200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
