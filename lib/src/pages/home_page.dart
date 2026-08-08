import 'package:flutter/material.dart';

import '../rust/api/transfer.dart';
import '../app/app.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../app/widgets/mode_card.dart';
import '../l10n/strings.dart';
import 'receive_page.dart';
import 'send_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = stringsOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.appName),
        actions: [
          IconButton(
            tooltip: s.diagnostics,
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => _showDiagnostics(context, s),
          ),
        ],
      ),
      body: SafeArea(
        child: _HomeBody(s: s),
      ),
    );
  }

  Future<void> _showDiagnostics(BuildContext context, Strings s) async {
    bool? pass;
    String? error;
    try {
      pass = runSelfTest();
    } catch (e) {
      error = e.toString();
    }
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          pass == true ? Icons.check_circle : Icons.error_outline,
          color: pass == true
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
        title: Text(s.diagnostics),
        content: Text(
          error != null
              ? '${s.selfTestFail} $error'
              : (pass == true ? s.selfTestPass : s.selfTestFail),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.s});

  final Strings s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breakpoint = Responsive.ofContext(context);

    final hero = Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(Shape.xl),
          ),
          child: Icon(
            Icons.qr_code_2,
            size: 52,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          s.tagline,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final sendCard = ModeCard(
      icon: Icons.send_outlined,
      title: s.sendTitle,
      subtitle: s.sendSubtitle,
      color: theme.colorScheme.primary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SendPage()),
      ),
    );
    final receiveCard = ModeCard(
      icon: Icons.camera_alt_outlined,
      title: s.receiveTitle,
      subtitle: s.receiveSubtitle,
      color: theme.colorScheme.tertiary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReceivePage()),
      ),
    );

    final privacy = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: theme.colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                s.privacyNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final about = Center(
      child: Text(
        s.about,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );

    // Wide screens: two-pane mode cards side by side.
    final modes = breakpoint.isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: sendCard),
              SizedBox(width: GridSpacing.gutter(context)),
              Expanded(child: receiveCard),
            ],
          )
        : Column(
            children: [
              sendCard,
              const SizedBox(height: 16),
              receiveCard,
            ],
          );

    return _FadeIn(
      child: ResponsiveBox(
        child: ListView(
          padding: Responsive.paddingOf(context),
          children: [
            hero,
            const SizedBox(height: 28),
            modes,
            const SizedBox(height: 28),
            privacy,
            const SizedBox(height: 12),
            about,
          ],
        ),
      ),
    );
  }
}

/// One-shot entrance animation for the home body.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.long,
      curve: Motion.emphasized,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

