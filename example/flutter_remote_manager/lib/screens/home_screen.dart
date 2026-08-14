// lib/screens/home_screen.dart
//
// Root screen. Two-pane layout:
//   Left  (256 px) — RemotePanel: list of remotes, add/remove/repopulate
//   Right (flex)   — PackageListView: streams refs from selected remote
//
// A top AppBar holds the window title and a global refresh icon.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/remote_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/package_list_view.dart';
import '../widgets/remote_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Kick off the initial data load after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RemoteProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.bg0,
      body: Column(
        children: [
          // ── App bar ──────────────────────────────────────────────────
          _AppBar(),

          Divider(),

          // ── Main two-pane content ────────────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left pane: remote list
                RemotePanel(),

                // Right pane: package browser
                Expanded(child: PackageListView()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppBar extends StatelessWidget {
  const _AppBar();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RemoteProvider>();

    return Container(
      height: 48,
      color: AppTheme.bg1,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Terminal-style decorative squares
          _TrafficLight(),
          const SizedBox(width: 14),

          // Title
          Text(
            'Flatpak Remote Manager',
            style: AppTheme.ui(
              size: 13,
              weight: FontWeight.w600,
              color: AppTheme.fg0,
            ),
          ),

          const SizedBox(width: 6),
          Text(
            '// flatpak_dart example',
            style: AppTheme.mono(size: 10, color: AppTheme.fg2),
          ),

          const Spacer(),

          // Error badge
          if (prov.remoteError != null)
            Tooltip(
              message: prov.remoteError,
              child: const Icon(
                Icons.warning_amber_outlined,
                size: 14,
                color: AppTheme.amber,
              ),
            ),

          const SizedBox(width: 8),

          // Global refresh
          Tooltip(
            message: 'Refresh all',
            child: InkWell(
              onTap: () => prov.refresh(),
              borderRadius: BorderRadius.circular(3),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.refresh,
                  size: 15,
                  color: prov.loadingRemotes ? AppTheme.teal : AppTheme.fg2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficLight extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      _Dot(color: Color(0xFFFF5F56)),
      SizedBox(width: 5),
      _Dot(color: Color(0xFFFFBD2E)),
      SizedBox(width: 5),
      _Dot(color: Color(0xFF27C93F)),
    ],
  );
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: 0.7),
    ),
  );
}
