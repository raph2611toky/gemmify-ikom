import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/ai_tutor_response.dart';
import '../models/audio_language_mode.dart';

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

  factory StoredChatMessage.fromMap(Map<String, Object?> map) {
    return StoredChatMessage(
      id: map['id'] as int,
      conversationId: map['conversation_id'] as int,
      isUser: (map['role'] as String) == 'user',
      text: (map['text'] as String?) ?? '',
      structuredJson: map['structured_json'] as String?,
      modality: (map['modality'] as String?) ?? 'text',
      audioDurationMs: map['audio_duration_ms'] as int?,
      languageMode: audioLanguageModeFromStorage(
        map['language_mode'] as String?,
      ),
      createdAt: (map['created_at'] as int?) ?? 0,
    );
  }
}

class StoredConversation {
  final int id;
  final String title;
  final String subject;
  final String topic;
  final String courseId;
  final String status;
  final String summary;
  final int? lastScore;
  final int? lastMaxScore;
  final int understanding;
  final int messageCount;
  final int createdAt;
  final int updatedAt;
  final int? completedAt;

  const StoredConversation({
    required this.id,
    required this.title,
    required this.subject,
    required this.topic,
    required this.courseId,
    required this.status,
    required this.summary,
    required this.lastScore,
    required this.lastMaxScore,
    required this.understanding,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
  });

  factory StoredConversation.fromMap(Map<String, Object?> map) {
    return StoredConversation(
      id: map['id'] as int,
      title: (map['title'] as String?) ?? 'Nouvelle discussion',
      subject: (map['subject'] as String?) ?? '',
      topic: (map['topic'] as String?) ?? '',
      courseId: (map['course_id'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'active',
      summary: (map['summary'] as String?) ?? '',
      lastScore: map['last_score'] as int?,
      lastMaxScore: map['last_max_score'] as int?,
      understanding: (map['understanding'] as int?) ?? 0,
      messageCount: (map['message_count'] as int?) ?? 0,
      createdAt: (map['created_at'] as int?) ?? 0,
      updatedAt: (map['updated_at'] as int?) ?? 0,
      completedAt: map['completed_at'] as int?,
    );
  }
}

class StoredSkillProgress {
  final String subject;
  final String topic;
  final String skillId;
  final String skillLabel;
  final int mastery;
  final String status;
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
    required this.status,
    required this.attempts,
    required this.correctAnswers,
    required this.xp,
    required this.updatedAt,
  });

