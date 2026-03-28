// lib/app.dart — MaterialApp root with theme and provider

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/remote_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class FlatpakRemoteApp extends StatelessWidget {
  const FlatpakRemoteApp({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => RemoteProvider(),
        child: MaterialApp(
          title:        'Flatpak Remote Manager',
          debugShowCheckedModeBanner: false,
          theme:        AppTheme.dark,
          home:         const HomeScreen(),
        ),
      );
}