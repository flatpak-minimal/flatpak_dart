// lib/widgets/package_list_view.dart
//
// Right-pane: streams FlatpakRef records from the selected remote.
// Shows a live counter while streaming, filter input, and status bar.

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/remote_provider.dart';
import '../theme/app_theme.dart';

class PackageListView extends StatelessWidget {
  const PackageListView({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RemoteProvider>();

    if (prov.selectedName == null) {
      return const _EmptyState(
        icon:    Icons.cloud_off_outlined,
        message: 'Select a remote from the left panel.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Toolbar ───────────────────────────────────────────────────
        _Toolbar(
          remoteName:  prov.selectedName!,
          totalLoaded: prov.totalLoaded,
          loadState:   prov.loadState,
        ),

        const Divider(),

        // ── Search bar ────────────────────────────────────────────────
        _SearchBar(
          value:     prov.packageFilter,
          onChanged: (v) => prov.packageFilter = v,
        ),

        const Divider(),

        // ── Main content ──────────────────────────────────────────────
        Expanded(child: _Body(prov: prov)),

        // ── Status bar ────────────────────────────────────────────────
        _StatusBar(prov: prov),
      ],
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final String          remoteName;
  final int             totalLoaded;
  final PackageLoadState loadState;
  const _Toolbar({
    required this.remoteName,
    required this.totalLoaded,
    required this.loadState,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
        child: Row(children: [
          // Remote name
          Text(remoteName,
              style: AppTheme.ui(
                  size: 14, weight: FontWeight.w600, color: AppTheme.fg0)),
          const SizedBox(width: 10),

          // Streaming indicator
          if (loadState == PackageLoadState.streaming) ...[
            SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppTheme.teal,
              ),
            ),
            const SizedBox(width: 6),
            Text('$totalLoaded loaded…',
                style: AppTheme.ui(size: 11, color: AppTheme.fg2)),
          ] else if (loadState == PackageLoadState.done) ...[
            const Icon(Icons.check_circle_outline,
                size: 12, color: AppTheme.teal),
            const SizedBox(width: 4),
            Text('$totalLoaded packages',
                style: AppTheme.ui(size: 11, color: AppTheme.fg2)),
          ],

          const Spacer(),

          // Refresh
          Tooltip(
            message: 'Refresh list',
            child: InkWell(
              onTap: () => context.read<RemoteProvider>().refresh(),
              borderRadius: BorderRadius.circular(3),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.refresh,
                    size: 15,
                    color: loadState == PackageLoadState.streaming
                        ? AppTheme.fg2
                        : AppTheme.fg1),
              ),
            ),
          ),
        ]),
      );
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatefulWidget {
  final String          value;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.value, required this.onChanged});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final _ctrl = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_SearchBar old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.search, size: 14, color: AppTheme.fg2),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              style:      AppTheme.ui(size: 13),
              onChanged:  widget.onChanged,
              decoration: const InputDecoration(
                hintText:    'Filter packages…',
                border:      InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense:     true,
                contentPadding: EdgeInsets.zero,
                fillColor:   Colors.transparent,
              ),
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            InkWell(
              onTap: () {
                _ctrl.clear();
                widget.onChanged('');
              },
              child: const Icon(Icons.close, size: 12, color: AppTheme.fg2),
            ),
        ]),
      );
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final RemoteProvider prov;
  const _Body({required this.prov});

  @override
  Widget build(BuildContext context) {
    if (prov.loadState == PackageLoadState.error) {
      return _EmptyState(
        icon:    Icons.error_outline,
        message: prov.packageError ?? 'Unknown error',
        color:   AppTheme.amber,
      );
    }

    if (prov.loadState == PackageLoadState.streaming &&
        prov.packages.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.teal),
          ),
          SizedBox(height: 12),
          Text('Fetching remote index…',
              style: TextStyle(color: AppTheme.fg2, fontSize: 12)),
        ]),
      );
    }

    if (prov.packages.isEmpty && prov.loadState == PackageLoadState.done) {
      return const _EmptyState(
        icon:    Icons.inventory_2_outlined,
        message: 'No packages found.',
      );
    }

    return Scrollbar(
      child: ListView.builder(
        itemCount:   prov.packages.length,
        itemExtent:  44,
        itemBuilder: (_, i) => _PackageRow(ref: prov.packages[i], index: i),
      ),
    );
  }
}

