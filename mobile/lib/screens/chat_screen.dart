import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/ai_tutor_response.dart';
import '../models/audio_language_mode.dart';
import '../models/chat_message.dart';
import '../services/gemma_service.dart';
import '../services/local_learning_database.dart';
import '../services/voice_interaction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';

enum _LessonFlowStage {
  idle,
  awaitingCustomSubject,
  choosingActivity,
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _gemma = GemmaService();
  final _voice = VoiceInteractionService.instance;
  final _learningDb = LocalLearningDatabase.instance;
  final _messages = <ChatMessage>[];
  final _conversations = <StoredConversation>[];
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isGenerating = false;
  bool _historyLoaded = false;
  bool _voiceConversationEnabled = false;
  AudioLanguageMode _audioLanguageMode = AudioLanguageMode.mixed;
  int _autoListenRequestId = 0;
  int _msgCounter = 0;
  int? _conversationId;
  int _generationSerial = 0;
  _LessonFlowStage _lessonFlowStage = _LessonFlowStage.idle;
  String? _selectedLessonSubject;

  static const String _lessonFlowCommand = '__mpanabe_start_lesson_flow__';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _voice.initialize();
      await _learningDb.initialize();

      // Une seule fois après cette migration : retire les anciennes discussions
      // non structurées. Les nouvelles conversations et la progression restent.
      await _learningDb.clearLegacyDiscussionsOnce();

