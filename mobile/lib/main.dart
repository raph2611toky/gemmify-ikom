import 'package:flutter/material.dart';

import 'screens/model_download_screen.dart';
import 'services/gemma_service.dart';
import 'services/local_learning_database.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LocalLearningDatabase.instance.initialize();
  await GemmaService().initEngine();

  runApp(const GemmafyApp());
}

class GemmafyApp extends StatelessWidget {
  const GemmafyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mpanabe AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const ModelDownloadScreen(),
    );
  }
}