// ── Package row ───────────────────────────────────────────────────────────────

class _PackageRow extends StatefulWidget {
  final FlatpakRef ref;
  final int        index;
  const _PackageRow({required this.ref, required this.index});

  @override
  State<_PackageRow> createState() => _PackageRowState();
}

class _PackageRowState extends State<_PackageRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final ref  = widget.ref;
    final even = widget.index % 2 == 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit:  (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: _hovering
            ? AppTheme.bg3
            : even
                ? Colors.transparent
                : AppTheme.bg1.withOpacity(0.4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        alignment: Alignment.centerLeft,
        child: Row(children: [
          // Kind icon
          Icon(
            ref.kind == 'app' ? Icons.apps : Icons.memory,
            size:  12,
            color: ref.kind == 'app' ? AppTheme.teal : AppTheme.fg2,
          ),
          const SizedBox(width: 10),

          // App ID (monospace)
          Expanded(
            flex: 5,
            child: Text(
              ref.name,
              style: AppTheme.mono(
                size:  12,
                color: AppTheme.fg0,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Arch
          SizedBox(
            width: 60,
            child: Text(
              ref.arch,
              style: AppTheme.mono(size: 10, color: AppTheme.fg2),
              textAlign: TextAlign.center,
            ),
          ),

          // Branch
          SizedBox(
            width: 70,
            child: Text(
              ref.branch,
              style: AppTheme.mono(size: 10, color: AppTheme.tealDim),
              textAlign: TextAlign.center,
            ),
          ),

          // Copy button on hover
          AnimatedOpacity(
            opacity:  _hovering ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 100),
            child: Tooltip(
              message: 'Copy app ID',
              child: InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: ref.name));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied ${ref.name}',
                          style: AppTheme.ui(size: 11)),
                      backgroundColor: AppTheme.bg2,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(2),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.copy, size: 11, color: AppTheme.fg2),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Status bar ────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final RemoteProvider prov;
  const _StatusBar({required this.prov});

  @override
  Widget build(BuildContext context) {
    final filtered = prov.packages.length;
    final total    = prov.totalLoaded;
    final showing  = prov.packageFilter.isNotEmpty
        ? '$filtered of $total'
        : '$total';

    return Container(
      height: 26,
      decoration: const BoxDecoration(
        color:  AppTheme.bg1,
        border: Border(top: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Text(
          '$showing packages',
          style: AppTheme.ui(size: 10, color: AppTheme.fg2),
        ),
        const Spacer(),
        if (prov.loadState == PackageLoadState.streaming)
          Row(children: [
            SizedBox.square(
              dimension: 8,
              child: CircularProgressIndicator(
                  strokeWidth: 1, color: AppTheme.teal),
            ),
            const SizedBox(width: 6),
            Text('streaming…',
                style: AppTheme.ui(size: 10, color: AppTheme.teal)),
          ]),
        if (prov.loadState == PackageLoadState.done)
          Row(children: [
            const Icon(Icons.circle, size: 6, color: AppTheme.teal),
            const SizedBox(width: 5),
            Text('done', style: AppTheme.ui(size: 10, color: AppTheme.fg2)),
          ]),
        if (prov.loadState == PackageLoadState.error)
          Row(children: [
            const Icon(Icons.circle, size: 6, color: AppTheme.amber),
            const SizedBox(width: 5),
            Text('error', style: AppTheme.ui(size: 10, color: AppTheme.amber)),
          ]),
      ]),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   message;
  final Color    color;
  const _EmptyState({
    required this.icon,
    required this.message,
    this.color = AppTheme.fg2,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 28, color: color.withOpacity(0.5)),
          const SizedBox(height: 10),
          Text(message,
              style: AppTheme.ui(size: 12, color: color.withOpacity(0.7))),
        ]),
      );
}