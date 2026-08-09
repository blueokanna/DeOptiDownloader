import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/app.dart';
import '../app/responsive.dart';
import '../app/settings_controller.dart';
import '../app/theme/app_themes.dart';
import '../app/theme/wallpaper.dart';
import '../../l10n/generated/app_localizations.dart';
import '../core/services/judge_keys.dart';
import '../rust/api/transfer.dart';

/// Application settings: appearance (theme + mode + language), wallpaper
/// (none / builtin / custom + blur) and advanced (judge key, defaults).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _pickingCustom = false;
  bool _initialized = false;
  final TextEditingController _judgeKeyController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _judgeKeyController.text = appSettingsOf(context).judgeSecretKey ?? '';
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _judgeKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final settings = appSettingsOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ResponsiveBox(
        child: ListView(
          padding: Responsive.paddingOf(context),
          children: [
            _SectionTitle(icon: Icons.palette_outlined, label: s.appearance),
            _buildThemeMode(s, settings),
            const SizedBox(height: 8),
            _buildThemePicker(s, settings),
            const SizedBox(height: 8),
            _buildLanguage(s, settings),
            const SizedBox(height: 20),
            _SectionTitle(icon: Icons.wallpaper_outlined, label: s.wallpaper),
            _buildWallpaper(s, settings),
            const SizedBox(height: 20),
            _SectionTitle(icon: Icons.tune, label: s.advanced),
            _buildJudgeKey(s, settings),
            const SizedBox(height: 8),
            _buildRestoreDefaults(s, settings),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // --- Appearance ----------------------------------------------------------

  Widget _buildThemeMode(AppLocalizations s, AppSettings settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.themeMode, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            SegmentedButton<AppThemeMode>(
              segments: [
                ButtonSegment(
                  value: AppThemeMode.system,
                  label: Text(s.themeModeSystem),
                  icon: const Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: AppThemeMode.light,
                  label: Text(s.themeModeLight),
                  icon: const Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text(s.themeModeDark),
                  icon: const Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (sel) => settings.setThemeMode(sel.first),
            ),
            const SizedBox(height: 12),
            Text(
              s.themeHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemePicker(AppLocalizations s, AppSettings settings) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.colorSpec, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final spec in ColorSpec.values)
                  _ColorSpecTile(
                    colorSpec: spec,
                    colorStyle: settings.colorStyle,
                    brightness: Theme.of(context).brightness,
                    selected: settings.colorSpec == spec,
                    label: _colorSpecLabel(s, spec),
                    onTap: () => settings.setColorSpec(spec),
                  ),
              ],
            ),
            const Divider(height: 28),
            DropdownButtonFormField<ColorStyle>(
              initialValue: settings.colorStyle,
              decoration: InputDecoration(
                labelText: s.colorStyle,
                prefixIcon: const Icon(Icons.auto_awesome_outlined),
              ),
              items: [
                for (final style in ColorStyle.values)
                  DropdownMenuItem(
                    value: style,
                    child: Text(_colorStyleLabel(s, style)),
                  ),
              ],
              onChanged: (style) {
                if (style != null) {
                  settings.setColorStyle(style);
                }
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.contrast_outlined),
              title: Text(s.themeAmoled),
              subtitle: Text(s.themeAmoledHint),
              value: settings.amoled,
              onChanged: settings.setAmoled,
            ),
            Text(
              s.themeHint,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _colorSpecLabel(AppLocalizations s, ColorSpec spec) => switch (spec) {
    ColorSpec.indigo => s.colorSpecIndigo,
    ColorSpec.cyan => s.colorSpecCyan,
    ColorSpec.emerald => s.colorSpecEmerald,
    ColorSpec.violet => s.colorSpecViolet,
    ColorSpec.sunset => s.colorSpecSunset,
    ColorSpec.neutral => s.colorSpecNeutral,
  };

  String _colorStyleLabel(AppLocalizations s, ColorStyle style) =>
      switch (style) {
        ColorStyle.tonalSpot => s.colorStyleTonalSpot,
        ColorStyle.expressive => s.colorStyleExpressive,
        ColorStyle.fidelity => s.colorStyleFidelity,
        ColorStyle.vibrant => s.colorStyleVibrant,
        ColorStyle.neutral => s.colorStyleNeutral,
        ColorStyle.monochrome => s.colorStyleMonochrome,
      };

  Widget _buildLanguage(AppLocalizations s, AppSettings settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.translate),
                const SizedBox(width: 12),
                Text(s.language),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: settings.languageCode,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.language),
              items: [
                DropdownMenuItem(value: null, child: Text(s.languageSystem)),
                const DropdownMenuItem(value: 'en', child: Text('English')),
                const DropdownMenuItem(value: 'zh', child: Text('中文')),
              ],
              onChanged: (v) => settings.setLanguage(v),
            ),
          ],
        ),
      ),
    );
  }

  // --- Wallpaper -----------------------------------------------------------

  Widget _buildWallpaper(AppLocalizations s, AppSettings settings) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.wallpaper, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            // None option.
            RadioGroup<WallpaperKind>(
              groupValue: settings.wallpaper.kind,
              onChanged: (v) {
                if (v != null && v != settings.wallpaper.kind) {
                  settings.setWallpaper(const WallpaperSpec.none());
                }
              },
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.block_outlined),
                title: Text(s.wallpaperNone),
                subtitle: Text(s.wallpaperNoneHint),
                trailing: const Radio<WallpaperKind>(value: WallpaperKind.none),
                onTap: () => settings.setWallpaper(const WallpaperSpec.none()),
              ),
            ),
            const Divider(height: 1),
            // Builtin wallpapers.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                s.wallpaperBuiltin,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final id in kBuiltinWallpapers)
                  _WallpaperTile(
                    assetId: id,
                    selected:
                        settings.wallpaper.kind == WallpaperKind.builtin &&
                        settings.wallpaper.assetId == id,
                    onTap: () =>
                        settings.setWallpaper(WallpaperSpec.builtin(id)),
                  ),
              ],
            ),
            // Custom image.
            const Divider(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: Text(s.wallpaperCustom),
              subtitle: Text(s.wallpaperCustomHint),
              trailing: _pickingCustom
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: s.wallpaperPick,
                      icon: const Icon(Icons.folder_open),
                      onPressed: () => _pickCustomWallpaper(s, settings),
                    ),
              onTap: () => _pickCustomWallpaper(s, settings),
            ),
            if (settings.wallpaper.kind == WallpaperKind.custom) ...[
              OutlinedButton.icon(
                onPressed: () => settings.removeCustomWallpaper(),
                icon: const Icon(Icons.delete_outline),
                label: Text(s.wallpaperRemove),
              ),
            ],
            // Blur slider (only meaningful when a wallpaper is active).
            if (settings.wallpaper.isActive) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.blur_on, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.wallpaperBlur,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          s.wallpaperBlurHint,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    settings.wallpaper.blur.toStringAsFixed(0),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              Slider(
                value: settings.wallpaper.blur,
                min: 0,
                max: 24,
                divisions: 24,
                label: settings.wallpaper.blur.toStringAsFixed(0),
                onChanged: (v) => settings.setWallpaperBlur(v),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomWallpaper(
    AppLocalizations s,
    AppSettings settings,
  ) async {
    if (_pickingCustom) {
      return;
    }
    setState(() => _pickingCustom = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      final file = result?.files.single;
      if (file == null) {
        return;
      }
      final bytes = file.bytes ?? (await file.xFile.readAsBytes());
      if (bytes.isEmpty) {
        return;
      }
      await settings.setCustomWallpaper(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _pickingCustom = false);
      }
    }
  }

  // --- Advanced ------------------------------------------------------------

  Widget _buildJudgeKey(AppLocalizations s, AppSettings settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.judgeSecretKey,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              s.judgeSecretKeyHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('judge-secret-key'),
              controller: _judgeKeyController,
              obscureText: true,
              maxLength: 64,
              decoration: InputDecoration(
                labelText: s.judgeSecretKey,
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  tooltip: s.generateJudgeKey,
                  icon: const Icon(Icons.casino_outlined),
                  onPressed: () => _generateJudgeKey(s, settings),
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                final hex = v.trim();
                // Only persist a complete 64-char key; partial input is kept
                // in the field but not saved.
                settings.setJudgeSecretKey(hex.length == 64 ? hex : null);
              },
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _generateJudgeKey(s, settings),
              icon: const Icon(Icons.casino_outlined),
              label: Text(s.generateJudgeKey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateJudgeKey(
    AppLocalizations s,
    AppSettings settings,
  ) async {
    try {
      final pair = jrcKeygenFfi();
      final hex = bytesToHex(pair.secretKey);
      settings.setJudgeSecretKey(hex);
      _judgeKeyController.text = hex;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.judgeKeyCopied)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _buildRestoreDefaults(AppLocalizations s, AppSettings settings) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => settings.restoreDefaults(),
        icon: const Icon(Icons.restart_alt),
        label: Text(s.restoreDefaults),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ColorSpecTile extends StatelessWidget {
  const _ColorSpecTile({
    required this.colorSpec,
    required this.colorStyle,
    required this.brightness,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final ColorSpec colorSpec;
  final ColorStyle colorStyle;
  final Brightness brightness;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = buildTheme(
      colorSpec,
      colorStyle,
      brightness: brightness,
    ).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Shape.md),
      child: AnimatedContainer(
        duration: Motion.short,
        width: 96,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Shape.md),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(Shape.sm),
              ),
              child: Icon(Icons.palette_outlined, color: scheme.primary),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({
    required this.assetId,
    required this.selected,
    required this.onTap,
  });

  final String assetId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Shape.md),
      child: AnimatedContainer(
        duration: Motion.short,
        width: 84,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Shape.md),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
          image: DecorationImage(
            image: AssetImage('assets/images/wallpapers/$assetId.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: selected
            ? Center(
                child: Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              )
            : null,
      ),
    );
  }
}