  factory StoredSkillProgress.fromMap(Map<String, Object?> map) {
    return StoredSkillProgress(
      subject: (map['subject'] as String?) ?? '',
      topic: (map['topic'] as String?) ?? '',
      skillId: (map['skill_id'] as String?) ?? '',
      skillLabel: (map['skill_label'] as String?) ?? '',
      mastery: (map['mastery'] as int?) ?? 0,
      status: (map['status'] as String?) ?? 'discover',
      attempts: (map['attempts'] as int?) ?? 0,
      correctAnswers: (map['correct_answers'] as int?) ?? 0,
      xp: (map['xp'] as int?) ?? 0,
      updatedAt: (map['updated_at'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'topic': topic,
        'skill_id': skillId,
        'skill_label': skillLabel,
        'mastery': mastery,
        'status': status,
        'attempts': attempts,
        'correct_answers': correctAnswers,
        'xp': xp,
      };
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
    if (totalXp >= 1200) return 'Experte 6';
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

  Map<String, dynamic> toJson() => {
        'total_xp': totalXp,
        'completed_lessons': completedLessons,
        'average_mastery': averageMastery,
        'level_label': levelLabel,
        'next_level_xp': nextLevelXp,
        'skills': skills.map((item) => item.toJson()).toList(),
      };
}

class LocalLearningDatabase {
  LocalLearningDatabase._();

  static final LocalLearningDatabase instance = LocalLearningDatabase._();

  static const int _databaseVersion = 4;
  Database? _database;

  Future<void> initialize() async {
    await _db;
  }

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;

    final basePath = await getDatabasesPath();
    final db = await openDatabase(
      '$basePath/gemmafy_local.db',
      version: _databaseVersion,
      onCreate: (database, version) async {
        await _createSettingsTable(database);
        await _createConversationTables(database);
        await _createLearningTables(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        await _createSettingsTable(database);
        await _createConversationTables(database);
        await _ensureConversationColumns(database);
        await _ensureMessageColumns(database);
        await _createLearningTables(database);
      },
    );

    _database = db;
    return db;
  }

  static Future<void> _createSettingsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createConversationTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        subject TEXT NOT NULL DEFAULT '',
        topic TEXT NOT NULL DEFAULT '',
        course_id TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        summary TEXT NOT NULL DEFAULT '',
        last_score INTEGER,
        last_max_score INTEGER,
        understanding INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        structured_json TEXT,
        modality TEXT NOT NULL DEFAULT 'text',
        audio_duration_ms INTEGER,
        language_mode TEXT NOT NULL DEFAULT 'mixed',
        created_at INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation
      ON chat_messages(conversation_id, id)
    ''');
  }

  static Future<void> _createLearningTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS learning_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subject TEXT NOT NULL,
        topic TEXT NOT NULL,
        skill_id TEXT NOT NULL,
        skill_label TEXT NOT NULL,
        mastery INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'discover',
        attempts INTEGER NOT NULL DEFAULT 0,
        correct_answers INTEGER NOT NULL DEFAULT 0,
        xp INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        UNIQUE(subject, topic, skill_id)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS progress_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL,
        course_id TEXT NOT NULL DEFAULT '',
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS lesson_attempts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL,
        course_id TEXT NOT NULL,
        subject TEXT NOT NULL,
        topic TEXT NOT NULL,
        score INTEGER,
        max_score INTEGER,
        xp INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'completed',
        details_json TEXT NOT NULL DEFAULT '{}',
        started_at INTEGER NOT NULL,
        completed_at INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_progress_events_conversation
      ON progress_events(conversation_id, created_at)
    ''');
  }

  static Future<void> _ensureConversationColumns(Database database) async {
    await _ensureColumn(database, 'conversations', 'subject', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(database, 'conversations', 'topic', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(database, 'conversations', 'course_id', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(database, 'conversations', 'status', "TEXT NOT NULL DEFAULT 'active'");
    await _ensureColumn(database, 'conversations', 'summary', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(database, 'conversations', 'last_score', 'INTEGER');
    await _ensureColumn(database, 'conversations', 'last_max_score', 'INTEGER');
    await _ensureColumn(database, 'conversations', 'understanding', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(database, 'conversations', 'completed_at', 'INTEGER');
  }

  static Future<void> _ensureMessageColumns(Database database) async {
    await _ensureColumn(database, 'chat_messages', 'structured_json', 'TEXT');
  }

  static Future<void> _ensureColumn(
    Database database,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _saveSetting(String key, String value) async {
    final db = await _db;
    await db.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _loadSetting(String key) async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['setting_value'] as String?;
  }

  Future<void> saveLanguageMode(AudioLanguageMode mode) {
    return _saveSetting('audio_language_mode', mode.storageValue);
  }

  Future<AudioLanguageMode> loadLanguageMode() async {
    return audioLanguageModeFromStorage(
      await _loadSetting('audio_language_mode'),
    );
  }

  Future<int> getOrCreateActiveConversation() async {
    final db = await _db;
    final saved = int.tryParse(
      (await _loadSetting('active_conversation_id')) ?? '',
    );

    if (saved != null) {
      final rows = await db.query(
        'conversations',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [saved],
        limit: 1,
      );
      if (rows.isNotEmpty) return saved;
    }

    return createConversation();
  }

  Future<void> setActiveConversation(int conversationId) async {
    await _saveSetting('active_conversation_id', '$conversationId');
  }

  Future<int> createConversation({String title = 'Nouvelle discussion'}) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert(
      'conversations',
      {
        'title': title,
        'created_at': now,
        'updated_at': now,
      },
    );
    await setActiveConversation(id);
    return id;
  }

  Future<List<StoredConversation>> listConversations() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT c.*,
        (SELECT COUNT(*) FROM chat_messages m
         WHERE m.conversation_id = c.id) AS message_count
      FROM conversations c
      ORDER BY c.updated_at DESC
    ''');
    return rows.map(StoredConversation.fromMap).toList(growable: false);
  }

  Future<StoredConversation?> getConversation(int conversationId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT c.*,
        (SELECT COUNT(*) FROM chat_messages m
         WHERE m.conversation_id = c.id) AS message_count
      FROM conversations c
      WHERE c.id = ?
      LIMIT 1
    ''', [conversationId]);
    if (rows.isEmpty) return null;
    return StoredConversation.fromMap(rows.first);
  }

  Future<void> renameConversation(int conversationId, String title) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;

    final db = await _db;
    await db.update(
      'conversations',
      {'title': cleanTitle},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> deleteConversation(int conversationId) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await transaction.delete(
        'chat_messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );
      await transaction.delete(
        'progress_events',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );
      await transaction.delete(
        'lesson_attempts',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );
      await transaction.delete(
        'conversations',
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
  }

  Future<List<StoredChatMessage>> loadChatMessages(
    int conversationId, {
    int limit = 100,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'chat_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed.map(StoredChatMessage.fromMap).toList(growable: false);
  }

  Future<void> saveExchange({
    required int conversationId,
    required String userText,
    required String userModality,
    required int? audioDurationMs,
    required AudioLanguageMode languageMode,
    required AiTutorResponse assistantResponse,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final structuredJson = assistantResponse.toJsonString();

    await db.transaction((transaction) async {
      await transaction.insert(
        'chat_messages',
        {
          'conversation_id': conversationId,
          'role': 'user',
          'text': userText,
          'structured_json': null,
          'modality': userModality,
          'audio_duration_ms': audioDurationMs,
          'language_mode': languageMode.storageValue,
          'created_at': now,
        },
      );

      await transaction.insert(
        'chat_messages',
        {
          'conversation_id': conversationId,
          'role': 'assistant',
          'text': assistantResponse.response,
          'structured_json': structuredJson,
          'modality': 'text',
          'audio_duration_ms': null,
          'language_mode': languageMode.storageValue,
          'created_at': now + 1,
        },
      );

      final existingRows = await transaction.query(
        'conversations',
        where: 'id = ?',
        whereArgs: [conversationId],
        limit: 1,
      );
      final existing = existingRows.isEmpty ? null : existingRows.first;
      final oldTitle = (existing?['title'] as String?) ?? 'Nouvelle discussion';
      final generatedTitle = assistantResponse.title.trim().isNotEmpty
          ? assistantResponse.title.trim()
          : _titleFromMessage(userText);

      await transaction.update(
        'conversations',
        {
          'title': oldTitle == 'Nouvelle discussion' || oldTitle == 'Discussion principale'
              ? generatedTitle
              : oldTitle,
          if (assistantResponse.subject.isNotEmpty)
            'subject': assistantResponse.subject,
          if (assistantResponse.topic.isNotEmpty)
            'topic': assistantResponse.topic,
          if (assistantResponse.courseId.isNotEmpty)
            'course_id': assistantResponse.courseId,
          if (assistantResponse.lessonStatus.isNotEmpty)
            'status': assistantResponse.lessonStatus,
          if (assistantResponse.summary.isNotEmpty)
            'summary': assistantResponse.summary,
          if (assistantResponse.score != null)
            'last_score': assistantResponse.score,
          if (assistantResponse.maxScore != null)
            'last_max_score': assistantResponse.maxScore,
          if (assistantResponse.understanding > 0)
            'understanding': assistantResponse.understanding,
          if (assistantResponse.lessonCompleted)
            'completed_at': now + 1,
          'updated_at': now + 1,
        },
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
  }

  Future<Map<String, dynamic>> applyProgressFunction({
    required int conversationId,
    required Map<String, dynamic> arguments,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final eventType = _string(arguments['event_type'] ?? arguments['eventType']);
    final courseId = _string(arguments['course_id'] ?? arguments['courseId']);
    final subject = _string(arguments['subject']).isEmpty
        ? 'Général'
        : _string(arguments['subject']);
    final topic = _string(arguments['topic']).isEmpty
        ? 'Apprentissage'
        : _string(arguments['topic']);
    final score = _nullableInt(arguments['score']);
    final maxScore = _nullableInt(arguments['max_score'] ?? arguments['maxScore']);
    final xp = _int(arguments['xp']);
    final understanding = _int(arguments['understanding']).clamp(0, 100).toInt();
    final summary = _string(arguments['summary']);
    final rawSkills = arguments['skills'];
    final skills = rawSkills is List ? rawSkills : const <dynamic>[];

    await db.transaction((transaction) async {
      await transaction.insert(
        'progress_events',
        {
          'conversation_id': conversationId,
          'course_id': courseId,
          'event_type': eventType.isEmpty ? 'progress_update' : eventType,
          'payload_json': jsonEncode(arguments),
          'created_at': now,
        },
      );

      for (var index = 0; index < skills.length; index++) {
        final raw = skills[index];
        if (raw is! Map) continue;
        final skill = Map<String, dynamic>.from(raw);
        final skillId = _string(skill['id'] ?? skill['skill_id'] ?? skill['skillId']);
        final skillLabel = _string(
          skill['label'] ?? skill['name'] ?? skill['skill_label'],
        );
        if (skillId.isEmpty && skillLabel.isEmpty) continue;

        final mastery = _int(skill['mastery']).clamp(0, 100).toInt();
        final status = _normalizeProgressStatus(_string(skill['status']));
        final correct = _bool(skill['correct']);
        final skillXp = _int(skill['xp']);

        final rows = await transaction.query(
          'learning_progress',
          where: 'subject = ? AND topic = ? AND skill_id = ?',
          whereArgs: [subject, topic, skillId.isEmpty ? _slug(skillLabel) : skillId],
          limit: 1,
        );

        final normalizedId = skillId.isEmpty ? _slug(skillLabel) : skillId;
        if (rows.isEmpty) {
          await transaction.insert(
            'learning_progress',
            {
              'subject': subject,
              'topic': topic,
              'skill_id': normalizedId,
              'skill_label': skillLabel.isEmpty ? normalizedId : skillLabel,
              'mastery': mastery,
              'status': status,
              'attempts': eventType == 'answer_evaluated' ? 1 : 0,
              'correct_answers': correct ? 1 : 0,
              'xp': skillXp,
              'updated_at': now,
            },
          );
        } else {
          final old = rows.first;
          await transaction.update(
            'learning_progress',
            {
              'skill_label': skillLabel.isEmpty
                  ? (old['skill_label'] as String? ?? normalizedId)
                  : skillLabel,
              'mastery': mastery,
              'status': status,
              'attempts': (old['attempts'] as int? ?? 0) +
                  (eventType == 'answer_evaluated' ? 1 : 0),
              'correct_answers': (old['correct_answers'] as int? ?? 0) +
                  (correct ? 1 : 0),
              'xp': (old['xp'] as int? ?? 0) + skillXp,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [old['id']],
          );
        }
      }

      final completed = eventType == 'lesson_completed' ||
          _bool(arguments['lesson_completed'] ?? arguments['lessonCompleted']);

      if (completed) {
        await transaction.insert(
          'lesson_attempts',
          {
            'conversation_id': conversationId,
            'course_id': courseId.isEmpty ? 'course_$conversationId' : courseId,
            'subject': subject,
            'topic': topic,
            'score': score,
            'max_score': maxScore,
            'xp': xp,
            'status': 'completed',
            'details_json': jsonEncode(arguments),
            'started_at': now,
            'completed_at': now,
          },
        );
      }

      await transaction.update(
        'conversations',
        {
          if (subject.isNotEmpty) 'subject': subject,
          if (topic.isNotEmpty) 'topic': topic,
          if (courseId.isNotEmpty) 'course_id': courseId,
          if (summary.isNotEmpty) 'summary': summary,
          if (score != null) 'last_score': score,
          if (maxScore != null) 'last_max_score': maxScore,
          if (understanding > 0) 'understanding': understanding,
          if (completed) 'status': 'completed',
          if (completed) 'completed_at': now,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });

    return getProgressContext(subject: subject, topic: topic);
  }

  Future<LearningOverview> getLearningOverview({
    String? subject,
    String? topic,
  }) async {
    final db = await _db;
    final clauses = <String>[];
    final args = <Object?>[];
    if (subject != null && subject.trim().isNotEmpty) {
      clauses.add('subject = ?');
      args.add(subject.trim());
    }
    if (topic != null && topic.trim().isNotEmpty) {
      clauses.add('topic = ?');
      args.add(topic.trim());
    }

    final where = clauses.isEmpty ? null : clauses.join(' AND ');
    final rows = await db.query(
      'learning_progress',
      where: where,
      whereArgs: args,
      orderBy: 'updated_at DESC',
      limit: 12,
    );
    final skills = rows.map(StoredSkillProgress.fromMap).toList(growable: false);

    final xpRows = await db.rawQuery(
      'SELECT COALESCE(SUM(xp), 0) AS total_xp, COUNT(*) AS completed '
      'FROM lesson_attempts WHERE status = ?',
      ['completed'],
    );
    final totalXp = (xpRows.first['total_xp'] as int?) ?? 0;
    final completedLessons = (xpRows.first['completed'] as int?) ?? 0;
    final averageMastery = skills.isEmpty
        ? 0
        : (skills.fold<int>(0, (sum, item) => sum + item.mastery) /
                skills.length)
            .round();

    return LearningOverview(
      totalXp: totalXp,
      completedLessons: completedLessons,
      averageMastery: averageMastery,
      skills: skills,
    );
  }

  Future<Map<String, dynamic>> getProgressContext({
    String? subject,
    String? topic,
  }) async {
    final overview = await getLearningOverview(subject: subject, topic: topic);
    return overview.toJson();
  }

  Future<String> buildCompactProgressJson({
    String? subject,
    String? topic,
  }) async {
    final overview = await getLearningOverview(subject: subject, topic: topic);
    final compactSkills = overview.skills.take(6).map((skill) => {
          'id': skill.skillId,
          'label': skill.skillLabel,
          'mastery': skill.mastery,
          'status': skill.status,
        });
    return jsonEncode({
      'total_xp': overview.totalXp,
      'completed_lessons': overview.completedLessons,
      'average_mastery': overview.averageMastery,
      'skills': compactSkills.toList(),
    });
  }

  Future<bool> clearLegacyDiscussionsOnce() async {
    const markerKey = 'structured_discussions_reset_v1';
    final marker = await _loadSetting(markerKey);
    if (marker == 'done') return false;

    final db = await _db;
    await db.transaction((transaction) async {
      await transaction.delete('chat_messages');
      await transaction.delete('conversations');
      await transaction.delete(
        'app_settings',
        where: 'setting_key = ?',
        whereArgs: ['active_conversation_id'],
      );
      await transaction.insert(
        'app_settings',
        {'setting_key': markerKey, 'setting_value': 'done'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return true;
  }

  Future<void> clearAllDiscussions() async {
    final db = await _db;
    await db.transaction((transaction) async {
      await transaction.delete('chat_messages');
      await transaction.delete('conversations');
      await transaction.delete('progress_events');
      await transaction.delete('lesson_attempts');
      await transaction.delete(
        'app_settings',
        where: 'setting_key = ?',
        whereArgs: ['active_conversation_id'],
      );
    });
  }

  Future<void> clearConversation(int conversationId) async {
    final db = await _db;
    await db.delete(
      'chat_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
    await db.update(
      'conversations',
      {
        'summary': '',
        'status': 'active',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

String _titleFromMessage(String message) {
  final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty || normalized == 'Message vocal') {
    return 'Nouvelle discussion';
  }
  if (normalized.length <= 42) return normalized;
  return '${normalized.substring(0, 42).trim()}…';
}

String _string(dynamic value) => value == null ? '' : '$value'.trim();

int _int(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(_string(value)) ?? 0;
}

int? _nullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(_string(value));
}

bool _bool(dynamic value) {
  if (value is bool) return value;
  return const {'true', '1', 'yes', 'oui'}.contains(_string(value).toLowerCase());
}

String _slug(String value) {
  final lower = value.toLowerCase();
  final normalized = lower
      .replaceAll(RegExp(r'[àáâä]'), 'a')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return normalized.isEmpty ? 'skill' : normalized;
}

String _normalizeProgressStatus(String status) {
  switch (status.toLowerCase()) {
    case 'mastered':
    case 'maitrise':
    case 'maîtrisé':
      return 'mastered';
    case 'in_progress':
    case 'en cours':
    case 'progressing':
      return 'in_progress';
    case 'reinforce':
    case 'à renforcer':
    case 'a renforcer':
      return 'reinforce';
    default:
      return 'discover';
  }
}
