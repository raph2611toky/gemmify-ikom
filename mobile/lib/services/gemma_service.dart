import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../models/ai_tutor_response.dart';
import '../models/audio_language_mode.dart';
import 'background_model_download_service.dart';
import 'local_learning_database.dart';

class GenerationCancelledException implements Exception {
  const GenerationCancelledException();

  @override
  String toString() => 'GenerationCancelledException';
}

/// Le fichier du modèle peut être présent sur le téléphone alors que
/// flutter_gemma a perdu l'identité du modèle actif.
class ModelNotActiveException implements Exception {
  const ModelNotActiveException([
    this.message =
        'Aucun modèle Gemma actif. Réinstalle ou réactive le modèle local.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class GemmaService {
  static final GemmaService _instance = GemmaService._internal();

  factory GemmaService() => _instance;

  GemmaService._internal();

  final BackgroundModelDownloadService _downloadService =
      BackgroundModelDownloadService.instance;

  InferenceModel? _model;
  InferenceChat? _chat;
  Future<void>? _engineInitFuture;
  Future<void>? _sessionFuture;

  bool _isReady = false;
  bool _installing = false;
  bool _isGenerating = false;
  bool _supportsImageSession = false;
  bool _supportsAudioSession = false;
  int _requestSerial = 0;
  int? _activeRequestSerial;
  int _turnsInSession = 0;
  int? _boundConversationId;
  bool _sessionHydrated = false;

  bool get isReady => _isReady;
  bool get isInstalling => _installing;
  bool get isLoading => _sessionFuture != null;
  bool get isGenerating => _isGenerating;
  bool get supportsImages => _chat?.supportsImages ?? false;
  bool get supportsAudio => _chat?.supportAudio ?? false;
  int get currentTokens => _chat?.currentTokens ?? 0;

  static const String modelFileName = 'gemma-4-E2B-it.litertlm';

  static const String modelUrl =
      'https://huggingface.co/'
      'litert-community/gemma-4-E2B-it-litert-lm/'
      'resolve/6e5c4f1e395deb959c494953478fa5cec4b8008f/'
      'gemma-4-E2B-it.litertlm';

  static const int expectedModelBytes = 2588147712;

  Future<void> initEngine() {
    return _engineInitFuture ??= FlutterGemma.initialize(
      inferenceEngines: [LiteRtLmEngine()],
    );
  }

  Future<ModelDownloadSnapshot> startBackgroundDownload() async {
    await initEngine();
    return _downloadService.start(
      url: modelUrl,
      fileName: modelFileName,
      expectedTotalBytes: expectedModelBytes,
    );
  }

  Future<ModelDownloadSnapshot> getDownloadState() async {
    await initEngine();
    return _downloadService.getState();
  }

  Stream<ModelDownloadSnapshot> watchDownload() => _downloadService.watch();

  Future<void> cancelDownload() => _downloadService.cancel();

  /// Vérifie qu'un modèle est réellement utilisable.
  ///
  /// `isModelInstalled()` seul ne suffit pas : le fichier peut être présent
  /// alors qu'aucun modèle n'est défini comme actif dans flutter_gemma.
  Future<bool> isModelAlreadyDownloaded() async {
    return ensureActiveModelAvailable();
  }

  /// Répare automatiquement l'identité du modèle actif à partir du fichier
  /// téléchargé localement, sans relancer un téléchargement de 2,5 Go.
  Future<bool> ensureActiveModelAvailable() async {
    await initEngine();

    if (FlutterGemma.hasActiveModel()) {
      return true;
    }

    try {
      final snapshot = await _downloadService.getState();
      final localPath = snapshot.filePath;

      if (snapshot.isCompleted && localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
        if (await file.exists() &&
            await file.length() == expectedModelBytes) {
          debugPrint(
            '🔧 Modèle présent mais inactif : réactivation depuis $localPath',
          );
          await installDownloadedModel(localPath);
          return FlutterGemma.hasActiveModel();
        }
      }
    } catch (error) {
      debugPrint('Réactivation locale impossible : $error');
    }

    try {
      final installed = await FlutterGemma.isModelInstalled(modelFileName);
      if (installed) {
        debugPrint(
          '⚠️ Modèle déclaré installé mais sans identité active exploitable.',
        );
      }
    } catch (_) {}

    return false;
  }

  Future<void> installDownloadedModel(String filePath) async {
    await initEngine();

    if (_installing) {
      while (_installing) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (FlutterGemma.hasActiveModel()) return;
    }

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

      await _chat?.close();
      _chat = null;
      await _model?.close();
      _model = null;
      _isReady = false;
      _boundConversationId = null;
      _sessionHydrated = false;

      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(filePath).install();

      if (!FlutterGemma.hasActiveModel()) {
        throw const ModelNotActiveException(
          'Le modèle local a été trouvé, mais son activation a échoué.',
        );
      }

      debugPrint('✅ Modèle Gemma local installé et défini comme actif.');
    } finally {
      _installing = false;
    }
  }

  Future<void> createSession({
    bool forceRecreate = false,
    bool supportImage = false,
    bool supportAudio = false,
  }) async {
    await initEngine();

    final activeModelAvailable = await ensureActiveModelAvailable();
    if (!activeModelAvailable) {
      throw const ModelNotActiveException();
    }

    final hasCapabilities =
        (!supportImage || _supportsImageSession) &&
        (!supportAudio || _supportsAudioSession);
    if (!forceRecreate && _isReady && _model != null && hasCapabilities) {
      return;
    }

    final running = _sessionFuture;
    if (running != null) {
      await running;
      if ((!supportImage || _supportsImageSession) &&
          (!supportAudio || _supportsAudioSession)) {
        return;
      }
    }

    final future = _createSessionInternal(
      forceRecreate: forceRecreate,
      supportImage: supportImage,
      supportAudio: supportAudio,
    );
    _sessionFuture = future;
    try {
      await future;
    } finally {
      if (identical(_sessionFuture, future)) _sessionFuture = null;
    }
  }

  Future<void> _createSessionInternal({
    required bool forceRecreate,
    required bool supportImage,
    required bool supportAudio,
  }) async {
    _isReady = false;
    _activeRequestSerial = null;
    _requestSerial++;

    if (_isGenerating) {
      try {
        await _chat?.stopGeneration();
      } catch (_) {}
      _isGenerating = false;
    }

    final capabilityChanged =
        supportImage != _supportsImageSession ||
        supportAudio != _supportsAudioSession;

    await _chat?.close();
    _chat = null;
    _boundConversationId = null;
    _sessionHydrated = false;

    if (_model == null || forceRecreate || capabilityChanged) {
      await _model?.close();
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
        supportImage: supportImage,
        supportAudio: supportAudio,
        maxNumImages: 1,
      );
      _supportsImageSession = supportImage;
      _supportsAudioSession = supportAudio;
    }

    await _createChatOnly();
    _isReady = true;
    debugPrint(
      '🟢 Mpanabe AI prêt : texte=${!supportImage && !supportAudio}, '
      'image=$supportImage, audio=$supportAudio',
    );
  }

