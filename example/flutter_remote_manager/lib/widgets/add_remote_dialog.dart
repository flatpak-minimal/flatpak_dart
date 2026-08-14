// lib/widgets/add_remote_dialog.dart
//
// Dialog for adding a Flatpak remote.
// Two modes toggled by a segmented button:
//   • Known — pick from the KnownRemotes catalog
//   • Custom — enter name + URL manually

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum _AddMode { known, custom }

/// Each entry in the known-remotes picker.
class _KnownEntry {
  final String label;
  final String suggestedName;
  final FlatpakRemoteConfig config;
  final String description;

  const _KnownEntry(
    this.label,
    this.suggestedName,
    this.config,
    this.description,
  );
}

final _knownEntries = <_KnownEntry>[
  const _KnownEntry(
    'Flathub',
    'flathub',
    KnownRemotes.flathub,
    'The main Flatpak repository — all apps.',
  ),
  const _KnownEntry(
    'Flathub Verified',
    'flathub-verified',
    KnownRemotes.flathubVerified,
    'Upstream-maintained apps only (--subset=verified).',
  ),
  const _KnownEntry(
    'Flathub FLOSS',
    'flathub-floss',
    KnownRemotes.flathubFloss,
    'Open-source apps only (--subset=floss).',
  ),
  const _KnownEntry(
    'Flathub Verified FLOSS',
    'flathub-verified_floss',
    KnownRemotes.flathubVerifiedFloss,
    'Open-source + upstream-maintained (--subset=verified_floss).',
  ),
  const _KnownEntry(
    'Flathub Beta',
    'flathub-beta',
    KnownRemotes.flathubBeta,
    'Pre-release Flathub channel.',
  ),
  const _KnownEntry(
    'Fedora',
    'fedora',
    KnownRemotes.fedora,
    'Fedora-built apps via OCI (oci+https://).',
  ),
  const _KnownEntry(
    'elementary AppCenter',
    'elementaryos',
    KnownRemotes.elementaryOs,
    'Curated apps for elementary OS.',
  ),
  const _KnownEntry(
    'PureOS',
    'PureOS',
    KnownRemotes.pureOs,
    'Purism apps (security-focused).',
  ),
  const _KnownEntry(
    'Igalia',
    'igalia',
    KnownRemotes.igalia,
    'Gobby, Linphone, WebKit SDK.',
  ),
  const _KnownEntry(
    'GNOME Nightly',
    'gnome-nightly',
    KnownRemotes.gnomeNightly,
    'Nightly GNOME apps and runtime.',
  ),
  const _KnownEntry(
    'KDE Runtime Nightly',
    'kde-runtime-nightly',
    KnownRemotes.kdeRuntimeNightly,
    'Required by KDE per-app nightly remotes.',
  ),
];

class AddRemoteDialog extends StatefulWidget {
  const AddRemoteDialog({super.key});

  @override
  State<AddRemoteDialog> createState() => _AddRemoteDialogState();
}

class _AddRemoteDialogState extends State<AddRemoteDialog> {
  _AddMode _mode = _AddMode.known;
  _KnownEntry? _selected = _knownEntries.first;

  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = _selected?.suggestedName ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _onKnownChanged(_KnownEntry? e) {
    setState(() {
      _selected = e;
      _nameCtrl.text = e?.suggestedName ?? '';
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_mode == _AddMode.known && _selected != null) {
      Navigator.of(
        context,
      ).pop((name: _nameCtrl.text.trim(), config: _selected!.config));
    } else {
      Navigator.of(context).pop((
        name: _nameCtrl.text.trim(),
        config: FlatpakRemoteConfig(url: _urlCtrl.text.trim(), gpgVerify: true),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bg1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppTheme.border, width: 0.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────
                Row(
                  children: [
                    const Icon(
                      Icons.add_circle_outline,
                      color: AppTheme.teal,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Add Remote',
                      style: AppTheme.ui(size: 15, weight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppTheme.fg2,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Mode toggle ──────────────────────────────────────────
                _ModeToggle(
                  value: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),

                const SizedBox(height: 20),

                // ── Known remote picker ──────────────────────────────────
                if (_mode == _AddMode.known) ...[
                  const _Label('Repository'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<_KnownEntry>(
                    initialValue: _selected,
                    dropdownColor: AppTheme.bg2,
                    style: AppTheme.ui(size: 13),
                    decoration: const InputDecoration(),
                    items: _knownEntries
                        .map(
                          (e) =>
                              DropdownMenuItem(value: e, child: Text(e.label)),
                        )
                        .toList(),
                    onChanged: _onKnownChanged,
                  ),
                  if (_selected != null) ...[
                    const SizedBox(height: 8),
                    _UrlChip(_selected!.config.url ?? ''),
                    const SizedBox(height: 6),
                    Text(
                      _selected!.description,
                      style: AppTheme.ui(size: 11, color: AppTheme.fg2),
                    ),
                  ],
                ],

                // ── Custom remote fields ─────────────────────────────────
                if (_mode == _AddMode.custom) ...[
                  const _Label('Remote URL'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _urlCtrl,
                    style: AppTheme.mono(size: 12),
                    decoration: const InputDecoration(
                      hintText: 'https://example.com/repo.flatpakrepo',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'URL is required'
                        : null,
                  ),
                ],

                const SizedBox(height: 16),

                // ── Remote name (both modes) ─────────────────────────────
                const _Label('Remote name'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  style: AppTheme.mono(size: 12),
                  decoration: const InputDecoration(hintText: 'flathub'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),

                const SizedBox(height: 24),

                // ── Actions ──────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _submit,
                      child: const Text('Add Remote'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: AppTheme.ui(
      size: 10,
      color: AppTheme.fg2,
      weight: FontWeight.w600,
    ).copyWith(letterSpacing: 0.8),
  );
}

class _UrlChip extends StatelessWidget {
  final String url;
  const _UrlChip(this.url);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: AppTheme.bg2,
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: AppTheme.border, width: 0.5),
    ),
    child: Text(url, style: AppTheme.mono(size: 10, color: AppTheme.fg1)),
  );
}

class _ModeToggle extends StatelessWidget {
  final _AddMode value;
  final ValueChanged<_AddMode> onChanged;
  const _ModeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    decoration: BoxDecoration(
      color: AppTheme.bg2,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppTheme.border, width: 0.5),
    ),
    child: Row(
      children: [
        _Seg('Known repos', _AddMode.known, value, onChanged),
        _Seg('Custom URL', _AddMode.custom, value, onChanged),
      ],
    ),
  );
}

class _Seg extends StatelessWidget {
  final String label;
  final _AddMode mine;
  final _AddMode current;
  final ValueChanged<_AddMode> onChanged;
  const _Seg(this.label, this.mine, this.current, this.onChanged);

  @override
  Widget build(BuildContext context) {
    final active = mine == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(mine),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: active
                ? AppTheme.teal.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: active
                ? Border.all(
                    color: AppTheme.teal.withValues(alpha: 0.4),
                    width: 0.5,
                  )
                : Border.all(color: Colors.transparent),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTheme.ui(
              size: 12,
              color: active ? AppTheme.teal : AppTheme.fg2,
              weight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
