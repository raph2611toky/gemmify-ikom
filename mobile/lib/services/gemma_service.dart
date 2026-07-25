import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../models/ai_tutor_response.dart';
import '../models/audio_language_mode.dart';
import 'background_model_download_service.dart';
import 'learning_tool_service.dart';
import 'local_learning_database.dart';

class ConversationReplayItem {
  final bool isUser;
  final String text;

  const ConversationReplayItem({
    required this.isUser,
    required this.text,
  });
}

class GenerationCancelledException implements Exception {
  const GenerationCancelledException();

  @override
  String toString() => 'GenerationCancelledException';
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
  int _requestSerial = 0;
  int? _activeRequestSerial;

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
      inferenceEngines: [LiteRtLmEngine()],
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

      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(filePath).install();
    } finally {
      _installing = false;
    }
  }

  Future<void> createSession({bool forceRecreate = false}) async {
    if (!forceRecreate && _isReady && _chat != null && _model != null) {
      return;
    }
    if (_loading) return;

    _loading = true;
    _isReady = false;

    try {
      _activeRequestSerial = null;
      _requestSerial++;
      await _chat?.stopGeneration();
      await _chat?.close();
      _chat = null;
      await _model?.close();
      _model = null;

      _model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
        supportImage: true,
        supportAudio: true,
        maxNumImages: 1,
      );

      _chat = await _model!.createChat(
        temperature: 0.25,
        topK: 20,
        tokenBuffer: 520,
        maxOutputTokens: 520,
        supportImage: true,
        supportAudio: true,
        supportsFunctionCalls: true,
        modelType: ModelType.gemma4,
        tools: LearningToolService.tools,
        toolChoice: ToolChoice.auto,
        systemInstruction: _systemInstruction,
      );

      if (!(_chat?.supportsImages ?? false)) {
        throw StateError('La session a été créée sans prise en charge des images.');
      }
      if (!(_chat?.supportAudio ?? false)) {
        throw StateError('La session a été créée sans prise en charge de l’audio.');
      }

      _isReady = true;
      debugPrint('🟢 Mpanabe AI prêt : JSON + function calling + progression');
    } finally {
      _loading = false;
    }
  }

  static const String _systemInstruction = '''
Tu es Mpanabe AI, tuteur scolaire patient pour les élèves de Madagascar.
Tu comprends le français, le malagasy et leur mélange. Adapte la difficulté au niveau réellement démontré par l’élève.

PROGRESSION:
- Quand une réponse d’élève permet une évaluation, appelle save_learning_progress.
- Quand une leçon est réellement terminée, appelle save_learning_progress avec event_type=lesson_completed, score, max_score, xp et skills.
- Pour afficher ou adapter une progression antérieure, appelle get_learning_progress.
- Ne donne jamais une note sans preuve dans la discussion.
- Après une réponse évaluée, mets à jour score, compréhension et compétences.
- Affiche ui.card=understanding après un diagnostic, activity_result à la fin d’une activité, progression quand l’élève demande son évolution.
- Les choix servent à poursuivre l’échange; mets style=button pour les grandes actions et style=chip pour les réponses courtes.
- Pour type=start_lesson, commence immédiatement l’activité demandée et garde response non vide.
- Après une explication, propose explicitement les étapes Exercice, Quiz et Jeu éducatif.
- N’appelle aucun outil de progression avant qu’une réponse de l’élève fournisse une preuve réellement évaluable.

SORTIE FINALE OBLIGATOIRE:
Après les éventuels appels d’outils, renvoie uniquement un objet JSON valide, sans markdown ni texte autour:
{
  "response":"texte pédagogique visible",
  "choices":[{"id":"id","label":"bouton","message":"message envoyé","style":"chip|button"}],
  "ui":{"card":"none|understanding|activity_result|progression"},
  "lesson":{"course_id":"","subject":"","topic":"","status":"none|in_progress|completed"},
  "assessment":{"score":null,"max_score":null,"understanding":0,"xp":0,"level_label":"","current_xp":0,"next_level_xp":0,"streak_days":0,"learning_time":"","skills":[{"id":"","label":"","mastery":0,"status":"mastered|in_progress|discover|reinforce","evidence":""}]},
  "memory":{"title":"titre court de la discussion","summary":"résumé cumulatif très court"}
}
Règles: choices=[] s’il n’y a rien à choisir. Une question pédagogique doit proposer des choices utiles. La clé response est toujours présente. Le résumé memory.summary conserve uniquement les faits utiles des anciens échanges.
''';

  Future<void> restoreConversation(
    List<ConversationReplayItem> history, {
    int maxMessages = 8,
  }) async {
    final chat = _chat;
    if (chat == null || history.isEmpty) return;
    if (chat.fullHistory.isNotEmpty) return;

    final usable = history
        .where((entry) => entry.text.trim().isNotEmpty)
        .toList(growable: false);
    final start = usable.length > maxMessages ? usable.length - maxMessages : 0;
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
  }

  void _ensureRequestActive(int requestSerial) {
    if (_activeRequestSerial != requestSerial) {
      throw const GenerationCancelledException();
    }
  }

  Future<AiTutorResponse> sendTutorMessage({
    required int conversationId,
    required String text,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    AudioLanguageMode languageMode = AudioLanguageMode.mixed,
  }) async {
    final chat = _chat;
    if (chat == null) {
      throw StateError('Session non initialisée. Appelle createSession().');
    }
    if (imageBytes != null && audioBytes != null) {
      throw ArgumentError('Un seul contenu multimodal par message est autorisé.');
    }

    final progressJson =
        await LocalLearningDatabase.instance.buildCompactProgressJson();
    final normalizedText = text.trim();
    final envelope = jsonEncode({
      'type': audioBytes != null
          ? 'student_audio'
          : imageBytes != null
              ? 'student_image'
              : 'student_message',
      'conversation_id': conversationId,
      'message': normalizedText,
      'audio_instruction': audioBytes == null
          ? null
          : _directAudioInstructionFor(languageMode),
      'known_progress': jsonDecode(progressJson),
    });

    final Message message;
    if (audioBytes != null && audioBytes.isNotEmpty) {
      if (!chat.supportAudio) {
        throw StateError('La session ne prend pas en charge l’audio.');
      }
      message = Message.withAudio(
        text: envelope,
        audioBytes: audioBytes,
        isUser: true,
      );
    } else if (imageBytes != null && imageBytes.isNotEmpty) {
      if (!chat.supportsImages) {
        throw StateError('La session ne prend pas en charge les images.');
      }
      message = Message.withImages(
        text: envelope,
        imageBytes: [imageBytes],
        isUser: true,
      );
    } else {
      if (normalizedText.isEmpty) {
        throw ArgumentError('Le message texte est vide.');
      }
      message = Message.text(text: envelope, isUser: true);
    }

    final requestSerial = ++_requestSerial;
    _activeRequestSerial = requestSerial;

    try {
      await chat.addQueryChunk(message);
      _ensureRequestActive(requestSerial);
      return await _generateWithTools(
        conversationId: conversationId,
        requestSerial: requestSerial,
      );
    } finally {
      if (_activeRequestSerial == requestSerial) {
        _activeRequestSerial = null;
      }
    }
  }

  Future<AiTutorResponse> _generateWithTools({
    required int conversationId,
    required int requestSerial,
  }) async {
    final chat = _chat!;
    var progressSavedByFunction = false;

    for (var round = 0; round < 3; round++) {
      _ensureRequestActive(requestSerial);
      final buffer = StringBuffer();
      final calls = <FunctionCallResponse>[];

      try {
        await for (final response in chat.generateChatResponseAsync()) {
          _ensureRequestActive(requestSerial);
          if (response is TextResponse) {
            buffer.write(response.token);
          } else if (response is FunctionCallResponse) {
            calls.add(response);
          } else if (response is ParallelFunctionCallResponse) {
            calls.addAll(response.calls);
          }
        }
      } catch (_) {
        _ensureRequestActive(requestSerial);
        rethrow;
      }

      _ensureRequestActive(requestSerial);

      if (calls.isEmpty) {
        final raw = buffer.toString().trim();
        if (raw.isEmpty) {
          return const AiTutorResponse(
            response:
                'Je n’ai pas reçu de réponse complète du modèle. Appuie sur une option ou reformule en une phrase courte.',
            choices: [
              TutorChoice(
                id: 'retry_explanation',
                label: 'Réessayer',
                message: 'Recommence avec une explication très courte.',
                style: 'button',
              ),
            ],
          );
        }

        final parsed = AiTutorResponse.parse(raw);
        await _persistStructuredAssessmentIfNeeded(
          conversationId: conversationId,
          response: parsed,
          alreadySavedByFunction: progressSavedByFunction,
        );
        return parsed;
      }

      for (final call in calls) {
        _ensureRequestActive(requestSerial);
        debugPrint('🛠️ Function call: ${call.name} ${call.args}');
        final arguments = Map<String, dynamic>.from(call.args);
        final toolResult = await LearningToolService.instance.execute(
          conversationId: conversationId,
          name: call.name,
          arguments: arguments,
        );
        _ensureRequestActive(requestSerial);
        if (call.name == 'save_learning_progress') {
          progressSavedByFunction = true;
        }
        await chat.addQueryChunk(
          Message.toolResponse(
            toolName: call.name,
            response: toolResult,
          ),
        );
      }
    }

    _ensureRequestActive(requestSerial);
    return const AiTutorResponse(
      response:
          'La progression a été enregistrée. Choisis maintenant la prochaine étape.',
      choices: [
        TutorChoice(
          id: 'continue_explanation',
          label: 'Continuer la leçon',
          message: 'Continue la leçon à l’étape suivante.',
          style: 'button',
        ),
        TutorChoice(
          id: 'start_exercise',
          label: 'Faire un exercice',
          message: 'Propose-moi un exercice adapté.',
          style: 'button',
        ),
      ],
    );
  }

  Future<void> _persistStructuredAssessmentIfNeeded({
    required int conversationId,
    required AiTutorResponse response,
    required bool alreadySavedByFunction,
  }) async {
    if (alreadySavedByFunction || response.skills.isEmpty) return;

    final hasEvidence = response.lessonCompleted ||
        response.score != null ||
        (response.understanding > 0 &&
            response.skills.any((skill) => skill.evidence.isNotEmpty));
    if (!hasEvidence) return;

    // Filet de sécurité : le chemin normal reste le function calling. Cette
    // écriture évite toutefois de perdre une note structurée si le modèle a
    // produit le JSON final sans appeler l’outil malgré les instructions.
    await LocalLearningDatabase.instance.applyProgressFunction(
      conversationId: conversationId,
      arguments: {
        'event_type': response.lessonCompleted
            ? 'lesson_completed'
            : 'answer_evaluated',
        'course_id': response.courseId,
        'subject': response.subject,
        'topic': response.topic,
        if (response.score != null) 'score': response.score,
        if (response.maxScore != null) 'max_score': response.maxScore,
        'understanding': response.understanding,
        'xp': response.xp,
        'summary': response.summary,
        'lesson_completed': response.lessonCompleted,
        'skills': response.skills
            .map(
              (skill) => {
                ...skill.toJson(),
                'correct': skill.status == 'mastered',
                'xp': 0,
              },
            )
            .toList(growable: false),
      },
    );
  }

  Future<AiTutorResponse> sendAudioTutorMessage({
    required int conversationId,
    required Uint8List audioBytes,
    required AudioLanguageMode languageMode,
  }) {
    if (audioBytes.length <= 44) {
      throw ArgumentError('Le message vocal est vide ou invalide.');
    }
    return sendTutorMessage(
      conversationId: conversationId,
      text: _directAudioInstructionFor(languageMode),
      audioBytes: audioBytes,
      languageMode: languageMode,
    );
  }

  Stream<String> sendMessageStream({
    required String text,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
  }) async* {
    final conversationId =
        await LocalLearningDatabase.instance.getOrCreateActiveConversation();
    final result = await sendTutorMessage(
      conversationId: conversationId,
      text: text,
      imageBytes: imageBytes,
      audioBytes: audioBytes,
    );
    yield result.response;
  }

  Future<void> stopGeneration() async {
    _activeRequestSerial = null;
    _requestSerial++;
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
