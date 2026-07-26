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
      maxOutputTokens: 320,
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
Tu es Mpanabe AI, professeur clair et patient pour un élève à Madagascar.
Retourne uniquement UN objet JSON compact, fermé par }, puis arrête.

Sans choix :
{"response":"texte","subject":"matière","topic":"sujet","action":"none"}
Avec choix :
{"response":"question","choices":["choix 1","choix 2"],"subject":"matière","topic":"sujet","action":"wait_answer"}
Après une réponse évaluée, ajoute éventuellement :
{"evaluation":{"skill":"compétence","correct":true}}

Règles obligatoires :
- Respecte `language_rule`. Utilise seulement le français ou le malagasy en alphabet latin. Jamais d'autre langue ni d'autre écriture.
- `response` doit être complète, simple et courte : respecte `response_limit_words`.
- Explication : une seule idée et un seul exemple.
- Exercice initial : une seule question, sans donner la solution.
- Ne recopie jamais les choix dans `response`; mets-les seulement dans `choices`.
- Les choix doivent être courts, distincts et au nombre de 2 ou 3.
- Jeu/quiz : 2 manches, une seule question affichée à la fois.
- Vrai/faux : exactement ["Vrai","Faux"].
- Après la manche 1 : correction en une phrase puis manche 2.
- Après la manche 2 : score final et encouragement, sans nouvelle question.
- N'écris jamais Étape 1, Étape 2 ou Étape 3.
- Omet `choices` sans question. Omet `evaluation` sans réponse évaluée.
- Les scores, points et niveaux sont calculés localement.
- Aucun texte avant ou après le JSON.
''';

  static String _audioInstruction(AudioLanguageMode mode) {
    switch (mode) {
      case AudioLanguageMode.malagasy:
        return 'Valio amin’ny teny malagasy. Aza aseho ny transcription.';
      case AudioLanguageMode.mixed:
        return 'Réponds en malagasy ou en français selon le message, sans transcription.';
      case AudioLanguageMode.french:
        return 'Réponds en français clair sans afficher la transcription.';
    }
  }

  static String _responseLanguageInstruction(AudioLanguageMode mode) {
    switch (mode) {
      case AudioLanguageMode.malagasy:
        return 'Réponds uniquement en malagasy avec l’alphabet latin.';
      case AudioLanguageMode.mixed:
        return 'Réponds dans la langue du message, uniquement en français ou '
            'en malagasy avec l’alphabet latin. N’utilise aucune autre langue.';
      case AudioLanguageMode.french:
        return 'Réponds uniquement en français avec l’alphabet latin.';
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
    void Function(String text)? onPartialResponse,
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
        onPartialResponse: onPartialResponse,
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
    void Function(String text)? onPartialResponse,
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
      'language_rule': _responseLanguageInstruction(languageMode),
      if (audioBytes != null) 'audio_rule': _audioInstruction(languageMode),
      'response_limit_words': _responseWordLimit(
        activeLesson,
        answerCanBeEvaluated,
        hasImage: imageBytes != null,
      ),
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
      'task': _taskFor(
        activeLesson,
        answerCanBeEvaluated,
        hasImage: imageBytes != null,
      ),
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
        onPartialResponse: onPartialResponse,
      );

      // Un JSON coupé ne doit plus enfermer l'utilisateur dans une boucle
      // « Reprendre ». On effectue un seul rattrapage automatique et compact.
      if (response.wasTruncated) {
        // Ne jamais effacer le texte déjà visible pendant le rattrapage.
        // Le second flux remplacera progressivement l'ancien seulement
        // lorsqu'un nouveau texte utile sera réellement disponible.
        final compactPayload = Map<String, dynamic>.from(
          jsonDecode(envelope) as Map,
        );
        compactPayload
          ..remove('summary')
          ..remove('recent_same_chat')
          ..remove('progress')
          ..['response_limit_words'] = 24
          ..['task'] =
              '${_taskFor(activeLesson, answerCanBeEvaluated, hasImage: imageBytes != null)} '
              'Rattrapage unique : réponse complète en 16 à 24 mots. '
              'JSON minimal, valide et fermé immédiatement.'
          ..['compact_retry'] = true;

        response = await _runGeneration(
          serial: serial,
          envelope: jsonEncode(compactPayload),
          activeLesson: activeLesson,
          imageBytes: imageBytes,
          audioBytes: audioBytes,
          onPartialResponse: (text) {
            if (text.trim().isNotEmpty) onPartialResponse?.call(text);
          },
        );
      }

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
    void Function(String text)? onPartialResponse,
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
    var lastPartial = '';
    await for (final item in chat.generateChatResponseAsync()) {
      _ensureActive(serial);
      if (item is! TextResponse) continue;
      buffer.write(item.token);

      // Gemma renvoie du JSON. On n'affiche que la valeur de `response`,
      // jamais les accolades ou les champs techniques.
      final partial = _sanitizeStreamingPreview(
        _extractPartialResponse(buffer.toString()),
      );
      if (partial.isNotEmpty && partial != lastPartial) {
        lastPartial = partial;
        onPartialResponse?.call(partial);
      }
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


int _responseWordLimit(
  LessonState lesson,
  bool answerExpected, {
  bool hasImage = false,
}) {
  if (hasImage) return 55;
  if (!lesson.isActive) return 45;
  if (lesson.step <= 1) return answerExpected ? 35 : 45;
  if (lesson.step == 2) return answerExpected ? 35 : 25;
  // Les jeux doivent rester très courts pour laisser assez de place au JSON
  // complet, même sur les appareils lents.
  return answerExpected ? 24 : 20;
}

/// Empêche l'affichage de scripts inattendus pendant le flux (le modèle
/// local peut parfois dériver vers une autre écriture). Le résultat final
/// reste validé par le parseur JSON.
String _sanitizeStreamingPreview(String value) {
  if (value.isEmpty) return '';

  final output = StringBuffer();
  for (final rune in value.runes) {
    final allowed = rune == 0x0A ||
        rune == 0x0D ||
        rune == 0x09 ||
        (rune >= 0x20 && rune <= 0x7E) ||
        (rune >= 0x00A0 && rune <= 0x024F) ||
        (rune >= 0x2000 && rune <= 0x206F) ||
        (rune >= 0x2190 && rune <= 0x22FF) ||
        (rune >= 0x1F000 && rune <= 0x1FAFF);
    if (allowed) output.writeCharCode(rune);
  }

  return output
      .toString()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trimRight();
}

String _taskFor(
  LessonState lesson,
  bool answerExpected, {
  bool hasImage = false,
}) {
  if (hasImage && !lesson.isActive) {
    return 'Observe attentivement l’image. Si elle montre un devoir ou un '
        'exercice déjà rempli, corrige-le précisément : indique ce qui est '
        'juste, ce qui est faux, donne la bonne réponse et une note seulement '
        'si un barème est visible. Si l’image contient uniquement un énoncé '
        'ou un cours, identifie la matière puis explique sans inventer.';
  }

  if (hasImage && lesson.isActive) {
    return answerExpected
        ? 'Considère l’image comme la réponse de l’élève à l’étape en cours. '
            'Lis ce qui est visible, corrige précisément, explique l’erreur '
            'éventuelle et évalue uniquement ce que l’image permet de vérifier.'
        : 'Observe l’image dans le contexte de la leçon. Si elle contient une '
            'réponse déjà rédigée, corrige-la; sinon explique l’énoncé visible '
            'et poursuis l’étape actuelle sans inventer de contenu.';
  }

  if (!lesson.isActive) {
    return 'Identifie la matière et le sujet. Explique clairement comme un '
        'professeur attentif. Si la demande est un exercice, crée un exercice; '
        'si c’est un jeu ou quiz, limite-le à 2 questions.';
  }
  if (lesson.step <= 1) {
    return answerExpected
        ? 'Évalue cette réponse. Si elle est correcte, félicite brièvement et '
            'demande de passer à l’exercice. Sinon réexplique plus simplement '
            'avec une nouvelle petite question.'
        : 'Explication : explique une seule idée avec un exemple très court. '
            'Puis pose une seule question avec 2 ou 3 choix distincts. '
            'Ne répète pas les choix dans le texte et ne numérote aucune étape.';
  }
  if (lesson.step == 2) {
    return answerExpected
        ? 'Évalue l’exercice. Bonne réponse : félicite et annonce le jeu. '
            'Erreur : montre l’erreur puis propose un exercice plus simple.'
        : 'Exercice : donne uniquement un seul énoncé court à résoudre, '
            'sans solution ni correction. Ajoute 2 ou 3 choix distincts dans '
            'le champ choices seulement. Ne répète pas les choix dans response.';
  }
  final current = lesson.gameQuestion <= 0 ? 1 : lesson.gameQuestion;
  final differentRound = current > 1
      ? 'La nouvelle question doit être différente de la manche précédente. '
      : '';
  final game = switch (lesson.activity.toLowerCase()) {
    'true_false' || 'truefalse' || 'vrai_faux' =>
      '${differentRound}Vrai ou faux : une affirmation courte et exactement les choix Vrai/Faux.',
    'memory' => '${differentRound}Jeu mémoire : une association courte avec 2 ou 3 choix.',
    'chrono' =>
      '${differentRound}Défi chrono : question très courte, ton énergique et 2 ou 3 choix.',
    _ => '${differentRound}Quiz rapide : question courte et 2 ou 3 choix.',
  };
  return answerExpected
      ? current >= lesson.gameTotal
          ? 'Évalue la question finale. Donne un score sur ${lesson.gameTotal}, '
              'un encouragement bref et termine. Aucun choix, aucune troisième '
              'question, aucune demande de compréhension.'
          : 'Évalue la question $current sur ${lesson.gameTotal} en une phrase, '
              'puis affiche immédiatement une question ${current + 1} sur '
              '${lesson.gameTotal}, différente de la précédente. $game '
              'Ne demande jamais si l’élève a compris.'
      : 'Jeu et quiz, question $current sur ${lesson.gameTotal}. $game Ajoute '
          'un emoji et un titre de manche. Ne propose jamais « J’ai compris » '
          'et n’écris aucun numéro d’étape.';
}

/// Extrait progressivement le texte du champ JSON `response`.
///
/// La génération locale fournit des morceaux de JSON. Cette fonction décode
/// les échappements déjà complets et ignore silencieusement une séquence
/// inachevée en fin de flux.
String _extractPartialResponse(String raw) {
  final marker = RegExp(r'"response"\s*:\s*"');
  final match = marker.firstMatch(raw);
  if (match == null) return '';

  final output = StringBuffer();
  var index = match.end;
  while (index < raw.length) {
    final char = raw[index];
    if (char == '"') break;
    if (char != '\\') {
      output.write(char);
      index++;
      continue;
    }

    if (index + 1 >= raw.length) break;
    final escaped = raw[index + 1];
    if (escaped == 'n') {
      output.write('\n');
      index += 2;
      continue;
    }
    if (escaped == 'r') {
      output.write('\r');
      index += 2;
      continue;
    }
    if (escaped == 't') {
      output.write('\t');
      index += 2;
      continue;
    }
    if (escaped == 'b') {
      output.write('\b');
      index += 2;
      continue;
    }
    if (escaped == 'f') {
      output.write('\f');
      index += 2;
      continue;
    }
    if (escaped == '"') {
      output.write('"');
      index += 2;
      continue;
    }
    if (escaped == '\\') {
      output.write('\\');
      index += 2;
      continue;
    }
    if (escaped == '/') {
      output.write('/');
      index += 2;
      continue;
    }
    if (escaped == 'u') {
      if (index + 6 > raw.length) return output.toString();
      final hex = raw.substring(index + 2, index + 6);
      final codePoint = int.tryParse(hex, radix: 16);
      if (codePoint == null) return output.toString();
      output.writeCharCode(codePoint);
      index += 6;
      continue;
    }

    // Le modèle peut exceptionnellement produire un échappement non JSON.
    // On conserve le caractère utile au lieu d'afficher l'antislash.
    output.write(escaped);
    index += 2;
  }
  return output.toString();
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