      _audioLanguageMode = await _learningDb.loadLanguageMode();
      final id = await _learningDb.getOrCreateActiveConversation();
      await _loadConversation(id, recreateSession: !_gemma.isReady);
    } catch (error, stackTrace) {
      debugPrint('Initialisation du chat impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _historyLoaded = true);
      }
    }
  }

  Future<void> _loadConversation(
    int conversationId, {
    bool recreateSession = true,
  }) async {
    if (mounted) {
      setState(() {
        _historyLoaded = false;
        _isGenerating = false;
      });
    }

    await _learningDb.setActiveConversation(conversationId);
    final conversation = await _learningDb.getConversation(conversationId);
    final stored = await _learningDb.loadChatMessages(
      conversationId,
      limit: 80,
    );

    await _gemma.createSession(forceRecreate: recreateSession);

    final replay = <ConversationReplayItem>[];
    final summary = conversation?.summary.trim() ?? '';
    if (summary.isNotEmpty) {
      replay.add(
        ConversationReplayItem(
          isUser: true,
          text: jsonEncode({
            'type': 'conversation_memory',
            'summary': summary,
          }),
        ),
      );
    }
    replay.addAll(stored.map(_toReplayItem));
    await _gemma.restoreConversation(replay, maxMessages: 7);

    final restored = stored.map(_toUiMessage).toList(growable: false);
    var restoredLessonStage = _LessonFlowStage.idle;
    String? restoredLessonSubject;
    if (restored.isNotEmpty) {
      final last = restored.last;
      final flow = '${last.tutorResponse?.ui['flow'] ?? ''}';
      if (!last.isUser && last.tutorResponse?.choices.isNotEmpty == true) {
        if (flow == 'lesson_subject') {
          last.choicesEnabled = true;
        } else if (flow == 'lesson_activity') {
          last.choicesEnabled = true;
          restoredLessonStage = _LessonFlowStage.choosingActivity;
          restoredLessonSubject = last.tutorResponse?.subject.trim();
        }
      } else if (!last.isUser && flow == 'custom_lesson_subject') {
        restoredLessonStage = _LessonFlowStage.awaitingCustomSubject;
      }
    }
    final conversations = await _learningDb.listConversations();

    if (!mounted) return;
    setState(() {
      _conversationId = conversationId;
      _messages
        ..clear()
        ..addAll(restored);
      _conversations
        ..clear()
        ..addAll(conversations);
      _msgCounter = stored.length + 1;
      _generationSerial++;
      _lessonFlowStage = restoredLessonStage;
      _selectedLessonSubject = restoredLessonSubject;
      _historyLoaded = true;
    });
    _scrollToBottom(jump: true);
  }

  ChatMessage _toUiMessage(StoredChatMessage stored) {
    AiTutorResponse? structured;
    if (!stored.isUser && stored.structuredJson?.trim().isNotEmpty == true) {
      structured = AiTutorResponse.parse(stored.structuredJson!);
    }

    return ChatMessage(
      id: 'db-${stored.id}',
      isUser: stored.isUser,
      text: structured?.response.isNotEmpty == true
          ? structured!.response
          : stored.text,
      tutorResponse: structured,
      audioPlaceholder: stored.modality == 'audio',
      audioDuration: stored.audioDurationMs == null
          ? null
          : Duration(milliseconds: stored.audioDurationMs!),
      voiceLanguageMode: stored.languageMode,
      createdAt: DateTime.fromMillisecondsSinceEpoch(stored.createdAt),
      status: MessageStatus.done,
      // Les anciens choix restent visibles à titre d’historique mais ne sont
      // pas renvoyés accidentellement après une restauration.
      choicesEnabled: false,
    );
  }

  ConversationReplayItem _toReplayItem(StoredChatMessage stored) {
    if (!stored.isUser) {
      return ConversationReplayItem(
        isUser: false,
        text: stored.structuredJson?.trim().isNotEmpty == true
            ? stored.structuredJson!.trim()
            : stored.text,
      );
    }

    switch (stored.modality) {
      case 'audio':
        return const ConversationReplayItem(
          isUser: true,
          text: '{"type":"previous_audio","message":"Message vocal déjà traité"}',
        );
      case 'image':
        return ConversationReplayItem(
          isUser: true,
          text: jsonEncode({
            'type': 'previous_image',
            'message': stored.text,
          }),
        );
      default:
        return ConversationReplayItem(isUser: true, text: stored.text);
    }
  }

  Future<void> _refreshConversations() async {
    final values = await _learningDb.listConversations();
    if (!mounted) return;
    setState(() {
      _conversations
        ..clear()
        ..addAll(values);
    });
  }

  void _closeDrawerIfOpen() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  Future<void> _newConversation() async {
    if (_isGenerating) await _handleStop();
    final id = await _learningDb.createConversation();
    if (!mounted) return;
    _closeDrawerIfOpen();
    await _loadConversation(id, recreateSession: true);
  }

  Future<void> _switchConversation(int id) async {
    if (id == _conversationId) {
      _closeDrawerIfOpen();
      return;
    }
    if (_isGenerating) await _handleStop();
    if (!mounted) return;
    _closeDrawerIfOpen();
    await _loadConversation(id, recreateSession: true);
  }

  Future<void> _renameConversation(StoredConversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renommer la discussion'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
          decoration: const InputDecoration(
            hintText: 'Titre de la discussion',
            border: OutlineInputBorder(),
          ),
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

    final cleanTitle = title?.trim() ?? '';
    if (cleanTitle.isEmpty || cleanTitle == conversation.title) return;

    await _learningDb.renameConversation(conversation.id, cleanTitle);
    await _refreshConversations();
  }

  Future<void> _deleteConversation(StoredConversation conversation) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Supprimer cette discussion ?'),
            content: Text(
              '« ${conversation.title} » sera supprimée. La progression générale déjà acquise reste enregistrée.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
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

    await _learningDb.deleteConversation(conversation.id);

    if (conversation.id != _conversationId) {
      await _refreshConversations();
      return;
    }

    final remaining = await _learningDb.listConversations();
    final nextId = remaining.isEmpty
        ? await _learningDb.createConversation()
        : remaining.first.id;

    if (!mounted) return;
    _closeDrawerIfOpen();
    await _loadConversation(nextId, recreateSession: true);
  }

  Future<void> _setLanguageMode(AudioLanguageMode mode) async {
    if (_audioLanguageMode == mode) return;
    setState(() => _audioLanguageMode = mode);
    await _learningDb.saveLanguageMode(mode);
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

  Future<int> _activeConversationId() async {
    final current = _conversationId;
    if (current != null) return current;
    final id = await _learningDb.getOrCreateActiveConversation();
    _conversationId = id;
    return id;
  }

  Future<void> _persistExchange({
    required ChatMessage user,
    required ChatMessage assistant,
    required String modality,
  }) async {
    final response = assistant.tutorResponse;
    if (response == null) return;
    final conversationId = await _activeConversationId();
    await _learningDb.saveExchange(
      conversationId: conversationId,
      userText: user.text,
      userModality: modality,
      audioDurationMs: user.audioDuration?.inMilliseconds,
      languageMode: user.voiceLanguageMode,
      assistantResponse: response,
    );
    await _refreshConversations();
  }


  Future<void> _appendLocalExchange({
    required String userText,
    required AiTutorResponse response,
  }) async {
    final conversationId = await _activeConversationId();
    final userMessage = ChatMessage(
      id: '${_msgCounter++}',
      isUser: true,
      text: userText,
      voiceLanguageMode: _audioLanguageMode,
    );
    final assistantMessage = ChatMessage(
      id: '${_msgCounter++}',
      isUser: false,
      text: response.response,
      tutorResponse: response,
      voiceLanguageMode: _audioLanguageMode,
      status: MessageStatus.done,
    );

    if (!mounted) return;
    setState(() {
      _messages.addAll([userMessage, assistantMessage]);
    });
    _scrollToBottom();

    await _learningDb.saveExchange(
      conversationId: conversationId,
      userText: userText,
      userModality: 'text',
      audioDurationMs: null,
      languageMode: _audioLanguageMode,
      assistantResponse: response,
    );
    await _refreshConversations();
  }

  Future<List<String>> _availableLessonSubjects() async {
    final overview = await _learningDb.getLearningOverview();
    final learned = <String>[];
    final seen = <String>{};

    for (final skill in overview.skills) {
      final subject = skill.subject.trim();
      if (subject.isEmpty || !seen.add(subject.toLowerCase())) continue;
      learned.add(subject);
      if (learned.length >= 4) break;
    }

    if (learned.isEmpty) {
      learned.addAll(const [
        'Mathématiques',
        'Français',
        'Sciences',
        'Histoire-Géographie',
      ]);
    }
    return learned;
  }

  String _choiceId(String prefix, String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${prefix}_${normalized.isEmpty ? 'item' : normalized}';
  }

  Future<void> _startLessonFlow() async {
    if (_isGenerating) return;

    _lessonFlowStage = _LessonFlowStage.idle;
    _selectedLessonSubject = null;
    final subjects = await _availableLessonSubjects();
    final choices = <Map<String, dynamic>>[
      ...subjects.map(
        (subject) => {
          'id': _choiceId('lesson_subject', subject),
          'label': subject,
          'message': subject,
          'style': 'chip',
        },
      ),
      {
        'id': 'lesson_subject_other',
        'label': 'Autre',
        'message': 'Autre matière',
        'style': 'chip',
      },
    ];

    final response = AiTutorResponse.fromJsonMap({
      'response':
          'Quelle leçon veux-tu apprendre ? Choisis une matière ci-dessous. Si elle n’apparaît pas, sélectionne « Autre » puis écris son nom.',
      'choices': choices,
      'ui': {
        'card': 'none',
        'flow': 'lesson_subject',
      },
      'lesson': {
        'status': 'in_progress',
      },
      'assessment': {
        'skills': <dynamic>[],
      },
      'memory': {
        'title': 'Choisir une leçon',
        'summary': 'L’élève choisit la matière de sa prochaine leçon.',
      },
    });

    await _appendLocalExchange(
      userText: 'Apprendre une leçon',
      response: response,
    );
  }

  Future<void> _askForCustomLessonSubject() async {
    _lessonFlowStage = _LessonFlowStage.awaitingCustomSubject;
    _selectedLessonSubject = null;

    final response = AiTutorResponse.fromJsonMap({
      'response':
          'Écris maintenant la matière ou le titre précis de la leçon que tu veux apprendre. Exemple : « Les volcans », « Le passé composé » ou « Les équations ».',
      'choices': <dynamic>[],
      'ui': {
        'card': 'none',
        'flow': 'custom_lesson_subject',
      },
      'lesson': {
        'status': 'in_progress',
      },
      'assessment': {
        'skills': <dynamic>[],
      },
      'memory': {
        'title': 'Choisir une leçon',
        'summary': 'L’élève doit écrire une matière ou un titre de leçon.',
      },
    });

    await _appendLocalExchange(
      userText: 'Autre',
      response: response,
    );
  }

  Future<void> _showLessonActivityChoices(
    String subject, {
    required String userText,
  }) async {
    final cleanSubject = subject.trim();
    if (cleanSubject.isEmpty) return;

    _lessonFlowStage = _LessonFlowStage.choosingActivity;
    _selectedLessonSubject = cleanSubject;

    final response = AiTutorResponse.fromJsonMap({
      'response':
          'Très bien. Comment veux-tu travailler « $cleanSubject » ? Choisis une étape :',
      'choices': [
        {
          'id': 'lesson_mode_explanation',
          'label': 'Explication',
          'message': 'Commencer par une explication',
          'style': 'button',
        },
        {
          'id': 'lesson_mode_exercise',
          'label': 'Exercice guidé',
          'message': 'Commencer par un exercice guidé',
          'style': 'button',
        },
        {
          'id': 'lesson_mode_quiz',
          'label': 'Quiz',
          'message': 'Commencer un quiz',
          'style': 'button',
        },
        {
          'id': 'lesson_mode_game',
          'label': 'Jeu éducatif',
          'message': 'Commencer un jeu éducatif',
          'style': 'button',
        },
      ],
      'ui': {
        'card': 'none',
        'flow': 'lesson_activity',
      },
      'lesson': {
        'subject': cleanSubject,
        'topic': cleanSubject,
        'status': 'in_progress',
      },
      'assessment': {
        'skills': <dynamic>[],
      },
      'memory': {
        'title': cleanSubject,
        'summary':
            'L’élève a choisi la leçon « $cleanSubject » et doit choisir une activité.',
      },
    });

    await _appendLocalExchange(
      userText: userText,
      response: response,
    );
  }

  String _lessonModePrompt({
    required String subject,
    required String mode,
  }) {
    final modeInstructions = switch (mode) {
      'explanation' =>
        'Explique une seule notion à la fois avec un exemple très simple. Termine par des choix pour continuer vers un exercice, un quiz ou un jeu.',
      'exercise' =>
        'Propose un seul exercice guidé. Attends la réponse de l’élève avant de corriger. Ne donne pas immédiatement la solution.',
      'quiz' =>
        'Commence un quiz de 5 questions, une question à la fois. Propose des choices quand elles sont utiles et calcule la note uniquement à la fin.',
      'game' =>
        'Commence un petit jeu éducatif interactif avec une règle courte, un premier défi et des choices. Évalue seulement les réponses réellement données.',
      _ =>
        'Commence par une explication courte, puis propose un exercice, un quiz et un jeu.',
    };

    return jsonEncode({
      'type': 'start_lesson',
      'subject': subject,
      'topic': subject,
      'mode': mode,
      'instructions': [
        modeInstructions,
        'Réponds uniquement avec le JSON structuré demandé par le système.',
        'La clé response doit être non vide.',
        'Ne déclenche pas save_learning_progress tant que l’élève n’a fourni aucune réponse évaluée.',
      ],
    });
  }

  Future<void> _startSelectedLessonMode(TutorChoice choice) async {
    final subject = _selectedLessonSubject?.trim() ?? '';
    if (subject.isEmpty) {
      await _startLessonFlow();
      return;
    }

    final mode = switch (choice.id) {
      'lesson_mode_exercise' => 'exercise',
      'lesson_mode_quiz' => 'quiz',
      'lesson_mode_game' => 'game',
      _ => 'explanation',
    };

    _lessonFlowStage = _LessonFlowStage.idle;
    await _handleRegularMessage(
      text: _lessonModePrompt(subject: subject, mode: mode),
      displayText: choice.label,
    );
  }

  Future<void> _handleSend(
    String text,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    Duration? audioDuration,
  ) async {
    if (_isGenerating) return;
    await _voice.stop();

    if (imageBytes == null &&
        audioBytes == null &&
        text.trim() == _lessonFlowCommand) {
      await _startLessonFlow();
      return;
    }

    if (imageBytes == null &&
        audioBytes == null &&
        _lessonFlowStage == _LessonFlowStage.awaitingCustomSubject) {
      final subject = text.trim();
      if (subject.isEmpty) return;
      await _showLessonActivityChoices(subject, userText: subject);
      return;
    }

    if (audioBytes != null && audioBytes.isNotEmpty) {
      await _handleAudioMessage(
        audioBytes: audioBytes,
        audioDuration: audioDuration ?? Duration.zero,
      );
      return;
    }

    await _handleRegularMessage(text: text, imageBytes: imageBytes);
  }

  Future<void> _handleRegularMessage({
    required String text,
    String? displayText,
    Uint8List? imageBytes,
  }) async {
    final prompt = text.trim().isEmpty
        ? 'Analyse cette image, corrige puis explique simplement.'
        : text.trim();
    final visibleText = displayText?.trim().isNotEmpty == true
        ? displayText!.trim()
        : prompt;
    final conversationId = await _activeConversationId();
    final generationSerial = ++_generationSerial;

    final userMessage = ChatMessage(
      id: '${_msgCounter++}',
      isUser: true,
      text: visibleText,
      imageBytes: imageBytes,
      voiceLanguageMode: _audioLanguageMode,
    );
    final assistantMessage = ChatMessage(
      id: '${_msgCounter++}',
      isUser: false,
      voiceLanguageMode: _audioLanguageMode,
      status: MessageStatus.streaming,
    );

    if (!mounted) return;
    setState(() {
      _messages.add(userMessage);
      _messages.add(assistantMessage);
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      final response = await _gemma
          .sendTutorMessage(
            conversationId: conversationId,
            text: prompt,
            imageBytes: imageBytes,
            languageMode: _audioLanguageMode,
          )
          .timeout(
            const Duration(seconds: 120),
            onTimeout: () {
              unawaited(_gemma.stopGeneration());
              throw TimeoutException(
                'La génération a dépassé le délai autorisé.',
              );
            },
          );

      if (!mounted || generationSerial != _generationSerial) return;
      setState(() {
        assistantMessage
          ..text = response.response
          ..tutorResponse = response
          ..status = MessageStatus.done;
        _isGenerating = false;
      });
      _scrollToBottom();

      await _persistExchange(
        user: userMessage,
        assistant: assistantMessage,
        modality: imageBytes == null ? 'text' : 'image',
      );

      if (_voiceConversationEnabled && response.response.trim().isNotEmpty) {
        await _voice.speak(
          response.response,
          languageMode: _audioLanguageMode,
        );
        _scheduleAutoListen();
      }
    } catch (error, stackTrace) {
      final cancelled = error is GenerationCancelledException ||
          generationSerial != _generationSerial;
      if (cancelled) {
        _removeStreamingMessage(assistantMessage);
        return;
      }

      debugPrint('Erreur Gemma : $error');
      debugPrintStack(stackTrace: stackTrace);
      _markMessageError(assistantMessage);
    } finally {
      if (mounted && generationSerial == _generationSerial) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _handleAudioMessage({
    required Uint8List audioBytes,
    required Duration audioDuration,
  }) async {
    final conversationId = await _activeConversationId();
    final languageMode = _audioLanguageMode;
    final generationSerial = ++_generationSerial;
    final userMessage = ChatMessage(
      id: '${_msgCounter++}',
      isUser: true,
      text: 'Message vocal',
      audioBytes: audioBytes,
      audioDuration: audioDuration,
      voiceLanguageMode: languageMode,
    );
    final assistantMessage = ChatMessage(
      id: '${_msgCounter++}',
      isUser: false,
      voiceLanguageMode: languageMode,
      status: MessageStatus.streaming,
    );

    if (!mounted) return;
    setState(() {
      _messages.add(userMessage);
      _messages.add(assistantMessage);
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      final response = await _gemma
          .sendAudioTutorMessage(
            conversationId: conversationId,
            audioBytes: audioBytes,
            languageMode: languageMode,
          )
          .timeout(
            const Duration(seconds: 120),
            onTimeout: () {
              unawaited(_gemma.stopGeneration());
              throw TimeoutException(
                'La génération audio a dépassé le délai autorisé.',
              );
            },
          );

      if (!mounted || generationSerial != _generationSerial) return;
      setState(() {
        assistantMessage
          ..text = response.response
          ..tutorResponse = response
          ..status = MessageStatus.done;
        _isGenerating = false;
      });
      _scrollToBottom();

      await _persistExchange(
        user: userMessage,
        assistant: assistantMessage,
        modality: 'audio',
      );

      await _voice.speak(response.response, languageMode: languageMode);
      if (_voiceConversationEnabled) _scheduleAutoListen();
    } catch (error, stackTrace) {
      final cancelled = error is GenerationCancelledException ||
          generationSerial != _generationSerial;
      if (cancelled) {
        _removeStreamingMessage(assistantMessage);
        return;
      }

      debugPrint('Erreur audio Gemma : $error');
      debugPrintStack(stackTrace: stackTrace);
      _markMessageError(assistantMessage);
      _scheduleAutoListen();
    } finally {
      if (mounted && generationSerial == _generationSerial) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _handleChoice(
    ChatMessage sourceMessage,
    TutorChoice choice,
  ) async {
    if (_isGenerating || !sourceMessage.choicesEnabled) return;
    setState(() {
      sourceMessage
        ..choicesEnabled = false
        ..selectedChoiceId = choice.id;
    });

    if (choice.id == 'lesson_subject_other') {
      await _askForCustomLessonSubject();
      return;
    }

    if (choice.id.startsWith('lesson_subject_')) {
      await _showLessonActivityChoices(
        choice.label,
        userText: choice.label,
      );
      return;
    }

    if (choice.id.startsWith('lesson_mode_')) {
      await _startSelectedLessonMode(choice);
      return;
    }

    await _handleRegularMessage(
      text: choice.message,
      displayText: choice.label,
    );
  }

  Future<void> _showLocalProgression() async {
    if (_isGenerating) return;
    final overview = await _learningDb.getLearningOverview();
    final conversationId = await _activeConversationId();
    final userMessage = ChatMessage(
      id: '${_msgCounter++}',
      isUser: true,
      text: 'Voir ma progression',
      voiceLanguageMode: _audioLanguageMode,
    );
    final response = AiTutorResponse.fromJsonMap({
      'response': overview.skills.isEmpty
          ? 'Ta progression commencera à se remplir dès que nous aurons évalué une réponse ou terminé un cours.'
          : 'Voici ta progression enregistrée localement. Elle est mise à jour après chaque preuve de compréhension.',
      'choices': [
        {
          'id': 'resume',
          'label': 'Reprendre la discussion',
          'message': 'Reprenons mon dernier apprentissage.',
          'style': 'button',
        },
        {
          'id': 'exercise',
          'label': 'Faire un exercice adapté',
          'message': 'Propose-moi un exercice adapté à ma progression.',
          'style': 'button',
        },
      ],
      'ui': {'card': 'progression'},
      'lesson': {
        'subject': 'Progression générale',
        'topic': 'Compétences',
        'status': 'in_progress',
      },
      'assessment': {
        'understanding': overview.averageMastery,
        'current_xp': overview.totalXp,
        'next_level_xp': overview.nextLevelXp,
        'level_label': overview.levelLabel,
        'learning_time': '${overview.completedLessons} cours terminés',
        'skills': overview.skills.map((skill) => skill.toJson()).toList(),
      },
      'memory': {
        'title': 'Ma progression',
        'summary': 'Consultation de la progression locale.',
      },
    });
    final assistantMessage = ChatMessage(
      id: '${_msgCounter++}',
      isUser: false,
      text: response.response,
      tutorResponse: response,
      voiceLanguageMode: _audioLanguageMode,
    );

    if (!mounted) return;
    _closeDrawerIfOpen();
    setState(() {
      _messages.addAll([userMessage, assistantMessage]);
    });
    _scrollToBottom();

    await _learningDb.saveExchange(
      conversationId: conversationId,
      userText: userMessage.text,
      userModality: 'text',
      audioDurationMs: null,
      languageMode: _audioLanguageMode,
      assistantResponse: response,
    );
    await _refreshConversations();
  }

  void _removeStreamingMessage(ChatMessage message) {
    if (!mounted) return;
    setState(() {
      if (message.status == MessageStatus.streaming) {
        _messages.remove(message);
      }
      _isGenerating = false;
    });
  }

  void _markMessageError(ChatMessage message) {
    if (!mounted) return;
    setState(() {
      message
        ..text = 'Je n’ai pas pu terminer cette réponse. Réessaie avec une question plus courte.'
        ..tutorResponse = AiTutorResponse.fallback(message.text)
        ..status = MessageStatus.error;
      _isGenerating = false;
    });
  }

  void _scheduleAutoListen() {
    if (!_voiceConversationEnabled || !mounted) return;
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted && _voiceConversationEnabled && !_isGenerating) {
        setState(() => _autoListenRequestId++);
      }
    });
  }

  Future<void> _handleStop() async {
    // Invalide immédiatement le Future encore en attente afin qu’une réponse
    // tardive ne puisse plus modifier l’interface après l’arrêt.
    _generationSerial++;

    if (mounted) {
      setState(() {
        _messages.removeWhere(
          (message) =>
              !message.isUser && message.status == MessageStatus.streaming,
        );
        _isGenerating = false;
      });
    }

    // L’interface s’arrête tout de suite, même si le moteur natif met un peu
    // de temps à confirmer l’annulation.
    await Future.wait<void>([
      _gemma.stopGeneration(),
      _voice.stop(),
    ]);
  }

  Future<void> _toggleVoiceConversation() async {
    final next = !_voiceConversationEnabled;
    await _voice.stop();
    if (!mounted) return;
    setState(() {
      _voiceConversationEnabled = next;
      if (next && !_isGenerating) _autoListenRequestId++;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          next
              ? 'Conversation vocale directe activée.'
              : 'Conversation vocale directe désactivée.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_voice.stop());
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: const TextScaler.linear(1)),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppTheme.background,
        drawer: _DiscussionDrawer(
          conversations: _conversations,
          activeConversationId: _conversationId,
          languageMode: _audioLanguageMode,
          voiceConversationEnabled: _voiceConversationEnabled,
          onNewDiscussion: _newConversation,
          onOpenDiscussion: _switchConversation,
          onRenameDiscussion: _renameConversation,
          onDeleteDiscussion: _deleteConversation,
          onShowProgression: _showLocalProgression,
          onLanguageChanged: _setLanguageMode,
          onVoiceChanged: _toggleVoiceConversation,
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: !_historyLoaded
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 390;
                          final side = compact ? 14.0 : 18.0;
                          return ListView(
                            controller: _scrollController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(side, 6, side, 26),
                            children: [
                              _MpanabeHeader(
                                compact: compact,
                                onMenuTap: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                              ),
                              SizedBox(height: compact ? 14 : 20),
                              if (_messages.isEmpty)
                                _HomeContent(
                                  compact: compact,
                                  conversations: _conversations
                                      .where((item) => item.messageCount > 0)
                                      .take(3)
                                      .toList(growable: false),
                                  onStartPrompt: (prompt) async {
                                    if (prompt == _lessonFlowCommand) {
                                      await _startLessonFlow();
                                      return;
                                    }
                                    await _handleRegularMessage(text: prompt);
                                  },
                                  onOpenDiscussion: _switchConversation,
                                  onShowProgression: _showLocalProgression,
                                )
                              else
                                ..._messages.map(
                                  (message) => MessageBubble(
                                    key: ValueKey(message.id),
                                    message: message,
                                    onChoiceSelected: (choice) =>
                                        _handleChoice(message, choice),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ),
              if (_historyLoaded && _messages.isNotEmpty)
                _PersistentChatMenu(
                  enabled: !_isGenerating,
                  onLesson: _startLessonFlow,
                  onExercise: () => _handleRegularMessage(
                    text:
                        'Aide-moi avec un exercice étape par étape sans donner directement la réponse.',
                  ),
                  onQuiz: () => _handleRegularMessage(
                    text:
                        'Commence un quiz progressif, une question à la fois, puis note mes réponses à la fin.',
                  ),
                  onGame: () => _handleRegularMessage(
                    text:
                        'Commence un petit jeu éducatif interactif et adapte la difficulté à mes réponses.',
                  ),
                  onProgression: _showLocalProgression,
                  onDiscussions: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                ),
              ChatInputBar(
                onSend: _handleSend,
                isGenerating: _isGenerating,
                onStop: _handleStop,
                onRecordingStarted: _voice.stop,
                voiceConversationEnabled: _voiceConversationEnabled,
                autoListenRequestId: _autoListenRequestId,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _PersistentChatMenu extends StatelessWidget {
  final bool enabled;
  final Future<void> Function() onLesson;
  final VoidCallback onExercise;
  final VoidCallback onQuiz;
  final VoidCallback onGame;
  final VoidCallback onProgression;
  final VoidCallback onDiscussions;

  const _PersistentChatMenu({
    required this.enabled,
    required this.onLesson,
    required this.onExercise,
    required this.onQuiz,
    required this.onGame,
    required this.onProgression,
    required this.onDiscussions,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_ChatMenuAction>[
      _ChatMenuAction(
        icon: Icons.menu_book_rounded,
        label: 'Leçon',
        onTap: () => onLesson(),
      ),
      _ChatMenuAction(
        icon: Icons.psychology_alt_rounded,
        label: 'Exercice',
        onTap: onExercise,
      ),
      _ChatMenuAction(
        icon: Icons.quiz_rounded,
        label: 'Quiz',
        onTap: onQuiz,
      ),
      _ChatMenuAction(
        icon: Icons.sports_esports_rounded,
        label: 'Jeu',
        onTap: onGame,
      ),
      _ChatMenuAction(
        icon: Icons.insights_rounded,
        label: 'Progression',
        onTap: onProgression,
      ),
      _ChatMenuAction(
        icon: Icons.forum_rounded,
        label: 'Discussions',
        onTap: onDiscussions,
      ),
    ];

    return Container(
      height: 64,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 7),
          itemBuilder: (context, index) {
            final item = items[index];
            return _ChatMenuButton(
              icon: item.icon,
              label: item.label,
              enabled: enabled || item.label == 'Discussions',
              onTap: item.onTap,
            );
          },
        ),
      ),
    );
  }
}

class _ChatMenuAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ChatMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _ChatMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ChatMenuButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppTheme.lavender : const Color(0xFFF2F0F6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled ? AppTheme.accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? AppTheme.accent : AppTheme.textSecondary,
                  fontSize: 11.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MpanabeHeader extends StatelessWidget {
  final bool compact;
  final VoidCallback onMenuTap;

  const _MpanabeHeader({
    required this.compact,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatarSize = compact ? 44.0 : 50.0;
    final mascotSize = compact ? 38.0 : 43.0;
    return SizedBox(
      height: compact ? 62 : 70,
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onMenuTap,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(
                Icons.menu_rounded,
                size: compact ? 28 : 30,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          SizedBox(width: compact ? 5 : 9),
          SizedBox(
            width: mascotSize,
            height: mascotSize,
            child: Image.asset(
              'assets/images/mascot.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.school_rounded,
                color: AppTheme.accent,
              ),
            ),
          ),
          SizedBox(width: compact ? 7 : 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mpanabe AI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: compact ? 19 : 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.4,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ton compagnon d’apprentissage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: compact ? 10.3 : 11.7,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF0E7FF),
                  border: Border.all(color: const Color(0xFFE2D4FF)),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/profile_avatar.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.person_rounded,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: 1,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final bool compact;
  final List<StoredConversation> conversations;
  final ValueChanged<String> onStartPrompt;
  final ValueChanged<int> onOpenDiscussion;
  final VoidCallback onShowProgression;

  const _HomeContent({
    required this.compact,
    required this.conversations,
    required this.onStartPrompt,
    required this.onOpenDiscussion,
    required this.onShowProgression,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MissionCard(
          compact: compact,
          onStart: () => onStartPrompt(
            'Apprends-moi à additionner les fractions, étape par étape, puis vérifie ma compréhension.',
          ),
        ),
        SizedBox(height: compact ? 20 : 25),
        _GreetingSection(compact: compact),
        SizedBox(height: compact ? 18 : 22),
        _LearningFeatureGrid(
          compact: compact,
          onSelected: onStartPrompt,
        ),
        if (conversations.isNotEmpty) ...[
          const SizedBox(height: 28),
          _SectionHeading(
            title: 'Discussions récentes',
            actionLabel: 'Progression',
            onAction: onShowProgression,
          ),
          const SizedBox(height: 10),
          ...conversations.map(
            (conversation) => _RecentDiscussionTile(
              conversation: conversation,
              onTap: () => onOpenDiscussion(conversation.id),
            ),
          ),
        ] else ...[
          const SizedBox(height: 26),
          OutlinedButton.icon(
            onPressed: onShowProgression,
            icon: const Icon(Icons.insights_rounded),
            label: const Text('Voir ma progression'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppTheme.accent,
              side: const BorderSide(color: Color(0xFFCDBAFF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MissionCard extends StatelessWidget {
  final bool compact;
  final VoidCallback onStart;

  const _MissionCard({required this.compact, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final height = compact ? 168.0 : 185.0;
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppTheme.missionGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.softShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            right: compact ? -10 : 3,
            bottom: 0,
            width: compact ? 158 : 180,
            height: height - 4,
            child: Image.asset(
              'assets/images/mission_teacher.png',
              alignment: Alignment.bottomRight,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 20,
                compact ? 16 : 20,
                compact ? 135 : 160,
                14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: compact ? 34 : 38,
                        height: compact ? 34 : 38,
                        decoration: const BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.track_changes_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Mission du jour',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: compact ? 13.2 : 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 10 : 13),
                  Text(
                    'Aujourd’hui, apprends à additionner les fractions.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: compact ? 14.3 : 16,
                      height: 1.18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: compact ? 39 : 43,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x335A22E8),
                            blurRadius: 12,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: TextButton.icon(
                        onPressed: onStart,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                        label: Text(
                          'Commencer',
                          style: TextStyle(
                            fontSize: compact ? 12.5 : 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GreetingSection extends StatelessWidget {
  final bool compact;

  const _GreetingSection({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text.rich(
          const TextSpan(
            text: 'Bonjour ',
            children: [
              TextSpan(
                text: 'Leite',
                style: TextStyle(color: AppTheme.accent),
              ),
              TextSpan(text: ' 👋'),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: compact ? 19 : 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Qu’allons-nous apprendre aujourd’hui ?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: compact ? 15 : 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Je suis là pour t’aider à comprendre, pratiquer\net progresser à ton rythme.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: compact ? 11.5 : 12.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LearningFeatureGrid extends StatelessWidget {
  final bool compact;
  final ValueChanged<String> onSelected;

  const _LearningFeatureGrid({
    required this.compact,
    required this.onSelected,
  });

  static const _items = <_FeatureData>[
    _FeatureData('📖', 'Apprendre\nune leçon', _ChatScreenState._lessonFlowCommand),
    _FeatureData('🧠', 'Aide pour un\nexercice', 'Aide-moi à résoudre un exercice étape par étape sans donner directement la réponse.'),
    _FeatureData('🎮', 'Créer un jeu\néducatif', 'Crée un petit jeu éducatif interactif et évalue mes réponses.'),
    _FeatureData('📷', 'Analyser\nune copie', 'Je veux analyser une copie ou une photo de devoir.'),
    _FeatureData('🔤', 'Traduire en\nMalagasy', 'Traduis et explique en malagasy avec les mots scolaires français utiles.'),
    _FeatureData('📝', 'Générer\nun quiz', 'Génère un quiz progressif, note mes réponses et enregistre ma progression.'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: compact ? 9 : 12,
        mainAxisSpacing: compact ? 9 : 12,
        childAspectRatio: compact ? .94 : 1.08,
      ),
      itemBuilder: (context, index) {
        final item = _items[index];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
          child: InkWell(
            onTap: () => onSelected(item.prompt),
            borderRadius: BorderRadius.circular(19),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 7 : 9,
                vertical: compact ? 9 : 11,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: AppTheme.border),
                boxShadow: AppTheme.softShadow,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item.emoji, style: TextStyle(fontSize: compact ? 24 : 27)),
                  const SizedBox(height: 7),
                  Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: compact ? 10.3 : 11.5,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FeatureData {
  final String emoji;
  final String label;
  final String prompt;

  const _FeatureData(this.emoji, this.label, this.prompt);
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  const _SectionHeading({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

class _RecentDiscussionTile extends StatelessWidget {
  final StoredConversation conversation;
  final VoidCallback onTap;

  const _RecentDiscussionTile({
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final score = conversation.lastScore;
    final maxScore = conversation.lastMaxScore;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: AppTheme.lavender,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.forum_rounded,
                    size: 20,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        score != null && maxScore != null
                            ? 'Note $score/$maxScore · ${conversation.understanding}% compris'
                            : conversation.topic.isNotEmpty
                                ? conversation.topic
                                : '${conversation.messageCount} messages',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscussionDrawer extends StatefulWidget {
  final List<StoredConversation> conversations;
  final int? activeConversationId;
  final AudioLanguageMode languageMode;
  final bool voiceConversationEnabled;
  final VoidCallback onNewDiscussion;
  final ValueChanged<int> onOpenDiscussion;
  final ValueChanged<StoredConversation> onRenameDiscussion;
  final ValueChanged<StoredConversation> onDeleteDiscussion;
  final VoidCallback onShowProgression;
  final ValueChanged<AudioLanguageMode> onLanguageChanged;
  final VoidCallback onVoiceChanged;

  const _DiscussionDrawer({
    required this.conversations,
    required this.activeConversationId,
    required this.languageMode,
    required this.voiceConversationEnabled,
    required this.onNewDiscussion,
    required this.onOpenDiscussion,
    required this.onRenameDiscussion,
    required this.onDeleteDiscussion,
    required this.onShowProgression,
    required this.onLanguageChanged,
    required this.onVoiceChanged,
  });

  @override
  State<_DiscussionDrawer> createState() => _DiscussionDrawerState();
}

class _DiscussionDrawerState extends State<_DiscussionDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StoredConversation> get _filteredConversations {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.conversations;

    return widget.conversations.where((item) {
      final searchable = [
        item.title,
        item.subject,
        item.topic,
        item.summary,
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList(growable: false);
  }

  Map<String, List<StoredConversation>> _groupConversations(
    List<StoredConversation> conversations,
  ) {
    final groups = <String, List<StoredConversation>>{
      "Aujourd’hui": <StoredConversation>[],
      'Hier': <StoredConversation>[],
      '7 derniers jours': <StoredConversation>[],
      'Plus ancien': <StoredConversation>[],
    };

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final conversation in conversations) {
      final updated = DateTime.fromMillisecondsSinceEpoch(
        conversation.updatedAt,
      );
      final updatedDay = DateTime(updated.year, updated.month, updated.day);
      final ageInDays = today.difference(updatedDay).inDays;

      if (ageInDays <= 0) {
        groups["Aujourd’hui"]!.add(conversation);
      } else if (ageInDays == 1) {
        groups['Hier']!.add(conversation);
      } else if (ageInDays <= 7) {
        groups['7 derniers jours']!.add(conversation);
      } else {
        groups['Plus ancien']!.add(conversation);
      }
    }

    groups.removeWhere((_, values) => values.isEmpty);
    return groups;
  }

  String _conversationMeta(StoredConversation item) {
    if (item.lastScore != null && item.lastMaxScore != null) {
      return 'Note ${item.lastScore}/${item.lastMaxScore}';
    }
    if (item.status == 'completed') return 'Cours terminé';
    if (item.topic.trim().isNotEmpty) return item.topic.trim();
    final count = item.messageCount;
    return '$count message${count > 1 ? 's' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredConversations;
    final grouped = _groupConversations(filtered);

    return Drawer(
      width: MediaQuery.sizeOf(context).width * .88,
      backgroundColor: const Color(0xFFF8F7FC),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/mascot.png',
                    width: 35,
                    height: 35,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Mpanabe AI',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: widget.onNewDiscussion,
                  borderRadius: BorderRadius.circular(14),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_comment_outlined,
                          size: 20,
                          color: AppTheme.textPrimary,
                        ),
                        SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            'Nouvelle discussion',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.add_rounded,
                          size: 20,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'Rechercher une discussion',
                  hintStyle: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? _EmptyDiscussionSearch(hasQuery: _query.trim().isNotEmpty)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: [
                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 13, 12, 5),
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          for (final item in entry.value)
                            _ChatGptConversationTile(
                              conversation: item,
                              selected: item.id == widget.activeConversationId,
                              meta: _conversationMeta(item),
                              onOpen: () => widget.onOpenDiscussion(item.id),
                              onRename: () => widget.onRenameDiscussion(item),
                              onDelete: () => widget.onDeleteDiscussion(item),
                            ),
                        ],
                      ],
                    ),
            ),
            const Divider(height: 1),
            _DrawerBottomAction(
              icon: Icons.insights_rounded,
              label: 'Voir ma progression',
              onTap: widget.onShowProgression,
            ),
            ExpansionTile(
              dense: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 17),
              childrenPadding: EdgeInsets.zero,
              leading: const Icon(Icons.settings_voice_rounded, size: 21),
              title: const Text(
                'Voix et langue',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              children: [
                SwitchListTile(
                  dense: true,
                  value: widget.voiceConversationEnabled,
                  onChanged: (_) => widget.onVoiceChanged(),
                  title: const Text(
                    'Conversation vocale directe',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: DropdownButtonFormField<AudioLanguageMode>(
                    value: widget.languageMode,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Langue vocale',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: AudioLanguageMode.values
                        .map(
                          (mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (mode) {
                      if (mode != null) widget.onLanguageChanged(mode);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatGptConversationTile extends StatelessWidget {
  final StoredConversation conversation;
  final bool selected;
  final String meta;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ChatGptConversationTile({
    required this.conversation,
    required this.selected,
    required this.meta,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? const Color(0xFFEDE7FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
            child: Row(
              children: [
                Icon(
                  conversation.status == 'completed'
                      ? Icons.check_circle_outline_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: conversation.status == 'completed'
                      ? AppTheme.success
                      : AppTheme.textPrimary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12.7,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 9.8,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Options de la discussion',
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    size: 19,
                    color: AppTheme.textSecondary,
                  ),
                  onSelected: (value) {
                    if (value == 'rename') {
                      onRename();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 19),
                          SizedBox(width: 10),
                          Text('Renommer'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: AppTheme.error,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Supprimer',
                            style: TextStyle(color: AppTheme.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDiscussionSearch extends StatelessWidget {
  final bool hasQuery;

  const _EmptyDiscussionSearch({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off_rounded : Icons.chat_bubble_outline,
              size: 34,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              hasQuery
                  ? 'Aucune discussion ne correspond à cette recherche.'
                  : 'Tes discussions apparaîtront ici.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerBottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerBottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 17),
      leading: Icon(icon, size: 21),
      title: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
      onTap: onTap,
    );
  }
}