  Future<void> _createChatOnly() async {
    final model = _model;
    if (model == null) {
      throw StateError('Le modèle Gemma n’est pas chargé.');
    }

    await _chat?.close();
    _chat = await model.createChat(
      temperature: 0.12,
      topK: 8,
      tokenBuffer: 280,
      maxOutputTokens: 150,
      supportImage: _supportsImageSession,
      supportAudio: _supportsAudioSession,
      supportsFunctionCalls: false,
      modelType: ModelType.gemma4,
      systemInstruction: _systemInstruction,
    );
    _turnsInSession = 0;
    _sessionHydrated = false;
  }

  static const String _systemInstruction = '''
Tu es Mpanabe AI, professeur attentif, patient et clair pour un élève à Madagascar.
Adapte uniquement les mots, l'exemple et la difficulté au niveau reçu.

Retourne uniquement un JSON compact.
Sans question :
{"response":"markdown complet","subject":"matière","topic":"sujet","action":"none"}
Avec choix :
{"response":"question courte","choices":["choix 1","choix 2"],"subject":"matière","topic":"sujet","action":"wait_answer"}
Après une vraie réponse évaluée, ajoute le champ optionnel :
{"evaluation":{"skill":"compétence courte","correct":true}}

Règles :
- response : 30 à 55 mots, complète, claire, Markdown simple, aucun antislash visible.
- Explique une seule idée avec un exemple concret, puis une courte question si utile.
- Exercice : un seul exercice guidé, 3 choix maximum.
- Jeu/quiz : exactement 2 petites questions, une seule question affichée à la fois.
- Dans un jeu, sois dynamique : emoji, numéro de manche et encouragement bref.
- N'écris jamais « Étape 1 », « Étape 2 » ou « Étape 3 ». Utilise directement les titres « Explication », « Exercice » ou « Jeu et quiz ».
- Quiz et défi chrono : fournis toujours 2 ou 3 choix dans `choices`.
- Vrai ou faux : fournis toujours exactement ["Vrai","Faux"].
- Mémoire : propose une association courte avec 2 ou 3 choix.
- Après la réponse à la question 1, corrige en une phrase puis donne immédiatement la question 2 avec ses choix.
- Après la question 2, donne seulement le score final et un encouragement. Ne demande jamais « as-tu compris ? » et ne propose jamais « J’ai compris » dans un jeu.
- Si la réponse est fausse, corrige simplement et mets correct=false.
- Si elle est juste, mets correct=true. Les notes, la maîtrise et les points sont calculés localement.
- Omet choices quand il n'y a aucun choix. Omet evaluation tant qu'aucune réponse n'est évaluée.
- subject : Mathématiques, Français, Anglais, Sciences ou Autre. topic : chapitre précis.
- Aucun nom d'étudiant, aucun champ vide, aucun ui, card, lesson, memory ou function_call.
''';

