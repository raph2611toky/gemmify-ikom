import 'package:flutter/material.dart';

import '../services/local_auth_service.dart';
import '../services/local_learning_database.dart';
import 'auth/welcome_screen.dart';
import 'app_entry_screen.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = LocalAuthService.instance.currentUserSync;
    if (user == null) return const WelcomeScreen();

    // La session locale est déjà lue dans main(). Aucun appel asynchrone
    // supplémentaire n'est nécessaire avant l'ouverture du modèle.
    LocalLearningDatabase.instance.restoreAccountSession(user.profile);
    return const AppEntryScreen();
  }
}
