import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/ai_tutor_response.dart';
import '../models/audio_language_mode.dart';
import '../models/chat_message.dart';
import '../services/gemma_service.dart';
import '../services/local_auth_service.dart';
import '../services/local_learning_database.dart';
import '../services/voice_interaction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';
import 'auth/welcome_screen.dart';
import 'online_tools_screen.dart';

enum _LessonSetupStage {
  idle,
  choosingTopic,
  awaitingCustomTopic,
  choosingActivity,
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();
  final _db = LocalLearningDatabase.instance;
  final _gemma = GemmaService();
  final _voice = VoiceInteractionService.instance;

  final List<ChatMessage> _messages = [];
  final List<StoredConversation> _conversations = [];

  int? _conversationId;
  int _messageCounter = 1;
  int _generationSerial = 0;
  bool _initializing = true;
  bool _isGuestMode = false;
  bool _modelReady = false;
  bool _isGenerating = false;
  String _studentName = '';
  String _generationLabel = 'Préparation de la réponse…';
  String _drawerQuery = '';

  LessonState _activeLesson = const LessonState();
  _LessonSetupStage _setupStage = _LessonSetupStage.idle;
  String _selectedTopic = '';
  String _selectedSubject = '';
  String? _presetActivity;
  AudioLanguageMode _languageMode = AudioLanguageMode.french;

  bool get _hasConversationContent => _messages.isNotEmpty;
  bool get _answerCanBeEvaluated =>
      _activeLesson.isActive && _activeLesson.awaitingAnswer;
  bool get _isMalagasy => _languageMode.normalized.isMalagasy;
  String _tr(String french, String malagasy) =>
      _isMalagasy ? malagasy : french;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await _db.runMaintenance();
      _languageMode = (await _db.loadLanguageMode()).normalized;
      _isGuestMode = await _db.isGuestMode();
      final profile = await _db.loadLocalProfile();
      _studentName = profile?['first_name']?.toString().trim() ?? '';

      final id = await _db.getOrCreateActiveConversation();
      await _loadConversation(id, resetGemma: false);

