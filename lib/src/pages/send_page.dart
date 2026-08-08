import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/api/transfer.dart';
import '../rust/api/types.dart';
import '../app/app.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../core/qr/qr_display.dart';
import '../core/services/file_service.dart';
import '../core/transfer/payload.dart';
import '../core/transfer/sender_controller.dart';
import '../core/util/format.dart';
import '../core/util/screen_keep.dart';
import '../l10n/strings.dart';

class SendPage extends StatefulWidget {
  const SendPage({super.key});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final FileService _files = FileService.create();
  final TextEditingController _snippet = TextEditingController();

  bool _snippetMode = false;
  PickedPayload? _payload;
  bool _busy = false;
  String? _error;

  // Settings.
  bool _encrypt = false;
  bool _encryptionSupported = false;
  final TextEditingController _password = TextEditingController();
  int _fps = 24;
  int _frameBytes = 2953;
  List<int> _frameOptions = const [];
  final bool _darkOnLight = true;

  // Live session.
  SenderController? _controller;
  SenderInfo? _info;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final options = frameSizeOptions();
    final supported = encryptionSupported();
    if (!mounted) {
      return;
    }
    setState(() {
      _frameOptions = options;
      if (_frameOptions.isNotEmpty) {
        _frameBytes = _frameOptions.last;
      }
      _encryptionSupported = supported;
    });
  }

  bool get _streaming => _controller != null && _controller!.running;

  @override
  void dispose() {
    ScreenKeep.off();
    _controller?.dispose();
    _snippet.dispose();
    _password.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Payload selection
  // -------------------------------------------------------------------------

  Future<void> _pickFile() async {
    setState(() => _error = null);
    final picked = await _files.pickFile();
    if (picked == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final maxBytes = maxFileBytes();
    if (picked.length > maxBytes) {
      setState(() {
        _error = stringsOf(context).fileTooLarge;
      });
      return;
    }
    setState(() {
      _payload = picked;
      _snippetMode = false;
    });
  }

  Future<void> _applySnippet() async {
    final text = _snippet.text.trim();
    if (text.isEmpty) {
      setState(() => _error = stringsOf(context).snippetEmpty);
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode(text));
    setState(() {
      _payload = PickedPayload(
        name: 'snippet.txt',
        mimeType: 'text/plain',
        bytes: bytes,
        isSnippet: true,
      );
      _snippetMode = true;
      _error = null;
    });
  }

  // -------------------------------------------------------------------------
  // Start / stop
  // -------------------------------------------------------------------------

  Future<void> _start() async {
    final payload = _payload;
    if (payload == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final packed = _encrypt && _encryptionSupported
          ? packFileEncryptedFfi(
              name: payload.name,
              mimeType: payload.mimeType,
              bytes: payload.bytes,
              password: _password.text,
            )
          : packFileFfi(
              name: payload.name,
              mimeType: payload.mimeType,
              bytes: payload.bytes,
            );
      final session = senderCreate(
        container: packed.container,
        frameBytes: _frameBytes,
        sessionId: null,
      );
      final info = senderInfo(session: session);
      final controller = SenderController(session: session, info: info)
        ..setFps(_fps);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _info = info;
        _controller = controller;
      });
      // First show the session-manifest QR so the receiver can preview the
      // transfer; the fountain stream starts automatically moments later.
      final setupQr = sessionManifestQr(session: session);
      controller.startWithSetup(setupQr);
      // Best-effort keep-screen-on; never blocks or aborts the transfer.
      unawaited(ScreenKeep.on());
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _stop() {
    _controller?.stop();
    ScreenKeep.off();
    setState(() {
      _controller = null;
      _info = null;
    });
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = stringsOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.sendTitle)),
      body: AnimatedSwitcher(
        duration: Motion.medium,
        switchInCurve: Motion.emphasized,
        switchOutCurve: Motion.standard,
        child: _streaming ? _buildStreaming(s) : _buildSetup(s),
      ),
    );
  }

  // --- Setup view ----------------------------------------------------------

  Widget _buildSetup(Strings s) {
    return ResponsiveBox(
      child: ListView(
        padding: Responsive.paddingOf(context),
        children: [
          _buildPayloadSection(s),
          const SizedBox(height: 16),
          _buildSettingsSection(s),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: (_payload == null || _busy) ? null : _start,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(s.startStream),
          ),
        ],
      ),
    );
  }

  Widget _buildPayloadSection(Strings s) {
    final payload = _payload;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (payload != null) ...[
              Row(
                children: [
                  const Icon(Icons.description_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(payload.name, style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          '${s.fileType}: ${payload.mimeType}  ·  ${formatBytes(payload.length)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: s.pickFile,
                    onPressed: _pickFile,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const Divider(height: 20),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(s.pickFile),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showSnippetDialog(s),
                    icon: const Icon(Icons.notes),
                    label: Text(s.pasteSnippet),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSnippetDialog(Strings s) async {
    _snippet.text = _snippetMode ? _snippet.text : '';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.pasteSnippet),
        content: TextField(
          controller: _snippet,
          maxLines: 8,
          maxLength: 100000,
          decoration: InputDecoration(hintText: s.snippetHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _applySnippet();
            },
            child: Text(s.confirm),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(Strings s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.settings, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _fps,
              decoration: InputDecoration(
                labelText: s.framesPerSecond,
                prefixIcon: const Icon(Icons.speed),
                border: const OutlineInputBorder(),
              ),
              items: const [10, 15, 20, 24, 30, 60]
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v fps')))
                  .toList(),
              onChanged: (v) => setState(() => _fps = v ?? 24),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _frameBytes,
              decoration: InputDecoration(
                labelText: s.frameSize,
                prefixIcon: const Icon(Icons.aspect_ratio),
                border: const OutlineInputBorder(),
              ),
              items: _frameOptions
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v B')))
                  .toList(),
              onChanged: (v) => setState(() => _frameBytes = v ?? _frameBytes),
            ),
            const SizedBox(height: 6),
            Text(s.frameSizeHint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (_encryptionSupported)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.encryption),
                subtitle: Text(s.encryptionHint),
                value: _encrypt,
                onChanged: (v) => setState(() => _encrypt = v),
              ),
            if (_encrypt && _encryptionSupported)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: s.password,
                    hintText: s.passwordHint,
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- Streaming view ------------------------------------------------------

  Widget _buildStreaming(Strings s) {
    final controller = _controller!;
    final info = _info!;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: QrDisplay(
              matrix: controller.matrix,
              dark: _darkOnLight ? Colors.black : Colors.white,
              light: _darkOnLight ? Colors.white : Colors.black,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AnimatedSwitcher(
            duration: Motion.short,
            child: controller.inSetup
                ? Chip(
                    key: const ValueKey('setup'),
                    avatar: const Icon(Icons.info_outline, size: 18),
                    label: Text(
                      '${s.manifestSetup} · ${s.manifestScanHint}',
                      textAlign: TextAlign.center,
                    ),
                  )
                : Text(
                    s.waitingForReceiver,
                    key: const ValueKey('streaming'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<SenderStats>(
          valueListenable: controller.stats,
          builder: (context, stats, _) {
            return _StatusChip(
              fps: stats.measuredFps,
              frames: stats.framesSent,
              k: info.k,
              session: info.sessionId,
              qrVersion: info.qrVersion,
              blockLen: info.blockLen,
              elapsed: stats.elapsed,
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: controller.paused ? s.resume : s.pause,
                icon: Icon(controller.paused ? Icons.play_arrow : Icons.pause),
                onPressed: () {
                  if (controller.paused) {
                    controller.resume();
                  } else {
                    controller.pause();
                  }
                },
              ),
              const SizedBox(width: 16),
              IconButton.filled(
                tooltip: s.stop,
                icon: const Icon(Icons.stop),
                onPressed: _stop,
              ),
              const SizedBox(width: 16),
              IconButton.outlined(
                tooltip: s.share,
                icon: const Icon(Icons.share),
                onPressed: () => _shareSession(s),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _shareSession(Strings s) async {
    final info = _info;
    if (info == null) {
      return;
    }
    final text = '${s.appName}\n'
        '${s.session}: ${info.sessionId}\n'
        '${s.sourceBlocks}: ${info.k}\n'
        '${s.blockSize}: ${info.blockLen} B\n'
        '${s.qrVersion}: ${info.qrVersion}';
    await _files.shareText(text);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.fps,
    required this.frames,
    required this.k,
    required this.session,
    required this.qrVersion,
    required this.blockLen,
    required this.elapsed,
  });

  final double fps;
  final int frames;
  final int k;
  final int session;
  final int qrVersion;
  final int blockLen;
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final s = stringsOf(context);
    String fmtFps(double v) => v.toStringAsFixed(1);
    final rows = <Widget>[
      _cell(s.framesPerSecond, '${fmtFps(fps)} fps', context),
      _cell(s.framesSent, '$frames', context),
      _cell(s.sourceBlocks, '$k', context),
      _cell(s.session, '$session', context),
      _cell(s.qrVersion, 'v$qrVersion', context),
      _cell(s.blockSize, '$blockLen B', context),
      _cell(s.elapsed, formatElapsed(elapsed), context),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: rows,
    );
  }

  Widget _cell(String label, String value, BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleSmall),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
