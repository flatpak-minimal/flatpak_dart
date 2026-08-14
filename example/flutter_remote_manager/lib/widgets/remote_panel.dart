// lib/widgets/remote_panel.dart
//
// Left sidebar showing all configured remotes.
// Tapping a remote selects it; tapping again does nothing.
// Each row has an overflow menu: enable/disable and remove.

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/remote_provider.dart';
import '../theme/app_theme.dart';
import 'add_remote_dialog.dart';

class RemotePanel extends StatelessWidget {
  const RemotePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RemoteProvider>();

    return Container(
      width: 256,
      decoration: const BoxDecoration(
        color: AppTheme.bg1,
        border: Border(right: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header bar ────────────────────────────────────────────────
          _PanelHeader(
            onAdd: () => _showAddDialog(context, prov),
            onRepopulate: () => _confirmRepopulate(context, prov),
          ),

          const Divider(),

          // ── Remote list ───────────────────────────────────────────────
          if (prov.loadingRemotes)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppTheme.teal,
                  ),
                ),
              ),
            )
          else if (prov.remotes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No remotes configured.',
                style: AppTheme.ui(size: 12, color: AppTheme.fg2),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: prov.remotes.length,
                itemBuilder: (_, i) => _RemoteTile(
                  remote: prov.remotes[i],
                  selected: prov.selectedName == prov.remotes[i].name,
                  onSelect: () => prov.selectRemote(prov.remotes[i].name),
                  onToggle: () => prov.toggleDisabled(prov.remotes[i].name),
                  onRemove: () =>
                      _confirmRemove(context, prov, prov.remotes[i]),
                ),
              ),
            ),

          const Divider(),

          // ── Footer status ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              '${prov.remotes.length} remote${prov.remotes.length != 1 ? "s" : ""}',
              style: AppTheme.ui(size: 10, color: AppTheme.fg2),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, RemoteProvider prov) async {
    final result =
        await showDialog<({String name, FlatpakRemoteConfig config})>(
          context: context,
          builder: (_) => const AddRemoteDialog(),
        );
    if (result == null) return;
    try {
      await prov.addRemote(result.name, result.config);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to add remote: $e',
              style: AppTheme.ui(size: 12, color: AppTheme.fg0),
            ),
            backgroundColor: AppTheme.bg2,
          ),
        );
      }
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    RemoteProvider prov,
    FlatpakRemote r,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Remove "${r.name}"?',
        message:
            'The remote will be removed. Installed apps from this '
            'remote are not affected.',
        action: 'Remove',
        danger: true,
      ),
    );
    if (ok != true) return;
    try {
      await prov.removeRemote(r.name, force: true);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove: $e', style: AppTheme.ui(size: 12)),
            backgroundColor: AppTheme.bg2,
          ),
        );
      }
    }
  }

  Future<void> _confirmRepopulate(
    BuildContext context,
    RemoteProvider prov,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        title: 'Repopulate with Flathub?',
        message:
            'All non-system remotes will be removed and replaced with '
            'Flathub, Flathub Verified, Flathub FLOSS, and '
            'Flathub Verified FLOSS. Installed apps are not affected.',
        action: 'Repopulate',
        danger: false,
      ),
    );
    if (ok != true) return;
    try {
      await prov.repopulateWithFlathub();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e', style: AppTheme.ui(size: 12)),
            backgroundColor: AppTheme.bg2,
          ),
        );
      }
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onRepopulate;
  const _PanelHeader({required this.onAdd, required this.onRepopulate});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
    child: Row(
      children: [
        Text(
          'Remotes',
          style: AppTheme.ui(
            size: 11,
            weight: FontWeight.w600,
            color: AppTheme.fg2,
          ).copyWith(letterSpacing: 0.6),
        ),
        const Spacer(),
        // Repopulate button
        Tooltip(
          message: 'Repopulate with Flathub',
          child: InkWell(
            onTap: onRepopulate,
            borderRadius: BorderRadius.circular(3),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.restart_alt, size: 15, color: AppTheme.fg2),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Add remote button
        Tooltip(
          message: 'Add remote',
          child: InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(3),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.add, size: 16, color: AppTheme.teal),
            ),
          ),
        ),
      ],
    ),
  );
}

