import 'package:flutter/material.dart';

import 'screens/model_download_screen.dart';
import 'screens/startup_screen.dart';
import 'services/local_auth_service.dart';
import 'services/local_learning_database.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise uniquement la petite base des comptes. Les discussions
  // restent en mémoire et le moteur IA n'est pas chargé avant le chatbot.
  await Future.wait([
    LocalLearningDatabase.instance.initialize(),
    LocalAuthService.instance.initialize(),
  ]);

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