  static String _audioInstruction(AudioLanguageMode mode) {
    switch (mode) {
      case AudioLanguageMode.malagasy:
        return 'Valio amin’ny teny malagasy. Aza aseho ny transcription.';
      case AudioLanguageMode.mixed:
        return 'Réponds naturellement en malagasy ou en français sans transcription.';
      case AudioLanguageMode.french:
        return 'Réponds en français clair sans afficher la transcription.';
    }
  }

  void _ensureActive(int serial) {
    if (_activeRequestSerial != serial) {
      throw const GenerationCancelledException();
    }
  }

  Future<bool> _ensureChatForConversation(int conversationId) async {
    if (_chat != null &&
        _boundConversationId == null &&
        _turnsInSession == 0) {
      _boundConversationId = conversationId;
      _sessionHydrated = false;
      return true;
    }

    final mustRebuild = _chat == null ||
        _boundConversationId != conversationId ||
        _turnsInSession >= 4 ||
        currentTokens >= 900;

    if (!mustRebuild) return false;

    await _createChatOnly();
    _boundConversationId = conversationId;
    _sessionHydrated = false;
    debugPrint('♻️ Contexte compact recréé pour la discussion $conversationId');
    return true;
  }

  Future<void> activateConversation(int conversationId) async {
    // La session est changée au prochain envoi pour éviter un travail natif
    // pendant le simple affichage de la liste des discussions.
  }

  Future<AiTutorResponse> sendTutorMessage({
    required int conversationId,
    required String text,
    LessonState activeLesson = const LessonState(),
    bool answerCanBeEvaluated = false,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    AudioLanguageMode languageMode = AudioLanguageMode.mixed,
  }) async {
    if (_isGenerating) {
      throw StateError('Une réponse est déjà en cours de génération.');
    }
    if (imageBytes != null && audioBytes != null) {
      throw ArgumentError('Envoie une image ou un audio, pas les deux ensemble.');
    }

    final needsImage = imageBytes != null;
    final needsAudio = audioBytes != null;
    await createSession(
      forceRecreate: needsImage && !_supportsImageSession ||
          needsAudio && !_supportsAudioSession,
      supportImage: needsImage || _supportsImageSession,
      supportAudio: needsAudio || _supportsAudioSession,
    );

    _isGenerating = true;
    try {
      final rebuilt = await _ensureChatForConversation(conversationId);
      final response = await _generateOnce(
        conversationId: conversationId,
        text: text,
        activeLesson: activeLesson,
        answerCanBeEvaluated: answerCanBeEvaluated,
        imageBytes: imageBytes,
        audioBytes: audioBytes,
        languageMode: languageMode,
        hydrate: rebuilt || !_sessionHydrated,
      );
      return _validateProgress(response, answerCanBeEvaluated);
    } finally {
      _isGenerating = false;
    }
  }

