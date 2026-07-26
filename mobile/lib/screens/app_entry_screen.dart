import 'package:flutter/material.dart';

import '../services/gemma_service.dart';
import 'chat_screen.dart';
import 'model_download_screen.dart';

/// Évite l'écran de préparation lorsque le moteur est déjà prêt en mémoire.
class AppEntryScreen extends StatelessWidget {
  const AppEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GemmaService().isReady
        ? const ChatScreen()
        : const ModelDownloadScreen();
  }
}
