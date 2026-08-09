import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/api/transfer.dart';
import '../rust/api/types.dart';
import '../app/app.dart';
import '../app/responsive.dart';
import '../core/camera/camera_source_factory.dart';
import '../core/services/file_service.dart';
import '../core/services/judge_keys.dart';
import '../core/transfer/receiver_controller.dart';
import '../core/util/format.dart';
import '../core/util/screen_keep.dart';
import '../../l10n/generated/app_localizations.dart';

class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  final FileService _files = FileService.create();
  ReceiverController? _controller;
  bool _initializing = true;
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final session = receiverCreate();
      final controller = ReceiverController(session: session);
      final camera = createCameraSource();
      await controller.start(camera);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
      // Best-effort keep-screen-on; never blocks or aborts receiving.
      unawaited(ScreenKeep.on());
    } catch (e) {
      if (!mounted) {
        return;
      }
      final msg = e.toString();
      setState(() {
        _initializing = false;
        _fatalError = msg.contains('camera') || msg.contains('permission')
            ? msg
            : _describeCameraError(msg);
      });
    }
  }

  String _describeCameraError(String raw) {
    final s = AppLocalizations.of(context);
    final lower = raw.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return s.cameraPermissionDenied;
    }
    return s.cameraUnavailable;
  }

  @override
  void dispose() {
    ScreenKeep.off();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.receiveTitle)),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : _fatalError != null
              ? _buildError(s)
              : _buildLive(s),
    );
  }

  Widget _buildError(AppLocalizations s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(_fatalError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _initializing = true;
                  _fatalError = null;
                });
                _init();
              },
              icon: const Icon(Icons.refresh),
              label: Text(s.receiveAgain),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLive(AppLocalizations s) {
    final controller = _controller!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Password gate.
        if (controller.passwordRequired) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPasswordDialog(s);
          });
        }
        // Judge-recoverable gate.
        if (controller.jrcRequired) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showJudgeKeyDialog(s);
          });
        }
        // Completion view.
        if (controller.completed != null) {
          return _buildCompleted(s, controller.completed!);
        }
        // Live camera + progress.
        return Stack(
          fit: StackFit.expand,
          children: [
            controller.source?.buildPreview() ?? const ColoredBox(color: Colors.black),
            _buildOverlay(s, controller),
          ],
        );
      },
    );
  }

  Widget _buildOverlay(AppLocalizations s, ReceiverController c) {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent, Colors.black87],
          ),
        ),
        child: Column(
          children: [
            const Spacer(),
            if (c.showNoSignal) _buildNoSignalCard(s),
            const SizedBox(height: 12),
            _buildProgress(s, c),
            const SizedBox(height: 12),
            Text(s.pointCamera,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSignalCard(AppLocalizations s) {
    return Card(
      color: Colors.black.withValues(alpha: 0.75),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.noSignalTitle,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(s.noSignalBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(AppLocalizations s, ReceiverController c) {
    final k = c.outcome.k;
    final total = k == null ? null : (k * 1.15).ceil();
    final lockLine = k == null
        ? s.waitingForSender
        : '${s.receiverLocked} #${c.outcome.sessionId} · ${s.transferMode} ${c.outcome.mode}';
    final m = c.manifest;
    return Card(
      color: Colors.black.withValues(alpha: 0.7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m != null) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.article_outlined,
                      color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${s.manifestIncoming}: ${m.fileName} · '
                      '${formatBytes(m.totalLen)} · ${s.sourceBlocks} ${m.k}'
                      '${m.encrypted ? ' · ${s.manifestEncrypted}' : ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text(lockLine,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(height: 8),
            SizedBox(
              width: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: c.progress,
                  minHeight: 8,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              total == null
                  ? '${s.progressFrames}: ${c.outcome.collected}'
                  : '${s.progressFrames}: ${c.outcome.collected} / $total  (${(c.progress * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (c.decodeFps > 0)
              Text('${c.decodeFps.toStringAsFixed(1)} fps',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // --- Completion ----------------------------------------------------------

  Widget _buildCompleted(AppLocalizations s, OpticalFileData file) {
    final isText = file.mimeType.startsWith('text/') ||
        file.mimeType == 'application/json' ||
        file.mimeType == 'application/xml';
    return SafeArea(
      child: ResponsiveBox(
        child: ListView(
          padding: Responsive.paddingOf(context),
          children: [
            const SizedBox(height: 12),
            Icon(Icons.check_circle,
                size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(s.complete,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv(s.fileName, file.name),
                    _kv(s.fileSize, formatBytes(file.bytes.length)),
                    _kv(s.fileType, file.mimeType),
                    if (file.encrypted) _kv(s.encryption, 'XChaCha20-Poly1305'),
                    _kv('SHA-256', _shortDigest(file.digest)),
                  ],
                ),
              ),
            ),
            if (isText) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _decodeText(file),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _save(file),
                    icon: const Icon(Icons.download),
                    label: Text(s.save),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _files.shareFile(file),
                    icon: const Icon(Icons.share),
                    label: Text(s.share),
                  ),
                ),
              ],
            ),
            if (isText) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _copyText(file),
                icon: const Icon(Icons.copy),
                label: Text(s.copy),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _receiveAgain,
              icon: const Icon(Icons.replay),
              label: Text(s.receiveAgain),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.bodyMedium,
                softWrap: true),
          ),
        ],
      ),
    );
  }

  Future<void> _save(OpticalFileData file) async {
    try {
      await _files.saveFile(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _copyText(OpticalFileData file) async {
    final text = _decodeText(file);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).copied)));
    }
  }

  String _decodeText(OpticalFileData file) {
    try {
      return utf8.decode(file.bytes, allowMalformed: true);
    } catch (_) {
      return file.bytes.isNotEmpty ? '…' : '';
    }
  }

  String _shortDigest(List<int> digest) {
    final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (hex.length <= 16) {
      return hex;
    }
    return '${hex.substring(0, 8)}…${hex.substring(hex.length - 8)}';
  }

  Future<void> _receiveAgain() async {
    await _controller?.reset();
    // Re-bind the camera source.
    final controller = _controller;
    if (controller != null) {
      try {
        final camera = createCameraSource();
        await controller.start(camera);
      } catch (e) {
        if (mounted) {
          setState(() => _fatalError = _describeCameraError(e.toString()));
        }
      }
    }
  }

  Future<void> _showPasswordDialog(AppLocalizations s) async {
    if (_passwordDialogOpen) {
      return;
    }
    _passwordDialogOpen = true;
    final controller = _controller;
    if (controller == null) {
      _passwordDialogOpen = false;
      return;
    }
    final input = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(s.enterPassword),
        content: TextField(
          controller: input,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: s.password,
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    _passwordDialogOpen = false;
    if (result == null) {
      // Cancelled: keep waiting for frames (or let user retry).
      return;
    }
    final ok = await controller.submitPassword(result);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.wrongPassword)));
    }
  }

  /// Judge-recoverable gate: prompts for the judge secret key (hex), with a
  /// one-tap "use saved key" shortcut backed by the settings page.
  Future<void> _showJudgeKeyDialog(AppLocalizations s) async {
    if (_jrcDialogOpen) {
      return;
    }
    _jrcDialogOpen = true;
    final controller = _controller;
    if (controller == null) {
      _jrcDialogOpen = false;
      return;
    }
    final input = TextEditingController();
    final saved = appSettingsOf(context).judgeSecretKey;

    String? submitted;
    if (saved != null) {
      // Offer the saved judge key as a quick action.
      submitted = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(s.enterJudgeKey),
          content: Text(s.enterJudgeKeyBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(saved),
              icon: const Icon(Icons.key_outlined),
              label: Text(s.judgeSecretKey),
            ),
          ],
        ),
      );
      if (!mounted) {
        return;
      }
    }
    submitted ??= await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(s.enterJudgeKey),
          content: TextField(
            controller: input,
            obscureText: true,
            autofocus: true,
            maxLength: 64,
            decoration: InputDecoration(
              labelText: s.judgeSecretKey,
              hintText: s.judgeSecretKeyHint,
              prefixIcon: const Icon(Icons.key_outlined),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(input.text.trim()),
              child: Text(s.confirm),
            ),
          ],
        ),
      );
    if (!mounted) {
      return;
    }
    _jrcDialogOpen = false;
    if (submitted == null || submitted.isEmpty) {
      return;
    }
    final key = hexToBytes(submitted);
    if (key == null || key.length != 32) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.judgeSecretKeyInvalid)));
      }
      return;
    }
    final ok = await controller.submitJudgeKey(key);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.wrongJudgeKey)));
    }
  }

  bool _passwordDialogOpen = false;
  bool _jrcDialogOpen = false;
}
