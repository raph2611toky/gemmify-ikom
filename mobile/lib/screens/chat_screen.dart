import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/audio_language_mode.dart';
import '../models/chat_message.dart';
import '../services/gemma_service.dart';
import '../services/local_learning_database.dart';
import '../services/voice_interaction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';

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
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isGenerating = false;
  bool _historyLoaded = false;
  bool _voiceConversationEnabled = false;
  AudioLanguageMode _audioLanguageMode = AudioLanguageMode.mixed;
  int _autoListenRequestId = 0;
  int _msgCounter = 0;
  int? _conversationId;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeSameChat());
  }

  Future<void> _initializeSameChat() async {
    try {
      await _voice.initialize();
      final mode = await _learningDb.loadLanguageMode();
      final conversationId =
          await _learningDb.getOrCreateActiveConversation();
      final stored = await _learningDb.loadChatMessages(
        conversationId,
        limit: 100,
      );

      final restoredUi = stored.map(_toUiMessage).toList(growable: false);
      final replay = stored.map(_toReplayItem).toList(growable: false);

      if (!mounted) return;
      setState(() {
        _audioLanguageMode = mode;
        _conversationId = conversationId;
        _messages
          ..clear()
          ..addAll(restoredUi);
        _msgCounter = stored.length + 1;
        _historyLoaded = true;
      });
      _scrollToBottom();

      await _gemma.restoreConversation(replay);
      debugPrint(
        '🧠 Même chat prêt : ${stored.length} messages affichés, '
        '${_gemma.currentTokens} tokens actifs.',
      );
    } catch (error, stackTrace) {
      debugPrint('Impossible de restaurer la discussion : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _historyLoaded = true);
    }
  }

  ChatMessage _toUiMessage(StoredChatMessage stored) {
    return ChatMessage(
      id: 'db-${stored.id}',
      isUser: stored.isUser,
      text: stored.text,
      audioPlaceholder: stored.modality == 'audio',
      audioDuration: stored.audioDurationMs == null
          ? null
          : Duration(milliseconds: stored.audioDurationMs!),
      voiceLanguageMode: stored.languageMode,
      status: MessageStatus.done,
    );
  }

  ConversationReplayItem _toReplayItem(StoredChatMessage stored) {
    if (!stored.isUser) {
      return ConversationReplayItem(isUser: false, text: stored.text);
    }

    switch (stored.modality) {
      case 'audio':
        return const ConversationReplayItem(
          isUser: true,
          text:
              'Dans ce tour précédent, l’utilisateur a envoyé un message '
              'vocal. La réponse suivante de Gemma contient le contexte utile '
              'à conserver pour la suite de la même discussion.',
        );
      case 'image':
        return ConversationReplayItem(
          isUser: true,
          text:
              '${stored.text}\nUne image accompagnait ce message dans la '
              'discussion précédente. Conserve le contexte de la réponse '
              'suivante sans inventer de nouveaux détails visuels.',
        );
      default:
        return ConversationReplayItem(isUser: true, text: stored.text);
    }
  }

  Future<void> _setLanguageMode(AudioLanguageMode mode) async {
    if (_audioLanguageMode == mode) return;
    setState(() => _audioLanguageMode = mode);
    await _learningDb.saveLanguageMode(mode);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<int> _activeConversationId() async {
    final existing = _conversationId;
    if (existing != null) return existing;
    final created = await _learningDb.getOrCreateActiveConversation();
    _conversationId = created;
    return created;
  }

  Future<void> _persistExchange({
    required ChatMessage user,
    required ChatMessage assistant,
    required String modality,
  }) async {
    if (assistant.text.trim().isEmpty) return;
    final conversationId = await _activeConversationId();
    await _learningDb.saveExchange(
      conversationId: conversationId,
      userText: user.text,
      userModality: modality,
      audioDurationMs: user.audioDuration?.inMilliseconds,
      languageMode: user.voiceLanguageMode,
      assistantText: assistant.text.trim(),
    );
    debugPrint('💾 Échange enregistré dans la même discussion SQLite.');
  }

  Future<void> _handleSend(
    String text,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    Duration? audioDuration,
  ) async {
    if (_isGenerating) return;
    await _voice.stop();

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
    Uint8List? imageBytes,
  }) async {
    final userText = text.trim().isEmpty
        ? 'Analyse cette image, corrige et explique.'
        : text.trim();

    final userMsg = ChatMessage(
      id: '${_msgCounter++}',
      isUser: true,
      text: userText,
      imageBytes: imageBytes,
      voiceLanguageMode: _audioLanguageMode,
    );

    final botMsg = ChatMessage(
      id: '${_msgCounter++}',
      isUser: false,
      voiceLanguageMode: _audioLanguageMode,
      status: MessageStatus.streaming,
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(botMsg);
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      await for (final token in _gemma.sendMessageStream(
        text: userMsg.text,
        imageBytes: imageBytes,
      )) {
        if (!mounted) return;
        setState(() => botMsg.text += token);
        _scrollToBottom();
      }

      if (!mounted) return;
      setState(() {
        botMsg.status = MessageStatus.done;
        _isGenerating = false;
      });

      await _persistExchange(
        user: userMsg,
        assistant: botMsg,
        modality: imageBytes == null ? 'text' : 'image',
      );

      if (_voiceConversationEnabled) {
        await _voice.speak(
          botMsg.text,
          languageMode: _audioLanguageMode,
        );
        _scheduleAutoListen();
      }
    } catch (error) {
      _markMessageError(botMsg, error);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _handleAudioMessage({
    required Uint8List audioBytes,
    required Duration audioDuration,
  }) async {
    final languageMode = _audioLanguageMode;

    final userMsg = ChatMessage(
      id: '${_msgCounter++}',
      isUser: true,
      text: 'Message vocal',
      audioBytes: audioBytes,
      audioDuration: audioDuration,
      voiceLanguageMode: languageMode,
    );

    final botMsg = ChatMessage(
      id: '${_msgCounter++}',
      isUser: false,
      voiceLanguageMode: languageMode,
      status: MessageStatus.streaming,
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(botMsg);
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      await for (final token in _gemma.sendAudioMessageStream(
        audioBytes: audioBytes,
        languageMode: languageMode,
      )) {
        if (!mounted) return;
        setState(() => botMsg.text += token);
        _scrollToBottom();
      }

      if (!mounted) return;
      setState(() {
        botMsg.status = MessageStatus.done;
        _isGenerating = false;
      });

      await _persistExchange(
        user: userMsg,
        assistant: botMsg,
        modality: 'audio',
      );

      await _voice.speak(
        botMsg.text,
        languageMode: languageMode,
      );

      if (_voiceConversationEnabled) {
        _scheduleAutoListen();
      }
    } catch (error) {
      _markMessageError(botMsg, error);
      _scheduleAutoListen();
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _markMessageError(ChatMessage message, Object error) {
    debugPrint('Erreur Gemma : $error');
    if (!mounted) return;
    setState(() {
      message.text =
          'Je n’ai pas pu terminer cette réponse. Réessaie avec une question plus courte.';
      message.status = MessageStatus.error;
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
    await _gemma.stopGeneration();
    await _voice.stop();
    if (mounted) setState(() => _isGenerating = false);
  }

  Future<void> _toggleVoiceConversation() async {
    final next = !_voiceConversationEnabled;
    await _voice.stop();

    setState(() {
      _voiceConversationEnabled = next;
      if (next && !_isGenerating) _autoListenRequestId++;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          next
              ? 'Conversation vocale directe activée : Gemma écoute, répond '
                  'à voix haute puis réactive le microphone.'
              : 'Conversation vocale désactivée.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _voice.stop();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.background,
      drawer: _MpanabeDrawer(
        languageMode: _audioLanguageMode,
        voiceConversationEnabled: _voiceConversationEnabled,
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
                  : ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                      children: [
                        _MpanabeHeader(
                          onMenuTap: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                        ),
                        const SizedBox(height: 22),
                        _MissionCard(
                          onStart: () => _handleSend(
                            'Apprends-moi à additionner les fractions, étape par étape.',
                            null,
                            null,
                            null,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _GreetingSection(),
                        const SizedBox(height: 22),
                        _LearningFeatureGrid(
                          onSelected: (prompt) =>
                              _handleSend(prompt, null, null, null),
                        ),
                        const SizedBox(height: 28),
                        const _TodayDivider(),
                        const SizedBox(height: 12),
                        if (_messages.isEmpty)
                          _ConversationPreview(
                            onQuickReply: (text) =>
                                _handleSend(text, null, null, null),
                          )
                        else ...[
                          ..._messages.map(
                            (message) => MessageBubble(message: message),
                          ),
                          const SizedBox(height: 8),
                          _QuickReplies(
                            onSelected: (text) =>
                                _handleSend(text, null, null, null),
                          ),
                        ],
                      ],
                    ),
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
    );
  }
}

class _MpanabeHeader extends StatelessWidget {
  final VoidCallback onMenuTap;

  const _MpanabeHeader({required this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onMenuTap,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.menu_rounded,
                size: 31,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            height: 48,
            child: Image.asset(
              'assets/images/mascot.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mpanabe AI',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Ton compagnon d’apprentissage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.lavender,
                  border: Border.all(color: const Color(0xFFE6DBFF), width: 2),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/profile_avatar.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: 2,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
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

class _MissionCard extends StatelessWidget {
  final VoidCallback onStart;

  const _MissionCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 165,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: AppTheme.missionGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppTheme.softShadow,
          ),
          child: Stack(
            children: [
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: constraints.maxWidth * 0.56,
                child: Image.asset(
                  'assets/images/mission_teacher.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: const [0, 0.54, 0.75],
                      colors: [
                        const Color(0xFFF7F3FF),
                        const Color(0xFFF7F3FF).withOpacity(0.96),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 17, 12, 14),
                child: SizedBox(
                  width: constraints.maxWidth * 0.56,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          _GradientIconCircle(
                            icon: Icons.track_changes_rounded,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Mission du jour',
                            style: TextStyle(
                              color: AppTheme.accentDark,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Aujourd’hui, apprends à\nadditionner les fractions.',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          height: 1.28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: onStart,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x345A22E8),
                                blurRadius: 12,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Commencer',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 19,
                                color: Colors.white,
                              ),
                            ],
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
      },
    );
  }
}

class _GradientIconCircle extends StatelessWidget {
  final IconData icon;

  const _GradientIconCircle({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 21),
    );
  }
}

class _GreetingSection extends StatelessWidget {
  const _GreetingSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Bonjour '),
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
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Qu’allons-nous apprendre aujourd’hui ?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 17.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Je suis là pour t’aider à comprendre, pratiquer\net progresser à ton rythme.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LearningFeatureGrid extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _LearningFeatureGrid({required this.onSelected});

  static const _features = <_LearningFeature>[
    _LearningFeature(
      emoji: '📖',
      label: 'Expliquer\nun cours',
      prompt: 'Explique-moi un cours simplement, avec des exemples.',
      tint: Color(0xFFF1E9FF),
    ),
    _LearningFeature(
      emoji: '🧠',
      label: 'Aide pour un\nexercice',
      prompt: 'Aide-moi à résoudre un exercice étape par étape.',
      tint: Color(0xFFFFEEF4),
    ),
    _LearningFeature(
      emoji: '🎮',
      label: 'Créer un jeu\néducatif',
      prompt: 'Crée un petit jeu éducatif pour réviser une leçon.',
      tint: Color(0xFFE9FFF2),
    ),
    _LearningFeature(
      emoji: '📷',
      label: 'Analyser\nune copie',
      prompt: 'Aide-moi à analyser et corriger une copie.',
      tint: Color(0xFFEBF3FF),
    ),
    _LearningFeature(
      emoji: '文',
      label: 'Traduire en\nMalagasy',
      prompt: 'Traduis ce que je vais écrire en malagasy.',
      tint: Color(0xFFFFF7DF),
    ),
    _LearningFeature(
      emoji: '📝',
      label: 'Générer\nun quiz',
      prompt: 'Génère-moi un quiz court avec les réponses à la fin.',
      tint: Color(0xFFE7FFF9),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _features.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final feature = _features[index];
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onSelected(feature.prompt),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border),
              boxShadow: AppTheme.softShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: feature.tint,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(feature.emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    feature.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 11.5,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LearningFeature {
  final String emoji;
  final String label;
  final String prompt;
  final Color tint;

  const _LearningFeature({
    required this.emoji,
    required this.label,
    required this.prompt,
    required this.tint,
  });
}

class _TodayDivider extends StatelessWidget {
  const _TodayDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: AppTheme.border)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 15),
          child: Text(
            'AUJOURD’HUI',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppTheme.border)),
      ],
    );
  }
}

class _ConversationPreview extends StatelessWidget {
  final ValueChanged<String> onQuickReply;

  const _ConversationPreview({required this.onQuickReply});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MessageBubble(
          message: ChatMessage(
            id: 'preview-user',
            isUser: true,
            text: 'Je ne comprends pas les fractions.',
          ),
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'preview-assistant',
            isUser: false,
            text:
                'Avant de t’expliquer, peux-tu me dire ce que représente **1/2** ?',
          ),
        ),
        const SizedBox(height: 8),
        _QuickReplies(onSelected: onQuickReply),
      ],
    );
  }
}

class _QuickReplies extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _QuickReplies({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const replies = ['C’est la moitié', 'Un nombre décimal', 'Je ne sais pas'];

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: replies.map((reply) {
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onSelected(reply),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDCCEFF)),
              ),
              child: Text(
                reply,
                style: const TextStyle(
                  color: AppTheme.accentDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MpanabeDrawer extends StatelessWidget {
  final AudioLanguageMode languageMode;
  final bool voiceConversationEnabled;
  final ValueChanged<AudioLanguageMode> onLanguageChanged;
  final VoidCallback onVoiceChanged;

  const _MpanabeDrawer({
    required this.languageMode,
    required this.voiceConversationEnabled,
    required this.onLanguageChanged,
    required this.onVoiceChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
          children: [
            Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Image.asset('assets/images/mascot.png'),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mpanabe AI',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Assistant pédagogique offline',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Text(
              'Langue de la conversation vocale',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ...AudioLanguageMode.values.map(
              (mode) => RadioListTile<AudioLanguageMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.accent,
                value: mode,
                groupValue: languageMode,
                title: Text(
                  mode.label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onChanged: (value) {
                  if (value != null) onLanguageChanged(value);
                },
              ),
            ),
            const Divider(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.accent,
              value: voiceConversationEnabled,
              title: const Text(
                'Conversation vocale directe',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: const Text(
                'Mpanabe écoute puis répond à voix haute.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              onChanged: (_) => onVoiceChanged(),
            ),
          ],
        ),
      ),
    );
  }
}
