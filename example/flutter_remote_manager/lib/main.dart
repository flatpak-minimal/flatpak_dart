// lib/main.dart
//
// Entry point for the Flatpak Remote Manager Flutter example.
// Targets Linux desktop (the only platform where flatpak_dart works).
//
// Run:
//   flutter run -d linux

import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FlatpakRemoteApp());
}
