import 'package:flutter/material.dart';

import 'screens/model_download_screen.dart';
import 'screens/startup_screen.dart';
import 'services/local_auth_service.dart';
import 'services/local_learning_database.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Les comptes sont initialisés avant la base pédagogique afin de restaurer
  // le bon espace SQLite (discussions + progression) pour l'utilisateur.
  await LocalAuthService.instance.initialize();
  await LocalLearningDatabase.instance.initialize();
  final rememberedUser = LocalAuthService.instance.currentUserSync;
  if (rememberedUser != null) {
    await LocalLearningDatabase.instance.restoreAccountSession(
      userId: rememberedUser.id,
      profile: rememberedUser.profile,
    );
  }

  runApp(const GemmafyApp());
}

class GemmafyApp extends StatelessWidget {
  const GemmafyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma Edu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: const TextScaler.linear(1.0),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      routes: {
        '/model': (_) => const ModelDownloadScreen(),
      },
      home: const StartupScreen(),
    );
  }
}
