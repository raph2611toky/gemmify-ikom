import 'package:flutter/material.dart';

import '../services/local_auth_service.dart';
import 'auth/welcome_screen.dart';
import 'app_entry_screen.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = LocalAuthService.instance.currentUserSync;
    if (user == null) return const WelcomeScreen();

    // La session pédagogique persistante a déjà été restaurée dans main().
    return const AppEntryScreen();
  }
}
