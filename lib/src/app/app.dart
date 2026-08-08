import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../pages/home_page.dart';
import 'theme.dart';

class DeOptiApp extends StatelessWidget {
  const DeOptiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeOptiDownloader',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomePage(),
      builder: (context, child) {
        // Resolve strings from the ambient locale for the whole tree.
        final strings = Strings.of(context);
        return _StringsScope(strings: strings, child: child!);
      },
    );
  }
}

/// Injects the resolved [Strings] into the widget tree.
class _StringsScope extends InheritedWidget {
  const _StringsScope({required this.strings, required super.child});

  final Strings strings;

  static Strings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_StringsScope>();
    return scope?.strings ?? Strings.en;
  }

  @override
  bool updateShouldNotify(_StringsScope oldWidget) => oldWidget.strings != strings;
}

/// Convenience accessor used by pages.
Strings stringsOf(BuildContext context) => _StringsScope.of(context);
