import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/audio_language_mode.dart';

class VoiceInteractionService {
  VoiceInteractionService._();

  static final VoiceInteractionService instance = VoiceInteractionService._();

  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);
  final ValueNotifier<String?> activeLocale = ValueNotifier<String?>(null);

  bool _initialized = false;
  bool _cancelRequested = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.44);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.setQueueMode(0);

    _tts.setStartHandler(() {
      isSpeaking.value = true;
    });
    _tts.setCompletionHandler(() {
      isSpeaking.value = false;
    });
    _tts.setCancelHandler(() {
      isSpeaking.value = false;
    });
    _tts.setErrorHandler((message) {
      debugPrint('🔊 Erreur TTS : $message');
      isSpeaking.value = false;
    });

    _initialized = true;
    await _configureLanguage(AudioLanguageMode.french);
  }

  /// Configure la meilleure voix installée pour la langue choisie.
  ///
  /// Sur beaucoup de téléphones Android, `mg-MG` n'est pas disponible. Dans
  /// ce cas, la réponse reste affichée en malagasy et la lecture utilise la
  /// meilleure voix de secours disponible, généralement `fr-FR`.
  Future<String?> _configureLanguage(AudioLanguageMode mode) async {
    for (final locale in mode.preferredTtsLocales) {
      try {
        final availability = await _tts.isLanguageAvailable(locale);
        final available = availability == true || availability == 1;
        if (!available) continue;

        final result = await _tts.setLanguage(locale);
        if (result == 1 || result == true || result == null) {
          activeLocale.value = locale;
          debugPrint('🔊 Voix sélectionnée : $locale');
          return locale;
        }
      } catch (error) {
        debugPrint('🔊 Voix $locale indisponible : $error');
      }
    }

    try {
      await _tts.setLanguage('fr-FR');
      activeLocale.value = 'fr-FR';
      return 'fr-FR';
    } catch (_) {
      activeLocale.value = null;
      return null;
    }
  }

  Future<void> speak(
    String markdownText, {
    AudioLanguageMode languageMode = AudioLanguageMode.french,
  }) async {
    await initialize();
    await _tts.stop();
    _cancelRequested = false;
    await _configureLanguage(languageMode);

    final text = _plainText(markdownText);
    if (text.trim().isEmpty) return;

    isSpeaking.value = true;
    try {
      final chunks = _splitText(text, 3200);
      for (final chunk in chunks) {
        if (_cancelRequested) break;
        await _tts.speak(chunk, focus: true);
      }
    } finally {
      isSpeaking.value = false;
    }
  }

  Future<void> stop() async {
    if (!_initialized) return;
    _cancelRequested = true;
    await _tts.stop();
    isSpeaking.value = false;
  }

  String _plainText(String input) {
    return input
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAllMapped(RegExp(r'`([^`]*)`'), (match) => match.group(1) ?? '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\([^)]*\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'[#>*_~\-]{1,3}'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _splitText(String text, int maxLength) {
    if (text.length <= maxLength) return <String>[text];

    final result = <String>[];
    var remaining = text;

    while (remaining.length > maxLength) {
      var splitAt = remaining.lastIndexOf(RegExp(r'[.!?]\s'), maxLength);
      if (splitAt < maxLength ~/ 2) {
        splitAt = remaining.lastIndexOf(' ', maxLength);
      }
      if (splitAt <= 0) splitAt = maxLength;

      result.add(remaining.substring(0, splitAt + 1).trim());
      remaining = remaining.substring(splitAt + 1).trim();
    }

    if (remaining.isNotEmpty) result.add(remaining);
    return result;
  }

  Future<void> dispose() async {
    await stop();
    isSpeaking.dispose();
    activeLocale.dispose();
  }
}
