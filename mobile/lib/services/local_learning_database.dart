import 'dart:convert';

import '../models/ai_tutor_response.dart';
import '../models/audio_language_mode.dart';

/// Message conservé uniquement en mémoire pendant l'exécution de l'application.
/// Aucune discussion n'est écrite sur le stockage du téléphone.
class StoredChatMessage {
  final int id;
  final int conversationId;
  final bool isUser;
  final String text;
  final String? structuredJson;
  final String modality;
  final int? audioDurationMs;
  final AudioLanguageMode languageMode;
  final int createdAt;

  const StoredChatMessage({
    required this.id,
    required this.conversationId,
    required this.isUser,
    required this.text,
    required this.structuredJson,
    required this.modality,
    required this.audioDurationMs,
    required this.languageMode,
    required this.createdAt,
  });
}

class StoredConversation {
  final int id;
  final String title;
  final String subject;
  final String topic;
  final String courseId;
  final String status;
  final String summary;
  final int messageCount;
  final int updatedAt;
  final String preview;

  const StoredConversation({
    required this.id,
    required this.title,
    required this.subject,
    required this.topic,
    required this.courseId,
    required this.status,
    required this.summary,
    required this.messageCount,
    required this.updatedAt,
    required this.preview,
  });
}

class StoredSkillProgress {
  final String subject;
  final String topic;
  final String skillId;
  final String skillLabel;
  final int mastery;
  final int attempts;
  final int correctAnswers;
  final int xp;
  final int updatedAt;

  const StoredSkillProgress({
    required this.subject,
    required this.topic,
    required this.skillId,
    required this.skillLabel,
    required this.mastery,
    required this.attempts,
    required this.correctAnswers,
    required this.xp,
    required this.updatedAt,
  });
}

class LearningOverview {
  final int totalXp;
  final int completedLessons;
  final int averageMastery;
  final List<StoredSkillProgress> skills;

  const LearningOverview({
    required this.totalXp,
    required this.completedLessons,
    required this.averageMastery,
    required this.skills,
  });

  String get levelLabel {
    if (totalXp >= 1200) return 'Exploratrice 6';
    if (totalXp >= 800) return 'Exploratrice 5';
    if (totalXp >= 450) return 'Exploratrice 4';
    if (totalXp >= 250) return 'Exploratrice 3';
    if (totalXp >= 100) return 'Exploratrice 2';
    return 'Exploratrice 1';
  }

  int get nextLevelXp {
    if (totalXp < 100) return 100;
    if (totalXp < 250) return 250;
    if (totalXp < 450) return 450;
    if (totalXp < 800) return 800;
    if (totalXp < 1200) return 1200;
    return totalXp + 500;
  }
}

class ProgressSaveResult {
  final bool saved;
  final bool positiveEvolution;
  final int pointsAdded;
  final int mastery;

  const ProgressSaveResult({
    required this.saved,
    required this.positiveEvolution,
    required this.pointsAdded,
    required this.mastery,
  });

  static const none = ProgressSaveResult(
    saved: false,
    positiveEvolution: false,
    pointsAdded: 0,
    mastery: 0,
  );
}

class CompactConversationContext {
  final String summary;
  final List<Map<String, String>> recentTurns;

  const CompactConversationContext({
    required this.summary,
    required this.recentTurns,
  });
}

