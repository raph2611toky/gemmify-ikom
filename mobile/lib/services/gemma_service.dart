import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../models/audio_language_mode.dart';
import 'background_model_download_service.dart';

class ConversationReplayItem {
  final bool isUser;
  final String text;

  const ConversationReplayItem({
    required this.isUser,
    required this.text,
  });
}

class GemmaService {
  static final GemmaService _instance = GemmaService._internal();

  factory GemmaService() => _instance;

  GemmaService._internal();

  final BackgroundModelDownloadService _downloadService =
      BackgroundModelDownloadService.instance;

  InferenceModel? _model;
  InferenceChat? _chat;
  bool _isReady = false;
  bool _installing = false;
  bool _loading = false;

  bool get isReady => _isReady;
  bool get isInstalling => _installing;
  bool get isLoading => _loading;
  bool get supportsImages => _chat?.supportsImages ?? false;
  bool get supportsAudio => _chat?.supportAudio ?? false;
  bool get hasLiveHistory => _chat?.fullHistory.isNotEmpty ?? false;
  int get currentTokens => _chat?.currentTokens ?? 0;

  static const String modelFileName = 'gemma-4-E2B-it.litertlm';

  static const String modelUrl =
      'https://huggingface.co/'
      'litert-community/gemma-4-E2B-it-litert-lm/'
      'resolve/6e5c4f1e395deb959c494953478fa5cec4b8008f/'
      'gemma-4-E2B-it.litertlm';

  static const int expectedModelBytes = 2588147712;


  /// Construit localement l'instruction vocale afin que GemmaService reste
  /// compatible même si l'ancien fichier audio_language_mode.dart est encore
  /// présent dans le projet.
  static String _directAudioInstructionFor(AudioLanguageMode mode) {
    switch (mode) {
      case AudioLanguageMode.malagasy:
        return 'Henoy mivantana ny feo ary valio amin\'ny teny malagasy, '
            'mazava sy pedagogika. Aza mampiseho transcription.';
      case AudioLanguageMode.mixed:
        return 'Écoute directement le vocal malagasy/français et réponds '
            'principalement en malagasy, en gardant les termes scolaires '
            'français utiles. Ne montre aucune transcription.';
      case AudioLanguageMode.french:
        return 'Écoute directement le vocal et réponds en français clair et '
            'pédagogique. Ne montre aucune transcription.';
    }
  }

  Future<void> initEngine() async {
    await FlutterGemma.initialize(
      inferenceEngines: [
        LiteRtLmEngine(),
      ],
    );
  }

  Future<ModelDownloadSnapshot> startBackgroundDownload() {
    return _downloadService.start(
      url: modelUrl,
      fileName: modelFileName,
      expectedTotalBytes: expectedModelBytes,
    );
  }

  Future<ModelDownloadSnapshot> getDownloadState() {
    return _downloadService.getState();
  }

  Stream<ModelDownloadSnapshot> watchDownload() {
    return _downloadService.watch();
  }

  Future<void> cancelDownload() {
    return _downloadService.cancel();
  }

  Future<bool> isModelAlreadyDownloaded() async {
    try {
      return FlutterGemma.hasActiveModel() ||
          await FlutterGemma.isModelInstalled(modelFileName);
    } catch (_) {
      return false;
    }
  }

  Future<void> installDownloadedModel(String filePath) async {
    if (_installing) return;
    _installing = true;

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw StateError('Le fichier du modèle est introuvable : $filePath');
      }

      final length = await file.length();
      if (length != expectedModelBytes) {
        throw StateError(
          'Fichier incomplet : $length octets sur $expectedModelBytes.',
        );
      }

      debugPrint('🟣 Installation LiteRT-LM depuis : $filePath');
      debugPrint('🟣 Taille vérifiée : $length octets');

      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(filePath).install();