  Future<AiTutorResponse> _generateOnce({
    required int conversationId,
    required String text,
    required LessonState activeLesson,
    required bool answerCanBeEvaluated,
    required AudioLanguageMode languageMode,
    required bool hydrate,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
  }) async {
    final isMultimodal = imageBytes != null || audioBytes != null;
    final context = hydrate
        ? await LocalLearningDatabase.instance.buildCompactContext(
            conversationId,
            recentMessageCount: isMultimodal ? 1 : 2,
          )
        : const CompactConversationContext(summary: '', recentTurns: []);
    final student = await LocalLearningDatabase.instance.buildTutorProfile();
    final progress = activeLesson.isActive
        ? await LocalLearningDatabase.instance.buildCompactProgress(
            subject: activeLesson.subject,
            topic: activeLesson.topic,
            limit: 1,
          )
        : const <String, dynamic>{};

    final normalizedText = _clip(text, isMultimodal ? 180 : 360);
    if (normalizedText.isEmpty && imageBytes == null && audioBytes == null) {
      throw ArgumentError('Le message est vide.');
    }

    final envelope = jsonEncode({
      'message': normalizedText,
      if (student.isNotEmpty) 'student': student,
      if (audioBytes != null) 'audio_rule': _audioInstruction(languageMode),
      if (activeLesson.isActive)
        'lesson': {
          'subject': _clip(activeLesson.subject, 30),
          'topic': _clip(activeLesson.topic, 50),
          'step': activeLesson.step,
          'activity': activeLesson.activity,
          if (activeLesson.step == 3)
            'game_question': activeLesson.gameQuestion,
          if (activeLesson.step == 3) 'game_total': activeLesson.gameTotal,
          if (activeLesson.step == 3)
            'game_correct': activeLesson.gameCorrect,
        },
      'evaluate_answer': answerCanBeEvaluated,
      if (hydrate && context.summary.isNotEmpty) 'summary': context.summary,
      if (hydrate && context.recentTurns.isNotEmpty)
        'recent_same_chat': context.recentTurns,
      if (progress['skills'] is List &&
          (progress['skills'] as List).isNotEmpty)
        'progress': progress,
      'task': _taskFor(activeLesson, answerCanBeEvaluated),
    });

    final serial = ++_requestSerial;
    _activeRequestSerial = serial;
    try {
      var response = await _runGeneration(
        serial: serial,
        envelope: envelope,
        activeLesson: activeLesson,
        imageBytes: imageBytes,
        audioBytes: audioBytes,
      );
      final inferredSubject = activeLesson.subject.trim().isNotEmpty
          ? activeLesson.subject
          : _inferSubject(normalizedText);
      final inferredTopic = activeLesson.topic.trim().isNotEmpty
          ? activeLesson.topic
          : _inferTopic(normalizedText, inferredSubject);
      response = response.copyWith(
        lesson: response.lesson.copyWith(
          subject: response.lesson.subject.trim().isEmpty
              ? inferredSubject
              : response.lesson.subject,
          topic: response.lesson.topic.trim().isEmpty
              ? inferredTopic
              : response.lesson.topic,
        ),
      );
      _sessionHydrated = true;
      return response;
    } finally {
      if (_activeRequestSerial == serial) _activeRequestSerial = null;
    }
  }

  Future<AiTutorResponse> _runGeneration({
    required int serial,
    required String envelope,
    required LessonState activeLesson,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
  }) async {
    final chat = _chat;
    if (chat == null) throw StateError('La session Gemma est indisponible.');

    final Message message;
    if (audioBytes != null && audioBytes.isNotEmpty) {
      message = Message.withAudio(
        text: envelope,
        audioBytes: audioBytes,
        isUser: true,
      );
    } else if (imageBytes != null && imageBytes.isNotEmpty) {
      message = Message.withImages(
        text: envelope,
        imageBytes: [imageBytes],
        isUser: true,
      );
    } else {
      message = Message.text(text: envelope, isUser: true);
    }

    await chat.addQueryChunk(message, true);
    _ensureActive(serial);

    final buffer = StringBuffer();
    await for (final item in chat.generateChatResponseAsync()) {
      _ensureActive(serial);
      if (item is TextResponse) buffer.write(item.token);
    }
    _ensureActive(serial);
    _turnsInSession++;

    return AiTutorResponse.parse(buffer.toString()).normalized(
      fallbackLesson: activeLesson,
      lessonMode: activeLesson.isActive,
    );
  }

  AiTutorResponse _validateProgress(
    AiTutorResponse response,
    bool answerCanBeEvaluated,
  ) {
    if (!response.progress.save || answerCanBeEvaluated) return response;
    return response.copyWith(progress: const ProgressUpdate());
  }

  Future<void> stopGeneration() async {
    _activeRequestSerial = null;
    _requestSerial++;
    if (!_isGenerating) return;
    try {
      await _chat?.stopGeneration();
    } catch (error) {
      debugPrint('Arrêt de génération : $error');
    } finally {
      _isGenerating = false;
    }
  }