class _ConversationRecord {
  _ConversationRecord({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int createdAt;
  String title;
  String subject = '';
  String topic = '';
  String courseId = '';
  String status = 'active';
  String summary = '';
  int updatedAt;
}

/// Stockage volontairement éphémère.
///
/// - Aucune base de discussions n'est ouverte au démarrage.
/// - Les discussions restent disponibles uniquement tant que l'application
///   reste ouverte.
/// - Le mode invité n'enregistre aucune progression.
/// - Le mini-résumé est isolé par identifiant de discussion.
class LocalLearningDatabase {
  LocalLearningDatabase._();

  static final LocalLearningDatabase instance = LocalLearningDatabase._();

  final Map<int, _ConversationRecord> _conversationRecords = {};
  final Map<int, List<StoredChatMessage>> _messagesByConversation = {};
  final Map<String, StoredSkillProgress> _skillProgress = {};
  final List<Map<String, Object?>> _completedLessons = [];

  int _conversationSeed = 0;
  int _messageSeed = 0;
  int? _activeConversationId;
  AudioLanguageMode _languageMode = AudioLanguageMode.mixed;
  Map<String, dynamic>? _localProfile;
  bool _signedIn = false;
  bool _guestMode = false;
  bool _initialized = false;

  bool get isGuestModeSync => _guestMode;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Les discussions restent en mémoire : aucun accès SQLite n'est effectué
    // au démarrage. La base persistante séparée sert uniquement aux comptes.
    clearRuntimeData();
  }

  void clearRuntimeData() {
    _conversationRecords.clear();
    _messagesByConversation.clear();
    _skillProgress.clear();
    _completedLessons.clear();
    _conversationSeed = 0;
    _messageSeed = 0;
    _activeConversationId = null;
    _languageMode = AudioLanguageMode.mixed;
    _localProfile = null;
    _signedIn = false;
    _guestMode = false;
  }

  Future<void> enterGuestMode() async {
    _signedIn = false;
    _guestMode = true;
    _localProfile = null;
    _skillProgress.clear();
    _completedLessons.clear();
  }

  Future<void> enterAccountMode() async {
    _signedIn = true;
    _guestMode = false;
  }

  void restoreAccountSession(Map<String, dynamic> profile) {
    _localProfile = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(profile)) as Map,
    );
    _signedIn = true;
    _guestMode = false;
  }

  Future<bool> isGuestMode() async => _guestMode;

  Future<void> saveLanguageMode(AudioLanguageMode mode) async {
    _languageMode = mode;
  }

  Future<AudioLanguageMode> loadLanguageMode() async => _languageMode;

  Future<int> getOrCreateActiveConversation() async {
    final active = _activeConversationId;
    if (active != null && _conversationRecords.containsKey(active)) {
      return active;
    }
    final conversations = await listConversations();
    if (conversations.isNotEmpty) {
      _activeConversationId = conversations.first.id;
      return conversations.first.id;
    }
    return createConversation();
  }

  Future<void> setActiveConversation(int conversationId) async {
    if (_conversationRecords.containsKey(conversationId)) {
      _activeConversationId = conversationId;
    }
  }

  Future<int> createConversation({String title = 'Nouvelle discussion'}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = ++_conversationSeed;
    _conversationRecords[id] = _ConversationRecord(
      id: id,
      title: title.trim().isEmpty ? 'Nouvelle discussion' : title.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _messagesByConversation[id] = <StoredChatMessage>[];
    _activeConversationId = id;
    return id;
  }

  Future<List<StoredConversation>> listConversations() async {
    final values = _conversationRecords.values.map(_toStoredConversation).toList();
    values.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(values);
  }

  Future<StoredConversation?> getConversation(int conversationId) async {
    final record = _conversationRecords[conversationId];
    return record == null ? null : _toStoredConversation(record);
  }

  StoredConversation _toStoredConversation(_ConversationRecord record) {
    final messages = _messagesByConversation[record.id] ?? const [];
    return StoredConversation(
      id: record.id,
      title: record.title,
      subject: record.subject,
      topic: record.topic,
      courseId: record.courseId,
      status: record.status,
      summary: record.summary,
      messageCount: messages.length,
      updatedAt: record.updatedAt,
      preview: messages.isEmpty ? '' : messages.last.text,
    );
  }

  Future<void> renameConversation(int conversationId, String title) async {
    final record = _conversationRecords[conversationId];
    final clean = title.trim();
    if (record == null || clean.isEmpty) return;
    record
      ..title = _clipInline(clean, 80)
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> deleteConversation(int conversationId) async {
    _conversationRecords.remove(conversationId);
    _messagesByConversation.remove(conversationId);
    if (_activeConversationId == conversationId) {
      _activeConversationId = null;
    }
  }

  Future<List<StoredChatMessage>> loadMessages(
    int conversationId, {
    int limit = 1000,
  }) async {
    final values = _messagesByConversation[conversationId] ?? const [];
    if (values.length <= limit) return List.unmodifiable(values);
    return List.unmodifiable(values.sublist(values.length - limit));
  }

  Future<void> saveExchange({
    required int conversationId,
    required String userText,
    required String userModality,
    required AiTutorResponse assistantResponse,
    int? audioDurationMs,
    AudioLanguageMode languageMode = AudioLanguageMode.mixed,
  }) async {
    final record = _conversationRecords[conversationId];
    if (record == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final compactUser = _clipInline(userText, 900);
    final assistantText = _clipRaw(assistantResponse.response, 2400);
    final list = _messagesByConversation.putIfAbsent(
      conversationId,
      () => <StoredChatMessage>[],
    );

    list.add(
      StoredChatMessage(
        id: ++_messageSeed,
        conversationId: conversationId,
        isUser: true,
        text: compactUser,
        structuredJson: null,
        modality: userModality,
        audioDurationMs: audioDurationMs,
        languageMode: languageMode,
        createdAt: now,
      ),
    );
    list.add(
      StoredChatMessage(
        id: ++_messageSeed,
        conversationId: conversationId,
        isUser: false,
        text: assistantText,
        structuredJson: assistantResponse.toCompactJson(),
        modality: 'text',
        audioDurationMs: null,
        languageMode: languageMode,
        createdAt: now + 1,
      ),
    );

    // Limite de mémoire par discussion, sans toucher aux autres discussions.
    if (list.length > 80) {
      list.removeRange(0, list.length - 80);
    }

    final lesson = assistantResponse.lesson;
    record.updatedAt = now + 1;
    if (record.title == 'Nouvelle discussion' && compactUser.isNotEmpty) {
      record.title = _titleFromMessage(compactUser);
    }
    if (lesson.subject.trim().isNotEmpty) record.subject = lesson.subject.trim();
    if (lesson.topic.trim().isNotEmpty) record.topic = lesson.topic.trim();
    if (lesson.courseId.trim().isNotEmpty) record.courseId = lesson.courseId.trim();
    record.status = lesson.completed ? 'completed' : 'active';
    final localSummary = _buildLocalSummary(
      subject: lesson.subject,
      topic: lesson.topic,
      userText: compactUser,
      assistantText: assistantText,
    );
    record.summary = _mergeSummary(record.summary, localSummary);
  }

  Future<CompactConversationContext> buildCompactContext(
    int conversationId, {
    int recentMessageCount = 3,
  }) async {
    final record = _conversationRecords[conversationId];
    final messages = await loadMessages(
      conversationId,
      limit: recentMessageCount.clamp(1, 4).toInt(),
    );
    return CompactConversationContext(
      summary: _clipRaw(record?.summary ?? '', 220),
      recentTurns: messages
          .map(
            (message) => {
              'role': message.isUser ? 'user' : 'assistant',
              'text': _clipRaw(message.text, 140),
            },
          )
          .toList(growable: false),
    );
  }

  Future<Map<String, dynamic>> buildCompactProgress({
    String? subject,
    String? topic,
    int limit = 3,
  }) async {
    if (_guestMode) return const <String, dynamic>{};
    final values = _skillProgress.values.where((skill) {
      final subjectMatches = subject?.trim().isNotEmpty != true ||
          skill.subject == subject!.trim();
      final topicMatches = topic?.trim().isNotEmpty != true ||
          skill.topic == topic!.trim();
      return subjectMatches && topicMatches;
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return {
      'skills': values
          .take(limit.clamp(0, 4).toInt())
          .map(
            (skill) => {
              'label': skill.skillLabel,
              'mastery': skill.mastery,
              'attempts': skill.attempts,
            },
          )
          .toList(growable: false),
    };
  }

  /// Profil pédagogique minimal envoyé au modèle.
  /// Les coordonnées, l'e-mail, le téléphone et l'établissement ne sont
  /// jamais ajoutés au prompt.
  Future<Map<String, dynamic>> buildTutorProfile() async {
    if (_guestMode) {
      return const <String, dynamic>{'mode': 'guest'};
    }
    final profile = _localProfile;
    if (profile == null) return const <String, dynamic>{};

    final rawSubjects = profile['subjects'];
    final subjects = rawSubjects is List
        ? rawSubjects
            .map((value) => _clipInline('$value', 24))
            .where((value) => value.isNotEmpty)
            .take(4)
            .toList(growable: false)
        : const <String>[];

    return <String, dynamic>{
      if (_clipInline('${profile['level'] ?? ''}', 18).isNotEmpty)
        'level': _clipInline('${profile['level']}', 18),
      if (_clipInline('${profile['account_type'] ?? ''}', 18).isNotEmpty)
        'account_type': _clipInline('${profile['account_type']}', 18),
      if (subjects.isNotEmpty) 'subjects': subjects,
    };
  }

  Future<ProgressSaveResult> saveProgressIfValid({
    required int conversationId,
    required LessonState lesson,
    required ProgressUpdate progress,
  }) async {
    if (_guestMode || !progress.isValid) return ProgressSaveResult.none;
    if (lesson.courseId.trim().isEmpty ||
        lesson.subject.trim().isEmpty ||
        lesson.topic.trim().isEmpty) {
      return ProgressSaveResult.none;
    }

    final label = progress.skillLabel.trim();
    final id = progress.skillId.trim().isEmpty
        ? _slug(label)
        : progress.skillId.trim();
    if (label.isEmpty || id.isEmpty) return ProgressSaveResult.none;

    final key = '${lesson.subject}|${lesson.topic}|$id';
    final old = _skillProgress[key];
    final attempts = (old?.attempts ?? 0) + 1;
    final oldMastery = old?.mastery ?? 0;
    final positiveAnswer = progress.correct ??
        (progress.maxScore > 0 && progress.score == progress.maxScore);
    final correctAnswers =
        (old?.correctAnswers ?? 0) + (positiveAnswer ? 1 : 0);
    final proposed = positiveAnswer
        ? progress.understanding > oldMastery
            ? progress.understanding
            : oldMastery + 10
        : oldMastery;
    final newMastery = proposed.clamp(0, 100).toInt();
    final positiveEvolution = newMastery > oldMastery;
    final gameActivity = <String>{
      'quiz',
      'game',
      'memory',
      'chrono',
      'true_false',
      'truefalse',
      'vrai_faux',
    }.contains(lesson.activity.toLowerCase());

    // Un mini-jeu terminé rapporte exactement un point. Les exercices
    // continuent d'améliorer la maîtrise, mais n'ajoutent pas de point.
    final pointsAdded = progress.lessonCompleted && gameActivity ? 1 : 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    _skillProgress[key] = StoredSkillProgress(
      subject: lesson.subject,
      topic: lesson.topic,
      skillId: id,
      skillLabel: _clipInline(label, 120),
      mastery: newMastery,
      attempts: attempts,
      correctAnswers: correctAnswers,
      xp: (old?.xp ?? 0) + pointsAdded,
      updatedAt: now,
    );

    if (progress.lessonCompleted && progress.maxScore > 0) {
      final alreadySaved = _completedLessons.any(
        (item) => item['course_id'] == lesson.courseId,
      );
      if (!alreadySaved) {
        _completedLessons.add({
          'conversation_id': conversationId,
          'course_id': lesson.courseId,
          'subject': lesson.subject,
          'topic': lesson.topic,
          'score': progress.score,
          'max_score': progress.maxScore,
          'points': pointsAdded,
          'completed_at': now,
        });
      }
    }
    return ProgressSaveResult(
      saved: true,
      positiveEvolution: positiveEvolution,
      pointsAdded: pointsAdded,
      mastery: newMastery,
    );
  }

  Future<LearningOverview> getLearningOverview() async {
    if (_guestMode) {
      return const LearningOverview(
        totalXp: 0,
        completedLessons: 0,
        averageMastery: 0,
        skills: [],
      );
    }
    final skills = _skillProgress.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final totalXp = skills.fold<int>(0, (sum, item) => sum + item.xp);
    final average = skills.isEmpty
        ? 0
        : (skills.fold<int>(0, (sum, item) => sum + item.mastery) /
                skills.length)
            .round();
    return LearningOverview(
      totalXp: totalXp,
      completedLessons: _completedLessons.length,
      averageMastery: average,
      skills: List.unmodifiable(skills.take(20)),
    );
  }

  Future<void> saveLocalProfile(Map<String, dynamic> profile) async {
    _localProfile = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(profile)) as Map,
    );
  }

  Future<Map<String, dynamic>?> loadLocalProfile() async {
    final profile = _localProfile;
    return profile == null ? null : Map<String, dynamic>.from(profile);
  }

  Future<void> setSignedIn(bool value) async {
    if (value) {
      await enterAccountMode();
    } else {
      await enterGuestMode();
    }
  }

  Future<bool> isSignedIn() async => _signedIn;

  Future<void> runMaintenance() async {
    // Aucun stockage persistant et aucune maintenance SQLite.
  }
}

String _clipInline(String value, int maxLength) {
  final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= maxLength) return clean;
  return '${clean.substring(0, maxLength - 1).trimRight()}…';
}

String _clipRaw(String value, int maxLength) {
  final clean = value.trim();
  if (clean.length <= maxLength) return clean;
  return '${clean.substring(0, maxLength - 1).trimRight()}…';
}

String _titleFromMessage(String value) {
  final clean = _clipInline(value, 54);
  return clean.isEmpty ? 'Nouvelle discussion' : clean;
}

String _buildLocalSummary({
  required String subject,
  required String topic,
  required String userText,
  required String assistantText,
}) {
  final parts = <String>[
    if (subject.trim().isNotEmpty) subject.trim(),
    if (topic.trim().isNotEmpty) topic.trim(),
    if (userText.trim().isNotEmpty) 'Demande: ${_clipInline(userText, 70)}',
    if (assistantText.trim().isNotEmpty)
      'Réponse: ${_clipInline(assistantText, 80)}',
  ];
  return _clipRaw(parts.join(' · '), 180);
}

String _mergeSummary(String previous, String addition) {
  final oldText = previous.trim();
  final newText = addition.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (newText.isEmpty) return _clipRaw(oldText, 220);
  if (oldText.toLowerCase().contains(newText.toLowerCase())) {
    return _clipRaw(oldText, 220);
  }
  final merged = oldText.isEmpty ? newText : '$oldText • $newText';
  return _clipRaw(merged, 220);
}

String _slug(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}