      debugPrint('🟢 Modèle enregistré dans FlutterGemma');
    } finally {
      _installing = false;
    }
  }

  Future<void> createSession({bool forceRecreate = false}) async {
    if (!forceRecreate &&
        _isReady &&
        _chat != null &&
        _model != null) {
      debugPrint(
        '🧠 Session existante conservée : '
        '${_chat!.currentTokens} tokens dans le même chat',
      );
      return;
    }

    if (_loading) return;
    _loading = true;
    _isReady = false;

    try {
      await _chat?.stopGeneration();
      await _chat?.close();
      _chat = null;
      await _model?.close();
      _model = null;

      debugPrint('🟣 Chargement du modèle LiteRT-LM image + audio...');

      _model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
        supportImage: true,
        supportAudio: true,
        maxNumImages: 1,
      );

      debugPrint('🟣 Création de la session pédagogique multimodale...');
      _chat = await _model!.createChat(
        temperature: 0.3,
        maxOutputTokens: 384,
        supportImage: true,
        supportAudio: true,
        systemInstruction: '''
Tu es Gemma Edu, un professeur patient, chaleureux et adapté aux élèves de Madagascar.
Tu peux dialoguer en malagasy, en français, ou dans un mélange malagasy-français.
Respecte toujours la langue demandée dans le message.
Explique étape par étape, utilise des exemples locaux quand ils sont utiles et conserve les termes scolaires français couramment utilisés à Madagascar.
Pour une photo d'exercice, décris ce que tu lis avant de résoudre.
Pour un message vocal, écoute directement le son et réponds à la question ou à la demande entendue. Ne fournis pas de transcription et ne demande pas de validation, sauf si l’utilisateur demande explicitement une transcription.
''',
      );

      if (!(_chat?.supportsImages ?? false)) {
        throw StateError(
          'La session a été créée sans prise en charge des images.',
        );
      }
      if (!(_chat?.supportAudio ?? false)) {
        throw StateError(
          'La session a été créée sans prise en charge de l’audio.',
        );
      }

      _isReady = true;
      debugPrint('🟢 Session Gemma prête — image, audio et malagasy activés');
    } finally {
      _loading = false;
    }
  }

  /// Réinjecte une discussion textuelle après un redémarrage de l'application.
  ///
  /// Tant que l'application reste ouverte, la session native conserve déjà
  /// exactement les messages texte, image et audio. Le rejeu n'est donc fait
  /// que lorsque la nouvelle session ne possède encore aucun historique.
  Future<void> restoreConversation(
    List<ConversationReplayItem> history, {
    int maxMessages = 14,
  }) async {
    final chat = _chat;
    if (chat == null || history.isEmpty) return;

    if (chat.fullHistory.isNotEmpty) {
      debugPrint(
        '🧠 Historique natif déjà présent : aucun rejeu nécessaire.',
      );
      return;
    }

    final usable = history
        .where((entry) => entry.text.trim().isNotEmpty)
        .toList(growable: false);
    final start = usable.length > maxMessages
        ? usable.length - maxMessages
        : 0;
    final recent = usable.sublist(start);

    final replay = recent
        .map(
          (entry) => Message.text(
            text: entry.text.trim(),
            isUser: entry.isUser,
          ),
        )
        .toList(growable: false);

    await chat.clearHistory(replayHistory: replay);
    debugPrint(
      '🧠 Discussion restaurée : ${replay.length} messages, '
      '${chat.currentTokens} tokens',
    );
  }

  /// Envoie le son directement à Gemma et diffuse sa réponse.
  ///
  /// Il n'y a volontairement aucune étape de transcription. Le message audio
  /// est ajouté à l'unique session multimodale créée avec `createChat()`, puis
  /// Gemma écoute, comprend et répond dans la langue choisie.
  Stream<String> sendAudioMessageStream({
    required Uint8List audioBytes,
    required AudioLanguageMode languageMode,
  }) {
    if (audioBytes.length <= 44) {
      throw ArgumentError('Le message vocal est vide ou invalide.');
    }

    debugPrint(
      '🎙️ Envoi vocal direct à Gemma : '
      'mode=${languageMode.storageValue}, ${audioBytes.length} octets',
    );

    return sendMessageStream(
      text: _directAudioInstructionFor(languageMode),
      audioBytes: audioBytes,
    );
  }

  Stream<String> sendMessageStream({
    required String text,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
  }) async* {
    final chat = _chat;

    if (chat == null) {
      throw StateError(
        'Session non initialisée. '
        'Appelle createSession() avant sendMessageStream().',
      );
    }

    if (imageBytes != null && audioBytes != null) {
      throw ArgumentError(
        'Envoie une image ou un audio dans un même message, pas les deux.',
      );
    }

    final Message message;

    if (audioBytes != null && audioBytes.isNotEmpty) {
      if (!chat.supportAudio) {
        throw StateError(
          'La session actuelle ne prend pas en charge l’audio. '
          'Redémarre complètement l’application pour recréer la session audio.',
        );
      }

      final normalizedText = text.trim().isEmpty
          ? _directAudioInstructionFor(AudioLanguageMode.mixed)
          : text.trim();

      message = Message.withAudio(
        text: normalizedText,
        audioBytes: audioBytes,
        isUser: true,
      );

      debugPrint('🎙️ Audio envoyé au modèle : ${audioBytes.length} octets');
      debugPrint(
        '🎙️ Message audio : hasAudio=${message.hasAudio}, type=${message.type}',
      );
    } else if (imageBytes != null && imageBytes.isNotEmpty) {
      if (!chat.supportsImages) {
        throw StateError(
          'La session actuelle ne prend pas en charge les images. '
          'Redémarre complètement l’application pour recréer la session vision.',
        );
      }

      final normalizedText = text.trim().isEmpty
          ? 'Analyse précisément cette image et explique ce que tu observes.'
          : text.trim();

      message = Message.withImages(
        text: normalizedText,
        imageBytes: [imageBytes],
        isUser: true,
      );

      debugPrint('🖼️ Image envoyée au modèle : ${imageBytes.length} octets');
      debugPrint(
        '🖼️ Message multimodal : hasImage=${message.hasImage}, '
        'type=${message.type}',
      );
    } else {
      final normalizedText = text.trim();
      if (normalizedText.isEmpty) {
        throw ArgumentError('Le message texte est vide.');
      }

      message = Message.text(
        text: normalizedText,
        isUser: true,
      );
      debugPrint('💬 Message texte envoyé au modèle');
    }

    await chat.addQueryChunk(message);

    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        yield response.token;
      }
    }
  }

  Future<void> stopGeneration() async {
    await _chat?.stopGeneration();
  }

  Future<void> dispose() async {
    await _chat?.close();
    _chat = null;
    await _model?.close();
    _model = null;
    _isReady = false;
  }
}
