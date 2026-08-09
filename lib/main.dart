import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'src/app/app.dart';
import 'src/app/settings_controller.dart';
import 'src/rust/frb_generated.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Google Fonts are bundled in assets — never fetch from the network (works
  // offline, in China, and in CI).
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  Object? _initializationError;
  AppSettings? _settings;
  var _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    try {
      // Rust bridge first (heavy FFI init), then persisted settings, so the
      // first frame shows a themed app the moment both are ready.
      await RustLib.init();
      final settings = AppSettings.create();
      await settings.load();
      if (mounted) {
        setState(() {
          _settings = settings;
          _initialized = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _initializationError = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialized) {
      return DeOptiApp(settings: _settings!);
    }

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: _initializationError == null
              ? const CircularProgressIndicator()
              : Text('Rust initialization failed: $_initializationError'),
        ),
      ),
    );
  }
}