      // L'interface est déjà visible pendant que le moteur local se prépare.
      unawaited(_prepareLocalServices());
    } catch (error) {
      if (!mounted) return;
      setState(() => _initializing = false);
      _showSnack('Impossible d’initialiser le chatbot : $error');
    }
  }

  Future<void> _prepareLocalServices() async {
    try {
      // Le TTS est initialisé seulement lorsque l'utilisateur appuie sur
      // lecture. On évite ainsi de démarrer plusieurs services au lancement.
      await _gemma.createSession();
      if (!mounted) return;
      setState(() => _modelReady = true);
    } on ModelNotActiveException {
      if (!mounted) return;
      setState(() => _modelReady = false);
      _openModelPreparation();
    } catch (error) {
      if (!mounted) return;
      setState(() => _modelReady = false);
      _showSnack('Le moteur IA sera relancé au premier message.');
    }
  }

  Future<bool> _ensureModelReady() async {
    if (_modelReady) return true;
    if (!mounted) return false;

    setState(() {
      _isGenerating = true;
      _generationLabel = 'Préparation de Mpanabe AI…';
    });

    try {
      await _gemma.createSession();
      if (!mounted) return false;
      setState(() {
        _modelReady = true;
        _isGenerating = false;
      });
      return true;
    } on ModelNotActiveException {
      if (!mounted) return false;
      setState(() => _isGenerating = false);
      _openModelPreparation();
      return false;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _isGenerating = false);
      _showSnack('Impossible de préparer le moteur IA : $error');
      return false;
    }
  }

  void _openModelPreparation() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/model');
    });
  }

  Future<void> _loadConversation(
    int conversationId, {
    bool resetGemma = true,
  }) async {
    if (resetGemma) await _gemma.activateConversation(conversationId);
    await _db.setActiveConversation(conversationId);

    final stored = await _db.loadMessages(conversationId);
    final conversations = await _db.listConversations();
    final restored = <ChatMessage>[];

    for (final item in stored) {
      AiTutorResponse? response;
      if (!item.isUser && item.structuredJson?.trim().isNotEmpty == true) {
        response = AiTutorResponse.parse(
          item.structuredJson!,
          languageMode: item.languageMode,
        );
      }
      restored.add(
        ChatMessage(
          id: 'db-${item.id}',
          isUser: item.isUser,
          text: item.isUser
              ? item.text
              : response?.response.trim().isNotEmpty == true
                  ? response!.response
                  : normalizeTutorMarkdown(item.text),
          tutorResponse: response,
          audioPlaceholder: item.modality == 'audio',
          audioDuration: item.audioDurationMs == null
              ? null
              : Duration(milliseconds: item.audioDurationMs!),
          voiceLanguageMode: item.languageMode,
          createdAt: DateTime.fromMillisecondsSinceEpoch(item.createdAt),
          choicesEnabled: false,
        ),
      );
    }

    if (restored.isNotEmpty &&
        !restored.last.isUser &&
        restored.last.tutorResponse?.choices.isNotEmpty == true) {
      restored.last.choicesEnabled = true;
    }

    LessonState lesson = const LessonState();
    _LessonSetupStage stage = _LessonSetupStage.idle;
    String topic = '';
    String subject = '';
    for (final message in restored.reversed) {
      final response = message.tutorResponse;
      if (response == null) continue;
      if (lesson.courseId.isEmpty &&
          (response.lesson.isActive || response.lesson.completed)) {
        lesson = response.lesson;
      }
      if (stage == _LessonSetupStage.idle) {
        switch (response.flow) {
          case 'lesson_topic':
            stage = _LessonSetupStage.choosingTopic;
            break;
          case 'custom_lesson_topic':
            stage = _LessonSetupStage.awaitingCustomTopic;
            break;
          case 'lesson_activity':
            stage = _LessonSetupStage.choosingActivity;
            break;
        }
      }
      if (topic.isEmpty && response.lesson.topic.isNotEmpty) {
        topic = response.lesson.topic;
      }
      if (subject.isEmpty && response.lesson.subject.isNotEmpty) {
        subject = response.lesson.subject;
      }
    }

    if (!mounted) return;
    setState(() {
      _conversationId = conversationId;
      _messages
        ..clear()
        ..addAll(restored);
      _conversations
        ..clear()
        ..addAll(conversations);
      _messageCounter = stored.length + 1;
      _activeLesson = lesson.completed ? const LessonState() : lesson;
      _setupStage = stage;
      _selectedTopic = topic;
      _selectedSubject = subject;
      _initializing = false;
      _generationSerial++;
      _isGenerating = false;
    });
    _closeDrawer();
    _scrollToBottom(jump: true);
  }

  Future<int> _ensureConversationId() async {
    final current = _conversationId;
    if (current != null) return current;
    final id = await _db.getOrCreateActiveConversation();
    _conversationId = id;
    return id;
  }

  Future<void> _refreshConversations() async {
    final values = await _db.listConversations();
    if (!mounted) return;
    setState(() {
      _conversations
        ..clear()
        ..addAll(values);
    });
  }

  Future<void> _newConversation() async {
    if (_isGenerating) await _stopGeneration();
    final id = await _db.createConversation();
    if (!mounted) return;
    await _loadConversation(id);
  }

  Future<void> _switchConversation(int id) async {
    if (id == _conversationId) {
      _closeDrawer();
      return;
    }
    if (_isGenerating) await _stopGeneration();
    await _loadConversation(id);
  }

  Future<void> _renameConversation(StoredConversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renommer la discussion'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            hintText: 'Titre',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (text) => Navigator.pop(dialogContext, text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value?.trim().isEmpty != false) return;
    await _db.renameConversation(conversation.id, value!.trim());
    await _refreshConversations();
  }

  Future<void> _deleteConversation(StoredConversation conversation) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer cette discussion ?'),
            content: Text('« ${conversation.title} » sera supprimée.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text(
                  'Supprimer',
                  style: TextStyle(color: AppTheme.error),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await _db.deleteConversation(conversation.id);
    if (conversation.id == _conversationId) {
      final remaining = await _db.listConversations();
      final id = remaining.isEmpty
          ? await _db.createConversation()
          : remaining.first.id;
      await _loadConversation(id);
    } else {
      await _refreshConversations();
    }
  }

  void _closeDrawer() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _startLessonSetup({String? presetActivity}) async {
    if (_isGenerating) return;
    _presetActivity = presetActivity;
    _setupStage = _LessonSetupStage.choosingTopic;
    _activeLesson = const LessonState();

    final response = AiTutorResponse.local(
      response: _tr(
        'Quelle leçon veux-tu travailler ? Choisis un thème ou écris le tien avec « Autre ».',
        'Inona ny lesona tianao hianarana? Misafidiana lohahevitra iray na soraty ao amin’ny « Hafa » ny anao.',
      ),
      flow: 'lesson_topic',
      choices: _isMalagasy
          ? const [
              TutorChoice(
                id: 'topic_fractions',
                label: 'Ampahany',
                message: 'Te hianatra momba ny ampahany aho.',
              ),
              TutorChoice(
                id: 'topic_multiplication',
                label: 'Fampitomboana',
                message: 'Te hianatra fampitomboana aho.',
              ),
              TutorChoice(
                id: 'topic_conjugaison',
                label: 'Fampiasana matoanteny',
                message: 'Te hianatra fampiasana matoanteny aho.',
              ),
              TutorChoice(
                id: 'topic_sciences',
                label: 'Siansa',
                message: 'Te hianatra lesona momba ny siansa aho.',
              ),
              TutorChoice(
                id: 'topic_other',
                label: 'Hafa',
                message: 'Te hisafidy lesona hafa aho.',
              ),
            ]
          : const [
              TutorChoice(
                id: 'topic_fractions',
                label: 'Fractions',
                message: 'Je veux apprendre les fractions.',
              ),
              TutorChoice(
                id: 'topic_multiplication',
                label: 'Multiplication',
                message: 'Je veux apprendre la multiplication.',
              ),
              TutorChoice(
                id: 'topic_conjugaison',
                label: 'Conjugaison',
                message: 'Je veux apprendre la conjugaison.',
              ),
              TutorChoice(
                id: 'topic_sciences',
                label: 'Sciences',
                message: 'Je veux apprendre une leçon de sciences.',
              ),
              TutorChoice(
                id: 'topic_other',
                label: 'Autre',
                message: 'Je veux choisir une autre leçon.',
              ),
            ],
    );
    await _appendLocalTurn(
      userText: presetActivity == null
          ? _tr('Apprendre une leçon', 'Hianatra lesona')
          : _activityLabel(presetActivity, malagasy: _isMalagasy),
      response: response,
    );
  }

  AiTutorResponse _buildGameMenuResponse({String? intro}) {
    final lesson = _activeLesson.copyWith(
      step: 3,
      totalSteps: 3,
      stage: _stageForStep(3, malagasy: _isMalagasy),
      awaitingAnswer: false,
      completed: false,
      gameQuestion: 0,
      gameTotal: 2,
      gameCorrect: 0,
    );
    return AiTutorResponse.local(
      response: [
        if (intro?.trim().isNotEmpty == true) intro!.trim(),
        _tr('## 🎮 Choisis ton jeu éducatif', '## 🎮 Fidio ny lalao fanabeazana'),
        _tr(
          'Cette dernière étape permet de vérifier ce que tu as compris en jouant.',
          'Ity ampahany farany ity dia manamarina izay azonao amin’ny alalan’ny lalao.',
        ),
      ].join('\n\n'),
      flow: 'game_menu',
      action: 'wait_answer',
      lesson: lesson,
      choices: _isMalagasy
          ? const [
              TutorChoice(
                id: 'game_quiz',
                label: 'Lalao fanontaniana fohy',
                message: 'Atombohy ny lalao misy fanontaniana roa, iray isaky ny mandeha.',
              ),
              TutorChoice(
                id: 'game_memory',
                label: 'Fitadidiana',
                message: 'Atombohy lalao fitadidiana misy fanamby 2, iray isaky ny mandeha.',
              ),
              TutorChoice(
                id: 'game_chrono',
                label: 'Fanamby ara-potoana',
                message: 'Atombohy fanamby ara-potoana misy fanontaniana 2, iray isaky ny mandeha.',
              ),
              TutorChoice(
                id: 'game_true_false',
                label: 'Marina sa diso',
                message: 'Atombohy marina sa diso misy fehezanteny 2, iray isaky ny mandeha.',
              ),
            ]
          : const [
              TutorChoice(
                id: 'game_quiz',
                label: 'Quiz rapide',
                message: 'Lance un mini quiz de 2 questions, une question à la fois.',
              ),
              TutorChoice(
                id: 'game_memory',
                label: 'Mémoire',
                message: 'Lance un mini jeu de mémoire en 2 défis, un défi à la fois.',
              ),
              TutorChoice(
                id: 'game_chrono',
                label: 'Défi chrono',
                message: 'Lance un défi chrono de 2 questions, une question à la fois.',
              ),
              TutorChoice(
                id: 'game_true_false',
                label: 'Vrai ou faux',
                message: 'Lance un vrai ou faux de 2 affirmations, une à la fois.',
              ),
            ],
    );
  }

  Future<void> _startSelectedLesson({
    required String activity,
    required String visibleUserText,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final courseId = '${_slug(_selectedTopic)}_$now';
    final normalizedActivity = activity == 'explanation' ? 'lesson' : activity;
    final step = switch (normalizedActivity) {
      'exercise' => 2,
      'quiz' || 'game' || 'memory' || 'chrono' || 'true_false' => 3,
      _ => 1,
    };
    final lesson = LessonState(
      courseId: courseId,
      subject: _selectedSubject,
      topic: _selectedTopic,
      activity: normalizedActivity,
      stage: _stageForStep(step, malagasy: _isMalagasy),
      step: step,
      totalSteps: 3,
      awaitingAnswer: false,
      gameQuestion: step == 3 && normalizedActivity != 'game' ? 1 : 0,
      gameTotal: 2,
      gameCorrect: 0,
    );
    setState(() {
      _activeLesson = lesson;
      _setupStage = _LessonSetupStage.idle;
      _presetActivity = null;
    });

    if (normalizedActivity == 'game') {
      await _appendLocalTurn(
        userText: visibleUserText,
        response: _buildGameMenuResponse(),
      );
      return;
    }

    final instruction = switch (step) {
      2 => _tr(
          'Commence directement un exercice sur « $_selectedTopic ». Propose un seul exercice guidé, clair, avec 2 ou 3 choix. Le titre affiché doit être simplement « Exercice ».',
          'Manomboha fanazaran-tena iray momba ny « $_selectedTopic ». Omeo fanazaran-tena iray fohy sy mazava misy safidy roa na telo. Soraty amin’ny teny malagasy ihany.',
        ),
      3 => _tr(
          'Commence « Jeu et quiz » sur « $_selectedTopic » avec le mode $normalizedActivity. Le jeu contient exactement 2 questions. Donne la question 1 sur 2 avec 2 ou 3 choix, sans numéro d’étape.',
          'Manomboha lalao momba ny « $_selectedTopic » amin’ny fomba $normalizedActivity. Fanontaniana 2 ihany ny lalao. Omeo ny fanontaniana voalohany misy safidy 2 na 3 amin’ny teny malagasy.',
        ),
      _ => _tr(
          'Commence une explication sur « $_selectedTopic ». Explique pédagogiquement avec un exemple concret, puis pose une seule petite question avec 2 ou 3 choix. Le titre doit être « Explication ».',
          'Manomboha fanazavana momba ny « $_selectedTopic ». Hazavao amin’ny teny malagasy miaraka amin’ny ohatra iray, avy eo mametraha fanontaniana kely iray misy safidy 2 na 3.',
        ),
    };

    await _generateTurn(
      visibleUserText: visibleUserText,
      modelText: instruction,
      activeLessonOverride: lesson,
    );
  }

  Future<void> _advanceToExercise(String visibleUserText) async {
    if (!_activeLesson.isActive || _activeLesson.step > 1) return;
    final lesson = _activeLesson.copyWith(
      step: 2,
      totalSteps: 3,
      stage: _stageForStep(2, malagasy: _isMalagasy),
      activity: 'exercise',
      awaitingAnswer: false,
      completed: false,
    );
    setState(() => _activeLesson = lesson);
    await _generateTurn(
      visibleUserText: visibleUserText,
      modelText: _tr(
        'Passe directement à un exercice guidé sur « ${lesson.topic} » avec 2 ou 3 choix. Ne demande pas si l’élève a compris et n’écris aucun numéro d’étape.',
        'Mandehana avy hatrany amin’ny fanazaran-tena momba ny « ${lesson.topic} » misy safidy roa na telo. Soraty amin’ny teny malagasy ihany.',
      ),
      activeLessonOverride: lesson,
    );
  }

  Future<void> _requestHintWithoutEvaluation({
    required String visibleUserText,
    required String instruction,
  }) async {
    if (!_activeLesson.isActive) return;
    final lesson = _activeLesson.copyWith(awaitingAnswer: false);
    setState(() => _activeLesson = lesson);
    await _generateTurn(
      visibleUserText: visibleUserText,
      modelText: instruction,
      activeLessonOverride: lesson,
    );
  }

  Future<void> _handleChoice(ChatMessage source, TutorChoice choice) async {
    if (_isGenerating || !source.choicesEnabled) return;
    setState(() {
      source.choicesEnabled = false;
      source.selectedChoiceId = choice.id;
    });

    // « J’ai compris » ne doit jamais être envoyé à Gemma comme une réponse
    // évaluée. Il fait avancer localement l’explication vers l’exercice.
    if ((choice.id == 'continue_to_exercise' || choice.id == 'understood') &&
        _activeLesson.isActive &&
        _activeLesson.step <= 1) {
      await _advanceToExercise(choice.label);
      return;
    }

    if (choice.id == 'exercise_hint' &&
        _activeLesson.isActive &&
        _activeLesson.step == 2) {
      await _requestHintWithoutEvaluation(
        visibleUserText: choice.label,
        instruction: _tr(
          'Donne un indice très court pour le même exercice, puis répète exactement la question avec 2 ou 3 choix. N’évalue rien.',
          'Omeo soso-kevitra fohy ho an’ilay fanazaran-tena, avy eo avereno ilay fanontaniana misy safidy roa na telo. Aza manome naoty.',
        ),
      );
      return;
    }

    if (choice.id == 'game_hint' &&
        _activeLesson.isActive &&
        _activeLesson.step == 3) {
      await _requestHintWithoutEvaluation(
        visibleUserText: choice.label,
        instruction: _tr(
          'Donne un indice très court pour la même manche, puis répète la même question avec ses choix. N’évalue rien et ne change pas le numéro de question.',
          'Omeo soso-kevitra fohy ho an’ity fihodinana ity, avy eo avereno ilay fanontaniana sy ny safidy. Aza manome naoty ary aza ovaina ny laharan’ny fanontaniana.',
        ),
      );
      return;
    }

    if (source.tutorResponse?.flow == 'lesson_topic') {
      if (choice.id == 'topic_other') {
        _setupStage = _LessonSetupStage.awaitingCustomTopic;
        await _appendLocalTurn(
          userText: choice.label,
          response: AiTutorResponse.local(
            response: _tr(
              'Écris le nom exact de la leçon ou du chapitre que tu veux apprendre.',
              'Soraty mazava ny anaran’ny lesona na toko tianao hianarana.',
            ),
            flow: 'custom_lesson_topic',
          ),
        );
        return;
      }
      final data = _topicFromChoice(choice.id, malagasy: _isMalagasy);
      _selectedSubject = data.$1;
      _selectedTopic = data.$2;
      final preset = _presetActivity;
      await _startSelectedLesson(
        activity: preset ?? 'lesson',
        visibleUserText: choice.label,
      );
      return;
    }

    if (source.tutorResponse?.flow == 'lesson_activity') {
      final requested = choice.id.replaceFirst('activity_', '');
      await _startSelectedLesson(
        activity: requested == 'explanation' ? 'lesson' : requested,
        visibleUserText: choice.label,
      );
      return;
    }

    if (source.tutorResponse?.flow == 'game_menu') {
      final gameType = choice.id.replaceFirst('game_', '');
      final lesson = _activeLesson.copyWith(
        step: 3,
        totalSteps: 3,
        stage: _stageForStep(3, malagasy: _isMalagasy),
        activity: gameType,
        awaitingAnswer: false,
        completed: false,
        gameQuestion: 1,
        gameTotal: 2,
        gameCorrect: 0,
      );
      setState(() => _activeLesson = lesson);
      await _generateTurn(
        visibleUserText: choice.label,
        modelText: choice.message,
        activeLessonOverride: lesson,
      );
      return;
    }

    if (source.tutorResponse?.flow == 'exercise_start') {
      final lesson = _activeLesson.copyWith(
        step: 2,
        totalSteps: 3,
        stage: _stageForStep(2, malagasy: _isMalagasy),
        awaitingAnswer: false,
      );
      setState(() => _activeLesson = lesson);
      await _generateTurn(
        visibleUserText: choice.label,
        modelText: _tr(
          'Commence maintenant un exercice guidé avec 2 ou 3 choix. N’écris aucun numéro d’étape.',
          'Atombohy izao ny fanazaran-tena misy tari-dalana sy safidy roa na telo. Soraty amin’ny teny malagasy ihany.',
        ),
        activeLessonOverride: lesson,
      );
      return;
    }

    if (source.tutorResponse?.flow == 'lesson_complete') {
      switch (choice.id) {
        case 'complete_progress':
          await _showProgress();
          return;
        case 'complete_new_lesson':
          await _startLessonSetup();
          return;
        case 'complete_replay':
          await _startSelectedLesson(
            activity: 'game',
            visibleUserText: _tr('Rejouer', 'Hilalao indray'),
          );
          return;
      }
    }

    await _generateTurn(
      visibleUserText: choice.label,
      modelText: choice.message,
    );
  }

  Future<void> _handleInputSend(
    String text,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    Duration? audioDuration,
  ) async {
    if (_isGenerating) return;
    final clean = text.trim();

    if (_setupStage == _LessonSetupStage.awaitingCustomTopic &&
        clean.isNotEmpty &&
        imageBytes == null &&
        audioBytes == null) {
      _selectedTopic = clean;
      _selectedSubject = _subjectFromTopicText(
        clean,
        malagasy: _isMalagasy,
      );
      final preset = _presetActivity;
      await _startSelectedLesson(
        activity: preset ?? 'lesson',
        visibleUserText: clean,
      );
      return;
    }

    if (imageBytes == null &&
        audioBytes == null &&
        _activeLesson.isActive &&
        _activeLesson.step <= 1 &&
        _isUnderstandingSignal(clean)) {
      await _advanceToExercise(clean.isEmpty ? _tr('Passer à l’exercice', 'Hanomboka fanazaran-tena') : clean);
      return;
    }

    await _generateTurn(
      visibleUserText: clean.isEmpty
          ? audioBytes != null
              ? _tr('Message vocal', 'Hafatra am-peo')
              : _tr('Image envoyée', 'Sary nalefa')
          : clean,
      modelText: clean,
      imageBytes: imageBytes,
      audioBytes: audioBytes,
      audioDuration: audioDuration,
    );
  }

  Future<void> _appendLocalTurn({
    required String userText,
    required AiTutorResponse response,
  }) async {
    final id = await _ensureConversationId();
    for (final message in _messages) {
      message.choicesEnabled = false;
    }
    final user = ChatMessage(
      id: 'local-u-${_messageCounter++}',
      isUser: true,
      text: userText,
      voiceLanguageMode: _languageMode,
    );
    final assistant = ChatMessage(
      id: 'local-a-${_messageCounter++}',
      isUser: false,
      text: response.response,
      tutorResponse: response,
      voiceLanguageMode: _languageMode,
    );
    if (!mounted) return;
    setState(() {
      _messages.add(user);
      _messages.add(assistant);
    });
    try {
      await _db.saveExchange(
        conversationId: id,
        userText: userText,
        userModality: 'text',
        languageMode: _languageMode,
        assistantResponse: response,
      );
      await _refreshConversations();
    } catch (error, stackTrace) {
      debugPrint('Sauvegarde du tour local impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _showSnack(
          'Le message reste affiché, mais sa sauvegarde locale a échoué.',
        );
      }
    }
    _scrollToBottom();
  }

  Future<void> _generateTurn({
    required String visibleUserText,
    required String modelText,
    LessonState? activeLessonOverride,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    Duration? audioDuration,
  }) async {
    if (_isGenerating) return;
    if (!await _ensureModelReady()) return;
    final conversationId = await _ensureConversationId();
    final lessonAtStart = activeLessonOverride ?? _activeLesson;
    final canEvaluate = lessonAtStart.isActive && lessonAtStart.awaitingAnswer;

    for (final message in _messages) {
      message.choicesEnabled = false;
    }

    final user = ChatMessage(
      id: 'u-${_messageCounter++}',
      isUser: true,
      text: visibleUserText,
      imageBytes: imageBytes,
      audioBytes: audioBytes,
      audioPlaceholder: audioBytes != null,
      audioDuration: audioDuration,
      voiceLanguageMode: _languageMode,
    );
    final placeholder = ChatMessage(
      id: 'a-${_messageCounter++}',
      isUser: false,
      text: '',
      tutorResponse: const AiTutorResponse(response: ''),
      status: MessageStatus.streaming,
      voiceLanguageMode: _languageMode,
      choicesEnabled: false,
    );
    final localSerial = ++_generationSerial;
    var lastPartialText = '';
    var lastPartialScrollAt = DateTime.fromMillisecondsSinceEpoch(0);

    void showPartialResponse(String partialText) {
      if (!mounted || localSerial != _generationSerial) return;

      // Un rattrapage ne doit jamais vider la bulle déjà visible.
      if (partialText.trim().isEmpty) {
        setState(() => _generationLabel = 'Finalisation de la réponse…');
        return;
      }
      if (partialText == lastPartialText) return;
      lastPartialText = partialText;

      setState(() {
        placeholder
          ..text = partialText
          ..tutorResponse = AiTutorResponse(response: partialText)
          ..status = MessageStatus.streaming
          ..choicesEnabled = false;
        _generationLabel = 'Mpanabe AI répond…';
      });

      final now = DateTime.now();
      if (now.difference(lastPartialScrollAt) >=
          const Duration(milliseconds: 180)) {
        lastPartialScrollAt = now;
        _scrollToBottom(jump: true);
      }
    }

    final generationTimeout = imageBytes != null
        ? const Duration(seconds: 210)
        : audioBytes != null
            ? const Duration(seconds: 180)
            : const Duration(seconds: 150);

    setState(() {
      _messages.add(user);
      _messages.add(placeholder);
      _isGenerating = true;
      _generationLabel = lessonAtStart.isActive
          ? 'Préparation de la leçon…'
          : imageBytes != null
              ? 'Analyse de l’image…'
              : audioBytes != null
                  ? 'Écoute du message…'
                  : 'Préparation de la réponse…';
    });
    _scrollToBottom();

    try {
      AiTutorResponse response;
      try {
        response = await _gemma
            .sendTutorMessage(
              conversationId: conversationId,
              text: modelText,
              activeLesson: lessonAtStart,
              answerCanBeEvaluated: canEvaluate,
              imageBytes: imageBytes,
              audioBytes: audioBytes,
              languageMode: _languageMode,
              onPartialResponse: showPartialResponse,
            )
            .timeout(generationTimeout);
      } catch (error) {
        if (!_isTokenError(error)) rethrow;
        debugPrint('♻️ Saturation détectée, reconstruction de session puis essai unique');
        await _gemma.resetConversationSession(conversationId: conversationId);
        response = await _gemma
            .sendTutorMessage(
              conversationId: conversationId,
              text: modelText,
              activeLesson: lessonAtStart,
              answerCanBeEvaluated: canEvaluate,
              imageBytes: imageBytes,
              audioBytes: audioBytes,
              languageMode: _languageMode,
              onPartialResponse: showPartialResponse,
            )
            .timeout(generationTimeout);
      }

      if (!mounted || localSerial != _generationSerial) return;
      response = _sanitizeLessonTransition(
        response,
        lessonAtStart,
        canEvaluate: canEvaluate,
      );

      var progressResult = ProgressSaveResult.none;
      if (canEvaluate) {
        try {
          progressResult = await _db.saveProgressIfValid(
            conversationId: conversationId,
            lesson: response.lesson.courseId.isEmpty
                ? lessonAtStart
                : response.lesson,
            progress: response.progress,
          );
        } catch (error, stackTrace) {
          // Une panne SQLite ne doit jamais remplacer la réponse pédagogique
          // déjà générée par un message d'erreur ou faire disparaître le jeu.
          debugPrint('Sauvegarde de progression impossible : $error');
          debugPrintStack(stackTrace: stackTrace);
          if (mounted) {
            _showSnack(
              _tr(
                'La manche continue, mais la progression locale n’a pas été sauvegardée.',
                'Mitohy ny fihodinana, saingy tsy voatahiry ny fandrosoana.',
              ),
            );
          }
        }
      }

      if (progressResult.pointsAdded > 0) {
        final progressLabel = _isMalagasy
            ? response.lessonCompleted
                ? 'vita ny lalao ary voatahiry ny fandrosoana'
                : 'voamarina ny fihodinana ary voatahiry ny fandrosoana'
            : response.lessonCompleted
                ? 'jeu terminé et progression sauvegardée'
                : 'manche validée et progression sauvegardée';
        response = response.copyWith(
          response:
              '${response.response}\n\n🏅 **+${progressResult.pointsAdded} XP** — $progressLabel.',
          progress: response.progress.copyWith(
            xp: progressResult.pointsAdded,
            understanding: progressResult.mastery,
          ),
        );
      }

      placeholder
        ..text = response.response
        ..tutorResponse = response
        ..status = MessageStatus.done
        ..choicesEnabled = response.choices.isNotEmpty;

      if (response.lesson.isActive) {
        _activeLesson = response.lesson;
      } else if (response.lessonCompleted) {
        _activeLesson = const LessonState();
      }

      setState(() {
        _isGenerating = false;
      });

      try {
        await _db.saveExchange(
          conversationId: conversationId,
          userText: visibleUserText,
          userModality: audioBytes != null
              ? 'audio'
              : imageBytes != null
                  ? 'image'
                  : 'text',
          audioDurationMs: audioDuration?.inMilliseconds,
          languageMode: _languageMode,
          assistantResponse: response,
        );
        await _refreshConversations();
      } catch (error, stackTrace) {
        debugPrint('Sauvegarde de discussion impossible : $error');
        debugPrintStack(stackTrace: stackTrace);
        if (mounted) {
          _showSnack(
            'La réponse reste affichée, mais sa sauvegarde locale a échoué.',
          );
        }
      }
      _scrollToBottom();
    } on GenerationCancelledException {
      if (!mounted || localSerial != _generationSerial) return;
      setState(() {
        _isGenerating = false;
        final stopped = _tr('Génération arrêtée.', 'Najanona ny famoronana valiny.');
        placeholder
          ..text = stopped
          ..tutorResponse = AiTutorResponse.local(
            response: stopped,
            choices: [
              TutorChoice(
                id: 'retry_after_stop',
                label: _tr('Réessayer', 'Andramo indray'),
                message: _tr(
                  'Reprends cette étape avec une réponse courte.',
                  'Avereno ity asa ity amin’ny valiny fohy.',
                ),
              ),
            ],
          )
          ..status = MessageStatus.done
          ..choicesEnabled = true;
      });
    } on TimeoutException {
      await _gemma.stopGeneration();
      if (!mounted || localSerial != _generationSerial) return;
      setState(() {
        _isGenerating = false;
        final timedOut = _tr(
          'La réponse a pris trop de temps. La session a été nettoyée.',
          'Ela loatra ny valiny ka naverina tamin’ny laoniny ny fampandehanana.',
        );
        placeholder
          ..text = timedOut
          ..tutorResponse = AiTutorResponse.local(
            response: timedOut,
            choices: [
              TutorChoice(
                id: 'retry_timeout',
                label: _tr('Réessayer', 'Andramo indray'),
                message: _tr(
                  'Reprends cette étape avec une réponse très courte.',
                  'Avereno ity asa ity amin’ny valiny tena fohy.',
                ),
              ),
            ],
          )
          ..status = MessageStatus.done
          ..choicesEnabled = true;
      });
      await _gemma.resetConversationSession(conversationId: conversationId);
    } catch (error) {
      if (!mounted || localSerial != _generationSerial) return;
      setState(() {
        _isGenerating = false;
        placeholder
          ..text = _tr(
            'Une erreur a empêché la réponse : $error',
            'Nisy olana ka tsy afaka namaly. Andramo indray.',
          )
          ..tutorResponse = null
          ..status = MessageStatus.error
          ..choicesEnabled = false;
      });
      _showSnack('Erreur du chatbot : $error');
    } finally {
      if (mounted && localSerial == _generationSerial && _isGenerating) {
        setState(() => _isGenerating = false);
      }
    }
  }

  List<TutorChoice> _completionChoices() {
    return [
      TutorChoice(
        id: 'complete_replay',
        label: _tr('🎮 Rejouer', '🎮 Hilalao indray'),
        message: _tr(
          'Je veux refaire un mini-jeu de 2 questions.',
          'Te hilalao indray lalao fohy misy fanontaniana 2 aho.',
        ),
      ),
      if (!_isGuestMode)
        TutorChoice(
          id: 'complete_progress',
          label: _tr('📈 Voir ma progression', '📈 Hijery ny fandrosoako'),
          message: _tr(
            'Affiche ma progression.',
            'Asehoy ny fandrosoako.',
          ),
        ),
      TutorChoice(
        id: 'complete_new_lesson',
        label: _tr('📚 Nouvelle leçon', '📚 Lesona vaovao'),
        message: _tr(
          'Je veux commencer une nouvelle leçon.',
          'Te hanomboka lesona vaovao aho.',
        ),
      ),
    ];
  }

  AiTutorResponse _sanitizeLessonTransition(
    AiTutorResponse response,
    LessonState previous, {
    required bool canEvaluate,
  }) {
    if (!previous.isActive) return response;
    if (response.wasTruncated) {
      // Pour une leçon ou un exercice, on conserve l'étape afin de ne pas
      // valider une réponse non évaluée.
      if (previous.step != 3 || !canEvaluate) {
        return response.copyWith(
          lesson: previous,
          flow: previous.step == 3 ? 'game_round' : response.flow,
        );
      }

      // Pour un jeu, un second échec de génération ne doit plus bloquer ou
      // faire disparaître la partie. La manche est enregistrée localement
      // comme tentative non notée, puis Flutter poursuit ou termine le jeu.
      final total = previous.gameTotal.clamp(1, 2).toInt();
      final isFinalRound = previous.gameQuestion >= total;
      final recoveredLesson = previous.copyWith(
        gameQuestion: isFinalRound ? total : previous.gameQuestion + 1,
        awaitingAnswer: false,
        completed: isFinalRound,
      );
      final recoveredProgress = ProgressUpdate(
        save: true,
        skillId:
            '${_slug(previous.topic)}_${_slug(previous.activity)}',
        skillLabel: '${_gameLabel(previous.activity, malagasy: _isMalagasy)} — ${previous.topic}',
        evidence: isFinalRound
            ? _tr(
                'Manche finale enregistrée localement après une réponse interrompue.',
                'Voatahiry teo an-toerana ny fihodinana farany taorian’ny fahatapahan’ny valiny.',
              )
            : _tr(
                'Manche ${previous.gameQuestion} enregistrée localement après une réponse interrompue.',
                'Voatahiry teo an-toerana ny fihodinana ${previous.gameQuestion} taorian’ny fahatapahan’ny valiny.',
              ),
        correct: null,
        score: isFinalRound ? previous.gameCorrect : 0,
        maxScore: isFinalRound ? total : 0,
        understanding: 0,
        xp: 0,
        lessonCompleted: isFinalRound,
      );

      if (isFinalRound) {
        return response.copyWith(
          response: _decorateGameComplete(
            text: _tr(
              'La correction détaillée a été écourtée, mais ta dernière manche a bien été enregistrée.',
              'Tapaka ny fanitsiana amin’ny antsipiriany, fa voatahiry tsara ny fihodinana farany.',
            ),
            activity: previous.activity,
            score: previous.gameCorrect,
            total: total,
            malagasy: _isMalagasy,
          ),
          choices: _completionChoices(),
          lesson: recoveredLesson,
          progress: recoveredProgress,
          flow: 'lesson_complete',
          action: 'finish',
          wasTruncated: false,
        );
      }

      return response.copyWith(
        response: _tr(
          'La correction détaillée a été écourtée, mais la manche ${previous.gameQuestion} est enregistrée. Continuons avec la manche ${previous.gameQuestion + 1}.',
          'Tapaka ny fanitsiana amin’ny antsipiriany, fa voatahiry ny fihodinana ${previous.gameQuestion}. Tohizantsika amin’ny fihodinana ${previous.gameQuestion + 1}.',
        ),
        choices: [
          TutorChoice(
            id: 'game_continue_recovery',
            label: _isMalagasy
                ? '▶ Fihodinana ${previous.gameQuestion + 1}'
                : '▶ Manche ${previous.gameQuestion + 1}',
            message: _tr(
              'Génère uniquement la manche ${previous.gameQuestion + 1} sur $total avec une question très courte et 2 ou 3 choix.',
              'Mamoròna ny fihodinana ${previous.gameQuestion + 1} amin’ny $total ihany, misy fanontaniana tena fohy sy safidy roa na telo.',
            ),
          ),
        ],
        lesson: recoveredLesson,
        progress: recoveredProgress,
        flow: 'game_recovery',
        action: 'wait_answer',
        wasTruncated: false,
      );
    }

    var step = previous.step.clamp(1, 3).toInt();
    var gameQuestion = previous.gameQuestion;
    final gameTotal = previous.gameTotal.clamp(1, 2).toInt();
    var gameCorrect = previous.gameCorrect;
    var completed = false;
    var flow = response.flow;
    var choices = response.choices;
    var text = response.response;
    var action = response.action;

    final scoreBasedCorrect = response.progress.maxScore > 0
        ? response.progress.score == response.progress.maxScore
        : null;
    final inferredCorrect = response.progress.correct ??
        scoreBasedCorrect ??
        (canEvaluate && (action == 'next_step' || action == 'finish')
            ? true
            : null);

    if (step == 3) {
      // Le jeu est piloté par Flutter : deux manches, aucun bouton
      // « J’ai compris », et une présentation plus dynamique.
      gameQuestion = gameQuestion <= 0 ? 1 : gameQuestion;

      if (!canEvaluate) {
        choices = _normalizedGameChoices(choices, previous.activity, malagasy: _isMalagasy);
        flow = 'game_round';
        action = 'wait_answer';
        text = _decorateGameRound(
          text: text,
          activity: previous.activity,
          question: gameQuestion,
          malagasy: _isMalagasy,
        );
      } else {
        if (inferredCorrect == true) gameCorrect++;
        if (gameQuestion >= gameTotal) {
          completed = true;
          flow = 'lesson_complete';
          action = 'finish';
          text = _decorateGameComplete(
            text: text,
            activity: previous.activity,
            score: gameCorrect,
            total: gameTotal,
            lastCorrect: inferredCorrect,
            malagasy: _isMalagasy,
          );
          choices = _completionChoices();
        } else {
          gameQuestion++;
          choices = _normalizedGameChoices(choices, previous.activity, malagasy: _isMalagasy);
          flow = 'game_round';
          action = 'wait_answer';
          text = _decorateGameRound(
            text: text,
            activity: previous.activity,
            question: gameQuestion,
            previousCorrect: inferredCorrect,
            malagasy: _isMalagasy,
          );
        }
      }
    } else {
      final shouldAdvance = canEvaluate &&
          (action == 'next_step' ||
              action == 'finish' ||
              (action == 'none' && inferredCorrect == true));

      if (shouldAdvance && step < 3) {
        step++;
        if (step == 2) {
          flow = 'exercise_start';
          choices = [
            TutorChoice(
              id: 'start_exercise',
              label: _tr('Commencer l’exercice', 'Hanomboka fanazaran-tena'),
              message: _tr(
                'Commence maintenant un exercice guidé sur cette notion.',
                'Atombohy izao ny fanazaran-tena misy tari-dalana momba ity hevitra ity.',
              ),
            ),
          ];
          action = 'wait_answer';
        } else if (step == 3) {
          final gameMenu = _buildGameMenuResponse(intro: text);
          text = gameMenu.response;
          choices = gameMenu.choices;
          flow = 'game_menu';
          action = 'wait_answer';
          gameQuestion = 0;
        }
      }
    }

    final awaiting = !completed &&
        flow != 'game_menu' &&
        flow != 'exercise_start' &&
        (action == 'wait_answer' || choices.isNotEmpty);
    final lesson = previous.copyWith(
      step: step,
      totalSteps: 3,
      stage: _stageForStep(step, malagasy: _isMalagasy),
      awaitingAnswer: awaiting,
      completed: completed,
      gameQuestion: gameQuestion,
      gameTotal: gameTotal,
      gameCorrect: gameCorrect,
    );

    var evaluatedProgress = response.progress;
    final isGameAnswer = canEvaluate && previous.step == 3;
    final hasEvaluatedAnswer = canEvaluate && inferredCorrect != null;

    // Pour les jeux, Flutter enregistre chaque manche même lorsque Gemma
    // oublie le champ progress.correct. Cela évite que certains modes
    // (mémoire, chrono ou vrai/faux) terminent sans aucune progression.
    if (isGameAnswer || hasEvaluatedAnswer) {
      final rawEvidence = normalizeTutorMarkdown(response.response);
      final clippedEvidence = rawEvidence.length > 180
          ? '${rawEvidence.substring(0, 179).trimRight()}…'
          : rawEvidence;
      final fallbackEvidence = isGameAnswer
          ? completed
              ? '${_gameLabel(previous.activity, malagasy: _isMalagasy)} ${_isMalagasy ? 'vita' : 'terminé'} : ${_isMalagasy ? 'isa' : 'score'} $gameCorrect/$gameTotal.'
              : _isMalagasy
                  ? 'Voamarina ny fihodinana ${previous.gameQuestion.clamp(1, gameTotal)} amin’ny $gameTotal.'
                  : 'Manche ${previous.gameQuestion.clamp(1, gameTotal)} sur $gameTotal validée.'
          : _isMalagasy
              ? 'Voamarina ny valiny nandritra ny ${_stageForStep(previous.step, malagasy: true).toLowerCase()}.'
              : 'Réponse évaluée pendant ${_stageForStep(previous.step).toLowerCase()}.';
      final modelProgress = evaluatedProgress;
      final knownRoundScore = inferredCorrect == null
          ? 0
          : inferredCorrect
              ? 1
              : 0;

      evaluatedProgress = ProgressUpdate(
        save: true,
        // Pour un jeu, l'identifiant est toujours calculé localement afin
        // que les deux manches alimentent exactement la même compétence.
        skillId: isGameAnswer
            ? '${_slug(previous.topic)}_${_slug(previous.activity)}'
            : modelProgress.skillId.trim().isEmpty
                ? '${_slug(previous.topic)}_step_${previous.step}'
                : modelProgress.skillId,
        skillLabel: isGameAnswer
            ? '${_gameLabel(previous.activity, malagasy: _isMalagasy)} — ${previous.topic}'
            : modelProgress.skillLabel.trim().isEmpty
                ? '${_stageForStep(previous.step, malagasy: _isMalagasy)} — ${previous.topic}'
                : modelProgress.skillLabel,
        evidence: modelProgress.evidence.trim().isEmpty
            ? clippedEvidence.trim().isEmpty
                ? fallbackEvidence
                : clippedEvidence
            : modelProgress.evidence,
        correct: inferredCorrect,
        // À la dernière manche, le score local est la source de vérité.
        // Pour une manche dont Gemma n'a pas indiqué la correction, on garde
        // maxScore=0 mais l'évidence permet quand même d'enregistrer l'essai.
        score: completed ? gameCorrect : knownRoundScore,
        maxScore: completed
            ? gameTotal
            : inferredCorrect == null
                ? 0
                : 1,
        understanding: inferredCorrect == true
            ? modelProgress.understanding.clamp(0, 100).toInt()
            : 0,
        xp: 0,
        lessonCompleted: completed,
      );
    } else {
      evaluatedProgress = const ProgressUpdate();
    }

    return response.copyWith(
      response: text,
      choices: choices,
      lesson: lesson,
      progress: evaluatedProgress,
      flow: flow,
      action: completed ? 'finish' : action,
    );
  }

  Future<void> _stopGeneration() async {
    if (!_isGenerating) return;
    final serial = ++_generationSerial;
    await _gemma.stopGeneration();
    if (!mounted || serial != _generationSerial) return;
    final streaming = _messages.where(
      (message) => message.status == MessageStatus.streaming,
    );
    setState(() {
      _isGenerating = false;
      for (final message in streaming) {
        final stopped = _tr('Génération arrêtée.', 'Najanona ny famoronana valiny.');
        message
          ..text = stopped
          ..tutorResponse = AiTutorResponse.local(
            response: stopped,
            choices: [
              TutorChoice(
                id: 'retry_stop',
                label: _tr('Réessayer', 'Andramo indray'),
                message: _tr(
                  'Reprends la dernière étape avec une réponse courte.',
                  'Avereno ny asa farany amin’ny valiny fohy.',
                ),
              ),
            ],
          )
          ..status = MessageStatus.done
          ..choicesEnabled = true;
      }
    });
  }

  Future<void> _showProgress() async {
    if (_isGuestMode) {
      _showSnack('La progression est désactivée en mode invité.');
      return;
    }
    final overview = await _db.getLearningOverview();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, controller) => Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: ListView(
              controller: controller,
              children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Ta progression',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ProgressMetric(
                      icon: Icons.stars_rounded,
                      label: 'Niveau',
                      value: overview.levelLabel,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ProgressMetric(
                      icon: Icons.bolt_rounded,
                      label: 'XP',
                      value: '${overview.totalXp}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ProgressMetric(
                      icon: Icons.sports_esports_rounded,
                      label: 'Jeux finis',
                      value: '${overview.completedLessons}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ProgressMetric(
                      icon: Icons.sports_score_rounded,
                      label: 'Score global',
                      value: overview.scoreLabel,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ProgressMetric(
                      icon: Icons.trending_up_rounded,
                      label: 'Maîtrise moyenne',
                      value: '${overview.averageMastery} %',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: overview.nextLevelXp <= 0
                    ? 0
                    : (overview.totalXp / overview.nextLevelXp).clamp(0, 1),
                minHeight: 9,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(height: 22),
              const Text(
                'Compétences',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              if (overview.skills.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Text(
                    'Valide une manche de jeu pour commencer à enregistrer ton score et ta progression.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              else
                ...overview.skills.map(
                  (skill) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.lavender,
                      child: Text('${skill.mastery}%'),
                    ),
                    title: Text(
                      skill.skillLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${skill.subject} · ${skill.topic}\n'
                      '${skill.correctAnswers}/${skill.attempts} bonne(s) réponse(s) · ${skill.xp} points',
                    ),
                    trailing: SizedBox(
                      width: 75,
                      child: LinearProgressIndicator(
                        value: skill.mastery / 100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setLanguageMode(AudioLanguageMode mode) async {
    final normalized = mode.normalized;
    if (_languageMode == normalized) return;
    setState(() => _languageMode = normalized);
    await _db.saveLanguageMode(normalized);

    // Une nouvelle session évite que la langue des anciens tours influence
    // les prochaines explications, exercices ou manches de jeu.
    if (_modelReady && !_isGenerating) {
      await _gemma.resetConversationSession(conversationId: _conversationId);
    }
    if (mounted) {
      _showSnack(
        normalized.isMalagasy
            ? 'Ny valin’i Mpanabe AI rehetra dia amin’ny teny malagasy.'
            : 'Toutes les réponses de Mpanabe AI seront en français.',
      );
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: SafeArea(
        child: _initializing
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: _hasConversationContent
                        ? _buildConversation()
                        : _buildHome(),
                  ),
                  if (_hasConversationContent) _buildPersistentMenu(),
                  if (_isGenerating)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 2, 22, 2),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _generationLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ChatInputBar(
                    onSend: _handleInputSend,
                    isGenerating: _isGenerating,
                    onStop: _stopGeneration,
                    onRecordingStarted: _voice.stop,
                    voiceConversationEnabled: false,
                    autoListenRequestId: 0,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 16, 13),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu_rounded, size: 29),
          ),
          const SizedBox(width: 4),
          Image.asset(
            'assets/images/mascot.png',
            width: 42,
            height: 42,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.smart_toy_rounded,
              color: AppTheme.accent,
              size: 35,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mpanabe AI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 21.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Ton compagnon d’apprentissage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!_isGuestMode)
            Tooltip(
              message: 'Voir ma progression',
              child: InkWell(
                onTap: _showProgress,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.softLavender,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD8C9FF)),
                  ),
                  child: const Icon(
                    Icons.trending_up_rounded,
                    color: AppTheme.accent,
                    size: 24,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHome() {
    final greeting = _studentName.isEmpty
        ? 'Bonjour 👋'
        : 'Bonjour $_studentName 👋';

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 390;
        final horizontalPadding = narrow ? 14.0 : 18.0;
        final missionHeight = narrow ? 168.0 : 174.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            8,
            horizontalPadding,
            18,
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  height: missionHeight,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: AppTheme.missionGradient,
                  ),
                  child: LayoutBuilder(
                    builder: (context, cardConstraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            right: narrow ? -8 : 0,
                            bottom: -2,
                            width: cardConstraints.maxWidth *
                                (narrow ? 0.47 : 0.45),
                            child: Image.asset(
                              'assets/images/mission_teacher.png',
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomRight,
                              errorBuilder: (_, __, ___) => const SizedBox(),
                            ),
                          ),
                          Positioned.fill(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                narrow ? 15 : 18,
                                14,
                                cardConstraints.maxWidth *
                                    (narrow ? 0.40 : 0.42),
                                13,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 17,
                                        backgroundColor: AppTheme.accent,
                                        child: Icon(
                                          Icons.gps_fixed_rounded,
                                          color: Colors.white,
                                          size: 19,
                                        ),
                                      ),
                                      SizedBox(width: 9),
                                      Expanded(
                                        child: Text(
                                          'Mission du jour',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: AppTheme.accent,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Aujourd’hui, apprends à additionner les fractions.',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.8,
                                      height: 1.2,
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 38,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: AppTheme.primaryGradient,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: FilledButton(
                                        onPressed: _startLessonSetup,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 15,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Commencer',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                            SizedBox(width: 7),
                                            Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              SizedBox(height: narrow ? 21 : 25),
              Text(
                greeting,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Qu’allons-nous apprendre aujourd’hui ?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Je suis là pour t’aider à comprendre, pratiquer\net progresser à ton rythme.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12.5,
                  height: 1.38,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: narrow ? 18 : 22),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 6,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: narrow ? 8 : 10,
                  mainAxisSpacing: narrow ? 9 : 11,
                  mainAxisExtent: narrow ? 86 : 92,
                ),
                itemBuilder: (context, index) {
                  final actions = <(IconData, String, VoidCallback, Color)>[
                    (
                      Icons.menu_book_rounded,
                      'Expliquer un cours',
                      _startLessonSetup,
                      const Color(0xFF8A55FF),
                    ),
                    (
                      Icons.psychology_alt_rounded,
                      'Aide pour un exercice',
                      () => _startLessonSetup(presetActivity: 'exercise'),
                      const Color(0xFFF0659B),
                    ),
                    (
                      Icons.sports_esports_rounded,
                      'Créer un jeu éducatif',
                      () => _startLessonSetup(presetActivity: 'game'),
                      const Color(0xFF12B76A),
                    ),
                    (
                      Icons.camera_alt_rounded,
                      'Analyser une copie',
                      () => _showSnack(
                        'Appuie sur + puis choisis une image.',
                      ),
                      const Color(0xFF4A8BFF),
                    ),
                    (
                      Icons.translate_rounded,
                      'Traduire en Malagasy',
                      () => _appendLocalTurn(
                        userText: 'Traduire en Malagasy',
                        response: AiTutorResponse.local(
                          response: _tr(
                            'Écris le texte que tu veux traduire en malagasy.',
                            'Soraty ny lahatsoratra tianao hadika amin’ny teny malagasy.',
                          ),
                        ),
                      ),
                      const Color(0xFFFFB800),
                    ),
                    (
                      Icons.quiz_rounded,
                      'Générer un quiz',
                      () => _startLessonSetup(presetActivity: 'quiz'),
                      const Color(0xFF21C6AD),
                    ),
                  ];
                  final action = actions[index];
                  return _HomeAction(
                    icon: action.$1,
                    label: action.$2,
                    onTap: action.$3,
                    iconColor: action.$4,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConversation() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return MessageBubble(
          message: message,
          onChoiceSelected: (choice) => _handleChoice(message, choice),
          onSpeak: message.isUser
              ? null
              : () => _voice.speak(
                    message.tutorResponse?.response ?? message.text,
                    languageMode: message.voiceLanguageMode,
                  ),
        );
      },
    );
  }

  Widget _buildPersistentMenu() {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.menu_book_rounded, _tr('Leçon', 'Lesona'), _startLessonSetup),
      (
        Icons.psychology_alt_rounded,
        _tr('Exercice', 'Fanazaran-tena'),
        () => _startLessonSetup(presetActivity: 'exercise'),
      ),
      (
        Icons.quiz_rounded,
        _tr('Quiz', 'Quiz'),
        () => _startLessonSetup(presetActivity: 'quiz'),
      ),
      (
        Icons.sports_esports_rounded,
        _tr('Jeu', 'Lalao'),
        () => _startLessonSetup(presetActivity: 'game'),
      ),
      (
        Icons.cloud_outlined,
        _tr('En ligne', 'An-tserasera'),
        () {
          _openOnlineTools();
        },
      ),
      if (!_isGuestMode)
        (Icons.trending_up_rounded, _tr('Progression', 'Fandrosoana'), _showProgress),
      (
        Icons.history_rounded,
        _tr('Discussions', 'Resaka'),
        () => _scaffoldKey.currentState?.openDrawer(),
      ),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final action = actions[index];
          return ActionChip(
            avatar: Icon(action.$1, size: 17, color: AppTheme.accent),
            label: Text(action.$2),
            onPressed: _isGenerating ? null : action.$3,
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFDCCFFF)),
            labelStyle: const TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openOnlineTools({int initialTab = 0}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineToolsScreen(
          languageMode: _languageMode,
          initialSubject: _activeLesson.subject.isNotEmpty
              ? _activeLesson.subject
              : _selectedSubject,
          initialTopic: _activeLesson.topic.isNotEmpty
              ? _activeLesson.topic
              : _selectedTopic,
          initialTab: initialTab,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    if (_isGenerating) {
      await _stopGeneration();
    }
    await LocalAuthService.instance.logout();
    _db.clearRuntimeData();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  Widget _buildDrawer() {
    final filtered = _conversations.where((conversation) {
      final query = _drawerQuery.trim().toLowerCase();
      if (query.isEmpty) return true;
      return conversation.title.toLowerCase().contains(query) ||
          conversation.topic.toLowerCase().contains(query) ||
          conversation.preview.toLowerCase().contains(query);
    }).toList(growable: false);
    final drawerItems = <Object>[];
    String? lastGroup;
    for (final conversation in filtered) {
      final group = _conversationGroupLabel(conversation.updatedAt);
      if (group != lastGroup) {
        drawerItems.add(group);
        lastGroup = group;
      }
      drawerItems.add(conversation);
    }

    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.88,
      backgroundColor: const Color(0xFFFAF9FE),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 12, 15, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Discussions',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: _newConversation,
                    tooltip: 'Nouvelle discussion',
                    icon: const Icon(Icons.edit_square),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: TextField(
                onChanged: (value) => setState(() => _drawerQuery = value),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Rechercher',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'Aucune discussion',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      itemCount: drawerItems.length,
                      itemBuilder: (context, index) {
                        final item = drawerItems[index];
                        if (item is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
                            child: Text(
                              item,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          );
                        }
                        final conversation = item as StoredConversation;
                        final active = conversation.id == _conversationId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Material(
                            color: active
                                ? AppTheme.lavender
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(13),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              onTap: () =>
                                  _switchConversation(conversation.id),
                              leading: const Icon(
                                Icons.chat_bubble_outline_rounded,
                              ),
                            title: Text(
                              conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: active
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            subtitle: conversation.preview.trim().isEmpty
                                ? null
                                : Text(
                                    conversation.preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'rename') {
                                  _renameConversation(conversation);
                                } else if (value == 'delete') {
                                  _deleteConversation(conversation);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Renommer'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Supprimer'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        );
                      },
                    ),
            ),
            if (_isGuestMode)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      size: 17,
                      color: AppTheme.textSecondary,
                    ),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Mode invité · discussions temporaires · sans progression',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.cloud_outlined,
                color: AppTheme.accent,
              ),
              title: Text(
                _tr('Outils en ligne', 'Fitaovana an-tserasera'),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                _tr(
                  'Analyse de copies et tutoriel vidéo',
                  'Fanadihadiana valin’asa sy horonan-tsary',
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _openOnlineTools();
              },
            ),
            if (!_isGuestMode)
              ListTile(
                leading: const Icon(
                  Icons.trending_up_rounded,
                  color: AppTheme.accent,
                ),
                title: const Text(
                  'Ma progression',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _showProgress();
                },
              ),
            if (!_isGuestMode)
              ListTile(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: AppTheme.error,
                ),
                title: const Text(
                  'Se déconnecter',
                  style: TextStyle(
                    color: AppTheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: _logout,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: DropdownButtonFormField<AudioLanguageMode>(
                value: _languageMode,
                decoration: const InputDecoration(
                  labelText: 'Langue des réponses',
                  border: OutlineInputBorder(),
                ),
                items: selectableAudioLanguageModes
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) _setLanguageMode(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  const _HomeAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF0ECF8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D0B1038),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 33,
                height: 33,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor, size: 21),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontSize: 10.6,
                    height: 1.16,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProgressMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.softLavender,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.accent),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

String _conversationGroupLabel(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final itemDay = DateTime(date.year, date.month, date.day);
  final difference = today.difference(itemDay).inDays;
  if (difference <= 0) return 'Aujourd’hui';
  if (difference == 1) return 'Hier';
  if (difference <= 7) return '7 derniers jours';
  return 'Plus ancien';
}

(String, String) _topicFromChoice(
  String id, {
  bool malagasy = false,
}) {
  if (malagasy) {
    switch (id) {
      case 'topic_fractions':
        return ('Kajy', 'Ampahany');
      case 'topic_multiplication':
        return ('Kajy', 'Fampitomboana');
      case 'topic_conjugaison':
        return ('Teny frantsay', 'Fampiasana matoanteny');
      case 'topic_sciences':
        return ('Siansa', 'Siansa voajanahary');
      default:
        return ('Hafa', 'Lesona nofidina');
    }
  }
  switch (id) {
    case 'topic_fractions':
      return ('Mathématiques', 'Fractions');
    case 'topic_multiplication':
      return ('Mathématiques', 'Multiplication');
    case 'topic_conjugaison':
      return ('Français', 'Conjugaison');
    case 'topic_sciences':
      return ('Sciences', 'Sciences naturelles');
    default:
      return ('Autre', 'Leçon personnalisée');
  }
}

String _activityLabel(String activity, {bool malagasy = false}) {
  if (malagasy) {
    switch (activity) {
      case 'exercise':
        return 'Hanao fanazaran-tena';
      case 'quiz':
        return 'Hanao lalao fanontaniana';
      case 'game':
        return 'Hamorona lalao fanabeazana';
      default:
        return 'Hianatra lesona';
    }
  }
  switch (activity) {
    case 'exercise':
      return 'Faire un exercice';
    case 'quiz':
      return 'Faire un quiz';
    case 'game':
      return 'Créer un jeu éducatif';
    default:
      return 'Apprendre une leçon';
  }
}

String _stageForStep(int step, {bool malagasy = false}) {
  if (malagasy) {
    switch (step) {
      case 1:
        return 'Fanazavana';
      case 2:
        return 'Fanazaran-tena';
      default:
        return 'Lalao sy fanontaniana';
    }
  }
  switch (step) {
    case 1:
      return 'Explication';
    case 2:
      return 'Exercice';
    default:
      return 'Jeu et quiz';
  }
}

String _slug(String value) {
  final result = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return result.isEmpty ? 'lesson' : result;
}

String _subjectFromTopicText(String value, {bool malagasy = false}) {
  final text = value.toLowerCase();
  if (RegExp(
    r'fraction|ampahany|calcul|kajy|nombre|isa|équation|equation|géométr|geometr|multipli|fampitomboana|division|fizarana',
  ).hasMatch(text)) {
    return malagasy ? 'Kajy' : 'Mathématiques';
  }
  if (RegExp(
    r'français|francais|teny frantsay|grammaire|fitsipi-pitenenana|conjug|matoanteny|orthographe|tsipelina|rédaction|redaction',
  ).hasMatch(text)) {
    return malagasy ? 'Teny frantsay' : 'Français';
  }
  if (RegExp(r'anglais|english|teny anglisy|vocabulaire anglais')
      .hasMatch(text)) {
    return malagasy ? 'Teny anglisy' : 'Anglais';
  }
  if (RegExp(r'science|siansa|physique|fizika|chimie|simia|biologie|svt')
      .hasMatch(text)) {
    return malagasy ? 'Siansa' : 'Sciences';
  }
  return malagasy ? 'Hafa' : 'Autre';
}

List<TutorChoice> _normalizedGameChoices(
  List<TutorChoice> choices,
  String activity, {
  bool malagasy = false,
}) {
  final game = activity.toLowerCase();
  if (game == 'true_false' || game == 'truefalse' || game == 'vrai_faux') {
    return [
      TutorChoice(
        id: 'game_true',
        label: malagasy ? '✅ Marina' : '✅ Vrai',
        message: malagasy ? 'Marina' : 'Vrai',
      ),
      TutorChoice(
        id: 'game_false',
        label: malagasy ? '❌ Diso' : '❌ Faux',
        message: malagasy ? 'Diso' : 'Faux',
      ),
    ];
  }

  final filtered = choices.where((choice) {
    final label = choice.label.toLowerCase().replaceAll('’', "'");
    return !label.contains("j'ai compris") &&
        !label.contains('jai compris') &&
        !label.contains('as-tu compris') &&
        !label.contains('avez-vous compris') &&
        !label.contains('azonao ve');
  }).take(3).toList(growable: false);

  if (filtered.isNotEmpty) return filtered;
  return [
    TutorChoice(
      id: 'game_hint',
      label: malagasy ? '💡 Soso-kevitra' : '💡 Indice',
      message: malagasy
          ? 'Omeo soso-kevitra fohy ary avereno ilay fanontaniana.'
          : 'Donne un indice court et répète la même question.',
    ),
    TutorChoice(
      id: 'game_skip',
      label: malagasy ? '⏭️ Mandalo' : '⏭️ Passer',
      message: malagasy
          ? 'Handalo ity fanontaniana ity aho.'
          : 'Je passe cette question.',
    ),
  ];
}

String _decorateGameRound({
  required String text,
  required String activity,
  required int question,
  bool? previousCorrect,
  bool malagasy = false,
}) {
  final parts = <String>[
    '## ${_gameEmoji(activity)} ${_gameLabel(activity, malagasy: malagasy)}',
    malagasy ? '**Fihodinana $question amin’ny 2**' : '**Manche $question sur 2**',
  ];
  if (previousCorrect == true) {
    parts.add(malagasy
        ? '✅ **Tsara!** Marina ny valinao.'
        : '✅ **Bien joué !** Bonne réponse.');
  } else if (previousCorrect == false) {
    parts.add(malagasy
        ? '💡 **Saika marina!** Tohizo fa mbola afaka manarina ianao.'
        : '💡 **Presque !** On continue, tu peux te rattraper.');
  }
  final body = normalizeTutorMarkdown(text);
  if (body.isNotEmpty) parts.add(body);
  return parts.join('\n\n');
}

String _decorateGameComplete({
  required String text,
  required String activity,
  required int score,
  required int total,
  bool? lastCorrect,
  bool malagasy = false,
}) {
  final parts = <String>[
    malagasy
        ? '## 🏁 Vita ny ${_gameLabel(activity, malagasy: true)}'
        : '## 🏁 ${_gameLabel(activity)} terminé',
    if (lastCorrect == true)
      malagasy
          ? '✅ **Marina ny valiny farany!**'
          : '✅ **Bonne dernière réponse !**'
    else if (lastCorrect == false)
      malagasy
          ? '💡 **Diso ny valiny farany, fa vita ny lalao.**'
          : '💡 **Dernière réponse manquée, mais la partie est terminée.**',
    malagasy ? '**Isa: $score/$total**' : '**Score : $score/$total**',
  ];
  final body = normalizeTutorMarkdown(text);
  if (body.isNotEmpty) parts.add(body);
  parts.add(
    malagasy
        ? score == total
            ? '🌟 Tena tsara! Voafehinao tsara ity lohahevitra ity.'
            : score > 0
                ? '👏 Tsara! Afaka manatsara ny isa ianao raha milalao indray.'
                : '💪 Fanombohana ihany izao. Milalaova indray mba handroso.'
        : score == total
            ? '🌟 Excellent ! Tu maîtrises bien cette notion.'
            : score > 0
                ? '👏 Bien joué ! Un nouvel essai peut améliorer ton score.'
                : '💪 Ce n’est qu’un début. Rejoue pour progresser.',
  );
  return parts.join('\n\n');
}

String _gameLabel(String activity, {bool malagasy = false}) {
  if (malagasy) {
    switch (activity.toLowerCase()) {
      case 'memory':
        return 'Lalao fitadidiana';
      case 'chrono':
        return 'Fanamby ara-potoana';
      case 'true_false':
      case 'truefalse':
      case 'vrai_faux':
        return 'Marina sa diso';
      default:
        return 'Lalao fanontaniana fohy';
    }
  }
  switch (activity.toLowerCase()) {
    case 'memory':
      return 'Mémoire';
    case 'chrono':
      return 'Défi chrono';
    case 'true_false':
    case 'truefalse':
    case 'vrai_faux':
      return 'Vrai ou faux';
    default:
      return 'Quiz rapide';
  }
}

String _gameEmoji(String activity) {
  switch (activity.toLowerCase()) {
    case 'memory':
      return '🧠';
    case 'chrono':
      return '⏱️';
    case 'true_false':
    case 'truefalse':
    case 'vrai_faux':
      return '✅❌';
    default:
      return '🎯';
  }
}

bool _isUnderstandingSignal(String value) {
  final text = value
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'[^a-zà-ÿ0-9 ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text == "j'ai compris" ||
      text == 'jai compris' ||
      text == 'compris' ||
      text == "c'est clair" ||
      text == 'c est clair' ||
      text == 'je comprends' ||
      text == 'oui compris' ||
      text == "oui j'ai compris";
}

bool _isTokenError(Object error) {
  final text = '$error'.toLowerCase();
  return text.contains('token') ||
      text.contains('2048') ||
      text.contains('invalid_argument') ||
      text.contains('input token ids are too long');
}