class _RemoteTile extends StatefulWidget {
  final FlatpakRemote remote;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  const _RemoteTile({
    required this.remote,
    required this.selected,
    required this.onSelect,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  State<_RemoteTile> createState() => _RemoteTileState();
}

class _RemoteTileState extends State<_RemoteTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.remote;
    final sel = widget.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: sel
                ? AppTheme.teal.withValues(alpha: 0.08)
                : _hovering
                ? AppTheme.bg3
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: sel ? AppTheme.teal : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
          child: Row(
            children: [
              // Active dot
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: r.disabled
                      ? AppTheme.fg2
                      : sel
                      ? AppTheme.teal
                      : AppTheme.tealDim,
                ),
              ),
              const SizedBox(width: 10),

              // Name + URL
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: AppTheme.ui(
                        size: 13,
                        color: r.disabled ? AppTheme.fg2 : AppTheme.fg0,
                        weight: sel ? FontWeight.w600 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (r.subset != RemoteSubset.none)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _SubsetBadge(r.subset),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _shortUrl(r.url),
                        style: AppTheme.mono(size: 9, color: AppTheme.fg2),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Overflow menu (shown on hover or selection)
              if (_hovering || sel)
                _OverflowMenu(
                  remote: r,
                  onToggle: widget.onToggle,
                  onRemove: widget.onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortUrl(String url) {
    try {
      final u = Uri.parse(url);
      return u.host.isEmpty ? url : u.host;
    } catch (_) {
      return url;
    }
  }
}

class _SubsetBadge extends StatelessWidget {
  final RemoteSubset subset;
  const _SubsetBadge(this.subset);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (subset) {
      RemoteSubset.verified => ('verified', AppTheme.teal),
      RemoteSubset.floss => ('floss', const Color(0xFF76C893)),
      RemoteSubset.verifiedFloss => ('verified·floss', AppTheme.teal),
      RemoteSubset.none => ('', AppTheme.fg2),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: AppTheme.ui(size: 9, color: color, weight: FontWeight.w600),
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  final FlatpakRemote remote;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  const _OverflowMenu({
    required this.remote,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    padding: EdgeInsets.zero,
    color: AppTheme.bg2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: const BorderSide(color: AppTheme.border, width: 0.5),
    ),
    iconSize: 14,
    icon: const Icon(Icons.more_vert, size: 14, color: AppTheme.fg2),
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'toggle',
        child: Row(
          children: [
            Icon(
              remote.disabled ? Icons.toggle_on : Icons.toggle_off,
              size: 14,
              color: AppTheme.fg1,
            ),
            const SizedBox(width: 8),
            Text(
              remote.disabled ? 'Enable' : 'Disable',
              style: AppTheme.ui(size: 12),
            ),
          ],
        ),
      ),
      if (!remote.isStatic)
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 14, color: AppTheme.amber),
              const SizedBox(width: 8),
              Text(
                'Remove',
                style: AppTheme.ui(size: 12, color: AppTheme.amber),
              ),
            ],
          ),
        ),
    ],
    onSelected: (v) {
      if (v == 'toggle') onToggle();
      if (v == 'remove') onRemove();
    },
  );
}

// ── Confirm dialog ───────────────────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String action;
  final bool danger;
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.action,
    required this.danger,
  });

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppTheme.bg1,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: AppTheme.border, width: 0.5),
    ),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.ui(size: 14, weight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(message, style: AppTheme.ui(size: 12, color: AppTheme.fg1)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: danger ? AppTheme.amber : AppTheme.teal,
                  foregroundColor: danger
                      ? const Color(0xFF1A0E00)
                      : const Color(0xFF001A14),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(action),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