  Future<void> resetConversationSession({int? conversationId}) async {
    if (_isGenerating) await stopGeneration();
    if (_model == null) {
      await createSession();
      return;
    }
    await _createChatOnly();
    _boundConversationId = conversationId;
    _sessionHydrated = false;
    _isReady = true;
  }

  Future<void> dispose() async {
    if (_isGenerating) await stopGeneration();
    await _chat?.close();
    _chat = null;
    await _model?.close();
    _model = null;
    _boundConversationId = null;
    _isReady = false;
    _supportsImageSession = false;
    _supportsAudioSession = false;
  }
}

String _taskFor(LessonState lesson, bool answerExpected) {
  if (!lesson.isActive) {
    return 'Identifie la matière et le sujet. Explique clairement comme un professeur attentif. Si la demande est un exercice, crée un exercice; si c’est un jeu ou quiz, limite-le à 2 questions.';
  }
  if (lesson.step <= 1) {
    return answerExpected
        ? 'Évalue cette réponse. Si elle est correcte, félicite brièvement et demande de passer à l’exercice. Sinon réexplique plus simplement avec une nouvelle petite question.'
        : 'Explication : explique une idée avec un exemple adapté au niveau, puis pose une seule petite question avec 2 ou 3 choix. N’écris aucun numéro d’étape.';
  }
  if (lesson.step == 2) {
    return answerExpected
        ? 'Évalue l’exercice. Bonne réponse : félicite et annonce le jeu. Erreur : montre l’erreur puis propose un exercice plus simple.'
        : 'Exercice : propose un seul exercice guidé avec 3 choix maximum. N’écris aucun numéro d’étape.';
  }
  final current = lesson.gameQuestion <= 0 ? 1 : lesson.gameQuestion;
  final game = switch (lesson.activity.toLowerCase()) {
    'true_false' || 'truefalse' || 'vrai_faux' =>
      'Vrai ou faux : une affirmation courte et exactement les choix Vrai/Faux.',
    'memory' =>
      'Jeu mémoire : une association courte avec 2 ou 3 choix.',
    'chrono' =>
      'Défi chrono : question très courte, ton énergique et 2 ou 3 choix.',
    _ => 'Quiz rapide : question courte et 2 ou 3 choix.',
  };
  return answerExpected
      ? current >= lesson.gameTotal
          ? 'Évalue la question finale. Donne un score sur ${lesson.gameTotal}, un encouragement bref et termine. Aucun choix, aucune troisième question, aucune demande de compréhension.'
          : 'Évalue la question $current sur ${lesson.gameTotal} en une phrase, puis affiche immédiatement la question ${current + 1} sur ${lesson.gameTotal}. $game Ne demande jamais si l’élève a compris.'
      : 'Jeu et quiz, question $current sur ${lesson.gameTotal}. $game Ajoute un emoji et un titre de manche. Ne propose jamais « J’ai compris » et n’écris aucun numéro d’étape.';
}

String _clip(String value, int maxLength) {
  final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= maxLength) return clean;
  return '${clean.substring(0, maxLength - 1).trimRight()}…';
}

String _inferSubject(String text) {
  final value = text.toLowerCase();
  if (RegExp(r'fraction|calcul|nombre|équation|equation|géométr|geometr|multipli|division')
      .hasMatch(value)) {
    return 'Mathématiques';
  }
  if (RegExp(r'français|francais|grammaire|conjug|orthographe|rédaction|redaction')
      .hasMatch(value)) {
    return 'Français';
  }
  if (RegExp(r'anglais|english|vocabulaire anglais|verb in english')
      .hasMatch(value)) {
    return 'Anglais';
  }
  if (RegExp(r'science|physique|chimie|biologie|svt').hasMatch(value)) {
    return 'Sciences';
  }
  return 'Autre';
}

String _inferTopic(String text, String subject) {
  final value = text.toLowerCase();
  if (value.contains('fraction')) return 'Fractions';
  if (value.contains('multipli')) return 'Multiplication';
  if (value.contains('division')) return 'Division';
  if (value.contains('conjug')) return 'Conjugaison';
  if (value.contains('grammaire')) return 'Grammaire';
  if (value.contains('orthographe')) return 'Orthographe';
  if (value.contains('vocabulaire')) return 'Vocabulaire';
  if (value.contains('physique')) return 'Physique';
  if (value.contains('chimie')) return 'Chimie';
  return subject == 'Autre' ? 'Question générale' : subject;
}
