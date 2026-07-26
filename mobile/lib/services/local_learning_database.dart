import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/ai_tutor_response.dart';
import '../models/audio_language_mode.dart';
import 'local_auth_service.dart';

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
  final int totalAttempts;
  final int totalCorrectAnswers;
  final List<StoredSkillProgress> skills;

  const LearningOverview({
    required this.totalXp,
    required this.completedLessons,
    required this.averageMastery,
    required this.totalAttempts,
    required this.totalCorrectAnswers,
    required this.skills,
  });

  String get scoreLabel => '$totalCorrectAnswers/$totalAttempts';

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


class OnlineApiSettings {
  final String baseUrl;

  const OnlineApiSettings({
    this.baseUrl = '',
  });
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

/// Stockage local hors ligne.
///
/// - Les comptes authentifiés conservent leurs discussions et leur progression
///   dans SQLite, séparément pour chaque compte.
/// - Le mode invité reste volontairement temporaire et n'enregistre aucune
///   progression persistante.
/// - La sauvegarde de progression est pilotée localement par Flutter : elle ne
///   dépend pas d'un éventuel appel d'outil produit par Gemma.
class LocalLearningDatabase {
  LocalLearningDatabase._();

  static final LocalLearningDatabase instance = LocalLearningDatabase._();

  Database? _database;

  // Données temporaires réservées au mode invité.
  final Map<int, _ConversationRecord> _guestConversationRecords = {};
  final Map<int, List<StoredChatMessage>> _guestMessagesByConversation = {};
  final Map<String, StoredSkillProgress> _guestSkillProgress = {};
  final List<Map<String, Object?>> _guestCompletedLessons = [];
  int _guestConversationSeed = 0;
  int _guestMessageSeed = 0;

  int? _activeUserId;
  int? _activeConversationId;
  AudioLanguageMode _languageMode = AudioLanguageMode.french;
  Map<String, dynamic>? _localProfile;
  bool _signedIn = false;
  bool _guestMode = false;
  bool _initialized = false;
  OnlineApiSettings _guestOnlineApiSettings = const OnlineApiSettings();

  bool get isGuestModeSync => _guestMode;

  Future<void> initialize() async {
    if (_initialized && _database != null) return;
    final base = await getDatabasesPath();
    _database = await openDatabase(
      '$base/gemmafy_learning.db',
      version: 5,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE learning_settings (
            user_id INTEGER PRIMARY KEY,
            profile_json TEXT NOT NULL DEFAULT '{}',
            language_mode TEXT NOT NULL DEFAULT 'french',
            active_conversation_id INTEGER,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            subject TEXT NOT NULL DEFAULT '',
            topic TEXT NOT NULL DEFAULT '',
            course_id TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'active',
            summary TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE INDEX conversations_user_updated_idx
          ON conversations(user_id, updated_at DESC)
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id INTEGER NOT NULL,
            user_id INTEGER NOT NULL,
            is_user INTEGER NOT NULL,
            text TEXT NOT NULL,
            structured_json TEXT,
            modality TEXT NOT NULL,
            audio_duration_ms INTEGER,
            language_mode TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id)
              ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE INDEX messages_conversation_created_idx
          ON messages(conversation_id, created_at, id)
        ''');
        await db.execute('''
          CREATE TABLE skill_progress (
            user_id INTEGER NOT NULL,
            subject TEXT NOT NULL,
            topic TEXT NOT NULL,
            skill_id TEXT NOT NULL,
            skill_label TEXT NOT NULL,
            mastery INTEGER NOT NULL,
            attempts INTEGER NOT NULL,
            correct_answers INTEGER NOT NULL,
            xp INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(user_id, subject, topic, skill_id)
          )
        ''');
        await db.execute('''
          CREATE INDEX skill_progress_user_updated_idx
          ON skill_progress(user_id, updated_at DESC)
        ''');
        await db.execute('''
          CREATE TABLE progress_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            conversation_id INTEGER NOT NULL,
            course_id TEXT NOT NULL,
            event_key TEXT NOT NULL,
            activity TEXT NOT NULL,
            subject TEXT NOT NULL,
            topic TEXT NOT NULL,
            correct INTEGER,
            score INTEGER NOT NULL,
            max_score INTEGER NOT NULL,
            xp INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            UNIQUE(user_id, course_id, event_key)
          )
        ''');
        await db.execute('''
          CREATE INDEX progress_events_user_idx
          ON progress_events(user_id, created_at DESC)
        ''');
        await db.execute('''
          CREATE TABLE completed_activities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            conversation_id INTEGER NOT NULL,
            course_id TEXT NOT NULL,
            activity TEXT NOT NULL,
            subject TEXT NOT NULL,
            topic TEXT NOT NULL,
            score INTEGER NOT NULL,
            max_score INTEGER NOT NULL,
            points INTEGER NOT NULL,
            completed_at INTEGER NOT NULL,
            UNIQUE(user_id, course_id)
          )
        ''');
        await db.execute('''
          CREATE INDEX completed_activities_user_idx
          ON completed_activities(user_id, completed_at DESC)
        ''');
        await db.execute('''
          CREATE TABLE online_api_settings (
            user_id INTEGER PRIMARY KEY,
            base_url TEXT NOT NULL DEFAULT '',
            api_key TEXT NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // La version précédente sauvegardait déjà la progression dans
          // skill_progress/completed_lessons, mais gardait les discussions
          // uniquement en mémoire. On conserve cette progression et on ajoute
          // les tables persistantes manquantes.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS learning_settings (
              user_id INTEGER PRIMARY KEY,
              profile_json TEXT NOT NULL DEFAULT '{}',
              language_mode TEXT NOT NULL DEFAULT 'french',
              active_conversation_id INTEGER,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS conversations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              title TEXT NOT NULL,
              subject TEXT NOT NULL DEFAULT '',
              topic TEXT NOT NULL DEFAULT '',
              course_id TEXT NOT NULL DEFAULT '',
              status TEXT NOT NULL DEFAULT 'active',
              summary TEXT NOT NULL DEFAULT '',
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS conversations_user_updated_idx
            ON conversations(user_id, updated_at DESC)
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              conversation_id INTEGER NOT NULL,
              user_id INTEGER NOT NULL,
              is_user INTEGER NOT NULL,
              text TEXT NOT NULL,
              structured_json TEXT,
              modality TEXT NOT NULL,
              audio_duration_ms INTEGER,
              language_mode TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              FOREIGN KEY(conversation_id) REFERENCES conversations(id)
                ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS messages_conversation_created_idx
            ON messages(conversation_id, created_at, id)
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS skill_progress (
              user_id INTEGER NOT NULL,
              subject TEXT NOT NULL,
              topic TEXT NOT NULL,
              skill_id TEXT NOT NULL,
              skill_label TEXT NOT NULL,
              mastery INTEGER NOT NULL,
              attempts INTEGER NOT NULL,
              correct_answers INTEGER NOT NULL,
              xp INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY(user_id, subject, topic, skill_id)
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS skill_progress_user_updated_idx
            ON skill_progress(user_id, updated_at DESC)
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS progress_events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              conversation_id INTEGER NOT NULL,
              course_id TEXT NOT NULL,
              event_key TEXT NOT NULL,
              activity TEXT NOT NULL,
              subject TEXT NOT NULL,
              topic TEXT NOT NULL,
              correct INTEGER,
              score INTEGER NOT NULL,
              max_score INTEGER NOT NULL,
              xp INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              UNIQUE(user_id, course_id, event_key)
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS progress_events_user_idx
            ON progress_events(user_id, created_at DESC)
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS completed_activities (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              conversation_id INTEGER NOT NULL,
              course_id TEXT NOT NULL,
              activity TEXT NOT NULL,
              subject TEXT NOT NULL,
              topic TEXT NOT NULL,
              score INTEGER NOT NULL,
              max_score INTEGER NOT NULL,
              points INTEGER NOT NULL,
              completed_at INTEGER NOT NULL,
              UNIQUE(user_id, course_id)
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS completed_activities_user_idx
            ON completed_activities(user_id, completed_at DESC)
          ''');

          final legacyTables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='completed_lessons'",
          );
          if (legacyTables.isNotEmpty) {
            await db.rawInsert('''
              INSERT OR IGNORE INTO completed_activities (
                user_id, conversation_id, course_id, activity, subject, topic,
                score, max_score, points, completed_at
              )
              SELECT user_id, conversation_id, course_id, 'game', subject, topic,
                     score, max_score, points, completed_at
              FROM completed_lessons
            ''');
          }
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS progress_events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              conversation_id INTEGER NOT NULL,
              course_id TEXT NOT NULL,
              event_key TEXT NOT NULL,
              activity TEXT NOT NULL,
              subject TEXT NOT NULL,
              topic TEXT NOT NULL,
              correct INTEGER,
              score INTEGER NOT NULL,
              max_score INTEGER NOT NULL,
              xp INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              UNIQUE(user_id, course_id, event_key)
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS progress_events_user_idx
            ON progress_events(user_id, created_at DESC)
          ''');
        }
        if (oldVersion < 4) {
          // Le mode mixte n'est plus proposé. Chaque compte utilise maintenant
          // une langue unique : français ou malagasy.
          await db.execute(
            "UPDATE learning_settings SET language_mode = 'french' "
            "WHERE language_mode IS NULL OR language_mode = '' OR language_mode = 'mixed'",
          );
          await db.execute(
            "UPDATE messages SET language_mode = 'french' "
            "WHERE language_mode IS NULL OR language_mode = '' OR language_mode = 'mixed'",
          );
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS online_api_settings (
              user_id INTEGER PRIMARY KEY,
              base_url TEXT NOT NULL DEFAULT '',
              api_key TEXT NOT NULL DEFAULT '',
              updated_at INTEGER NOT NULL
            )
          ''');
        }
      },
    );
    _initialized = true;
  }

  Future<Database> _db() async {
    await initialize();
    return _database!;
  }

  int? get _accountId => _signedIn && !_guestMode ? _activeUserId : null;

  void _clearGuestData() {
    _guestConversationRecords.clear();
    _guestMessagesByConversation.clear();
    _guestSkillProgress.clear();
    _guestCompletedLessons.clear();
    _guestConversationSeed = 0;
    _guestMessageSeed = 0;
  }

  /// Efface uniquement l'état de session en mémoire.
  /// Les données SQLite du compte restent intactes pour la prochaine connexion.
  void clearRuntimeData() {
    _clearGuestData();
    _activeUserId = null;
    _activeConversationId = null;
    _languageMode = AudioLanguageMode.french;
    _localProfile = null;
    _signedIn = false;
    _guestMode = false;
    _guestOnlineApiSettings = const OnlineApiSettings();
  }

  Future<void> enterGuestMode({
    AudioLanguageMode languageMode = AudioLanguageMode.french,
  }) async {
    _clearGuestData();
    _activeUserId = null;
    _activeConversationId = null;
    _signedIn = false;
    _guestMode = true;
    _localProfile = null;
    _languageMode = languageMode.normalized;
  }

  Future<void> enterAccountMode({
    int? userId,
    Map<String, dynamic>? profile,
    AudioLanguageMode? preferredLanguageMode,
  }) async {
    await initialize();
    final authUser = LocalAuthService.instance.currentUserSync;
    final resolvedUserId = userId ?? authUser?.id;
    if (resolvedUserId == null) {
      throw StateError('Aucun compte local actif.');
    }

    _activeUserId = resolvedUserId;
    _signedIn = true;
    _guestMode = false;
    _clearGuestData();

    final db = await _db();
    final rows = await db.query(
      'learning_settings',
      where: 'user_id = ?',
      whereArgs: [resolvedUserId],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final row = rows.first;
      _languageMode = audioLanguageModeFromStorage(
        row['language_mode']?.toString(),
      );
      _activeConversationId = (row['active_conversation_id'] as num?)?.toInt();
      final storedProfile = _decodeMap(row['profile_json']);
      _localProfile = profile == null
          ? storedProfile
          : Map<String, dynamic>.from(profile);
    } else {
      _languageMode = AudioLanguageMode.french;
      _activeConversationId = null;
      _localProfile = profile == null
          ? Map<String, dynamic>.from(authUser?.profile ?? const {})
          : Map<String, dynamic>.from(profile);
      await _upsertSettings();
    }

    if (profile != null) {
      _localProfile = Map<String, dynamic>.from(profile);
      await _upsertSettings();
    }

    if (preferredLanguageMode != null) {
      _languageMode = preferredLanguageMode.normalized;
      await _upsertSettings();
    }
  }

  Future<void> restoreAccountSession({
    required int userId,
    required Map<String, dynamic> profile,
  }) {
    return enterAccountMode(userId: userId, profile: profile);
  }

  Future<bool> isGuestMode() async => _guestMode;

  Future<void> _upsertSettings() async {
    final userId = _accountId;
    if (userId == null) return;
    final db = await _db();
    await db.insert(
      'learning_settings',
      {
        'user_id': userId,
        'profile_json': jsonEncode(_localProfile ?? const <String, dynamic>{}),
        'language_mode': _languageMode.storageValue,
        'active_conversation_id': _activeConversationId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveLanguageMode(AudioLanguageMode mode) async {
    _languageMode = mode.normalized;
    if (_accountId != null) await _upsertSettings();
  }

  Future<AudioLanguageMode> loadLanguageMode() async => _languageMode;

  Future<int> getOrCreateActiveConversation() async {
    if (_guestMode) {
      final active = _activeConversationId;
      if (active != null && _guestConversationRecords.containsKey(active)) {
        return active;
      }
      final conversations = await listConversations();
      if (conversations.isNotEmpty) {
        _activeConversationId = conversations.first.id;
        return conversations.first.id;
      }
      return createConversation();
    }

    final userId = _accountId;
    if (userId == null) {
      // Avant le choix de connexion, on reste dans un mode temporaire sûr.
      await enterGuestMode();
      return createConversation();
    }

    final db = await _db();
    final active = _activeConversationId;
    if (active != null) {
      final rows = await db.query(
        'conversations',
        columns: ['id'],
        where: 'id = ? AND user_id = ?',
        whereArgs: [active, userId],
        limit: 1,
      );
      if (rows.isNotEmpty) return active;
    }

    final rows = await db.query(
      'conversations',
      columns: ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      _activeConversationId = (rows.first['id'] as num).toInt();
      await _upsertSettings();
      return _activeConversationId!;
    }
    return createConversation();
  }

  Future<void> setActiveConversation(int conversationId) async {
    if (_guestMode) {
      if (_guestConversationRecords.containsKey(conversationId)) {
        _activeConversationId = conversationId;
      }
      return;
    }
    final userId = _accountId;
    if (userId == null) return;
    final db = await _db();
    final rows = await db.query(
      'conversations',
      columns: ['id'],
      where: 'id = ? AND user_id = ?',
      whereArgs: [conversationId, userId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    _activeConversationId = conversationId;
    await _upsertSettings();
  }

  Future<int> createConversation({String title = 'Nouvelle discussion'}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanTitle = title.trim().isEmpty ? 'Nouvelle discussion' : title.trim();

    if (_guestMode) {
      final id = ++_guestConversationSeed;
      _guestConversationRecords[id] = _ConversationRecord(
        id: id,
        title: cleanTitle,
        createdAt: now,
        updatedAt: now,
      );
      _guestMessagesByConversation[id] = <StoredChatMessage>[];
      _activeConversationId = id;
      return id;
    }

    final userId = _accountId;
    if (userId == null) {
      await enterGuestMode();
      return createConversation(title: title);
    }
    final db = await _db();
    final id = await db.insert('conversations', {
      'user_id': userId,
      'title': _clipInline(cleanTitle, 80),
      'subject': '',
      'topic': '',
      'course_id': '',
      'status': 'active',
      'summary': '',
      'created_at': now,
      'updated_at': now,
    });
    _activeConversationId = id;
    await _upsertSettings();
    return id;
  }

  Future<List<StoredConversation>> listConversations() async {
    if (_guestMode) {
      final values = _guestConversationRecords.values
          .map(_guestToStoredConversation)
          .toList();
      values.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return List.unmodifiable(values);
    }

    final userId = _accountId;
    if (userId == null) return const [];
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT c.*,
             (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id)
               AS message_count,
             COALESCE((
               SELECT m2.text
               FROM messages m2
               WHERE m2.conversation_id = c.id
               ORDER BY m2.created_at DESC, m2.id DESC
               LIMIT 1
             ), '') AS preview
      FROM conversations c
      WHERE c.user_id = ?
      ORDER BY c.updated_at DESC
    ''', [userId]);
    return List.unmodifiable(rows.map(_conversationFromRow));
  }

  Future<StoredConversation?> getConversation(int conversationId) async {
    if (_guestMode) {
      final record = _guestConversationRecords[conversationId];
      return record == null ? null : _guestToStoredConversation(record);
    }
    final userId = _accountId;
    if (userId == null) return null;
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT c.*,
             (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id)
               AS message_count,
             COALESCE((
               SELECT m2.text
               FROM messages m2
               WHERE m2.conversation_id = c.id
               ORDER BY m2.created_at DESC, m2.id DESC
               LIMIT 1
             ), '') AS preview
      FROM conversations c
      WHERE c.id = ? AND c.user_id = ?
      LIMIT 1
    ''', [conversationId, userId]);
    return rows.isEmpty ? null : _conversationFromRow(rows.first);
  }

  StoredConversation _guestToStoredConversation(_ConversationRecord record) {
    final messages = _guestMessagesByConversation[record.id] ?? const [];
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

  StoredConversation _conversationFromRow(Map<String, Object?> row) {
    return StoredConversation(
      id: (row['id'] as num).toInt(),
      title: '${row['title'] ?? 'Nouvelle discussion'}',
      subject: '${row['subject'] ?? ''}',
      topic: '${row['topic'] ?? ''}',
      courseId: '${row['course_id'] ?? ''}',
      status: '${row['status'] ?? 'active'}',
      summary: '${row['summary'] ?? ''}',
      messageCount: (row['message_count'] as num?)?.toInt() ?? 0,
      updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
      preview: '${row['preview'] ?? ''}',
    );
  }

  Future<void> renameConversation(int conversationId, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_guestMode) {
      final record = _guestConversationRecords[conversationId];
      if (record == null) return;
      record
        ..title = _clipInline(clean, 80)
        ..updatedAt = now;
      return;
    }
    final userId = _accountId;
    if (userId == null) return;
    final db = await _db();
    await db.update(
      'conversations',
      {'title': _clipInline(clean, 80), 'updated_at': now},
      where: 'id = ? AND user_id = ?',
      whereArgs: [conversationId, userId],
    );
  }

  Future<void> deleteConversation(int conversationId) async {
    if (_guestMode) {
      _guestConversationRecords.remove(conversationId);
      _guestMessagesByConversation.remove(conversationId);
      if (_activeConversationId == conversationId) _activeConversationId = null;
      return;
    }
    final userId = _accountId;
    if (userId == null) return;
    final db = await _db();
    await db.delete(
      'conversations',
      where: 'id = ? AND user_id = ?',
      whereArgs: [conversationId, userId],
    );
    if (_activeConversationId == conversationId) {
      _activeConversationId = null;
      await _upsertSettings();
    }
  }

  Future<List<StoredChatMessage>> loadMessages(
    int conversationId, {
    int limit = 1000,
  }) async {
    final safeLimit = limit.clamp(1, 2000).toInt();
    if (_guestMode) {
      final values = _guestMessagesByConversation[conversationId] ?? const [];
      if (values.length <= safeLimit) return List.unmodifiable(values);
      return List.unmodifiable(values.sublist(values.length - safeLimit));
    }
    final userId = _accountId;
    if (userId == null) return const [];
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT * FROM (
        SELECT m.*
        FROM messages m
        INNER JOIN conversations c ON c.id = m.conversation_id
        WHERE m.conversation_id = ? AND m.user_id = ? AND c.user_id = ?
        ORDER BY m.created_at DESC, m.id DESC
        LIMIT ?
      ) recent
      ORDER BY created_at ASC, id ASC
    ''', [conversationId, userId, userId, safeLimit]);
    return List.unmodifiable(rows.map(_messageFromRow));
  }

  StoredChatMessage _messageFromRow(Map<String, Object?> row) {
    return StoredChatMessage(
      id: (row['id'] as num).toInt(),
      conversationId: (row['conversation_id'] as num).toInt(),
      isUser: ((row['is_user'] as num?)?.toInt() ?? 0) == 1,
      text: '${row['text'] ?? ''}',
      structuredJson: row['structured_json']?.toString(),
      modality: '${row['modality'] ?? 'text'}',
      audioDurationMs: (row['audio_duration_ms'] as num?)?.toInt(),
      languageMode: audioLanguageModeFromStorage(
        row['language_mode']?.toString(),
      ),
      createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> saveExchange({
    required int conversationId,
    required String userText,
    required String userModality,
    required AiTutorResponse assistantResponse,
    int? audioDurationMs,
    AudioLanguageMode languageMode = AudioLanguageMode.french,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final compactUser = _clipInline(userText, 1200);
    final assistantText = _clipRaw(assistantResponse.response, 5000);

    if (_guestMode) {
      final record = _guestConversationRecords[conversationId];
      if (record == null) return;
      final list = _guestMessagesByConversation.putIfAbsent(
        conversationId,
        () => <StoredChatMessage>[],
      );
      list.add(
        StoredChatMessage(
          id: ++_guestMessageSeed,
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
          id: ++_guestMessageSeed,
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
      if (list.length > 120) list.removeRange(0, list.length - 120);
      _updateGuestConversationRecord(
        record: record,
        userText: compactUser,
        assistantText: assistantText,
        assistantResponse: assistantResponse,
        updatedAt: now + 1,
      );
      return;
    }

    final userId = _accountId;
    if (userId == null) return;
    final db = await _db();
    await db.transaction((txn) async {
      final ownership = await txn.query(
        'conversations',
        columns: ['id', 'title', 'summary', 'subject', 'topic', 'course_id', 'status'],
        where: 'id = ? AND user_id = ?',
        whereArgs: [conversationId, userId],
        limit: 1,
      );
      if (ownership.isEmpty) return;

      await txn.insert('messages', {
        'conversation_id': conversationId,
        'user_id': userId,
        'is_user': 1,
        'text': compactUser,
        'structured_json': null,
        'modality': userModality,
        'audio_duration_ms': audioDurationMs,
        'language_mode': languageMode.storageValue,
        'created_at': now,
      });
      await txn.insert('messages', {
        'conversation_id': conversationId,
        'user_id': userId,
        'is_user': 0,
        'text': assistantText,
        'structured_json': assistantResponse.toCompactJson(),
        'modality': 'text',
        'audio_duration_ms': null,
        'language_mode': languageMode.storageValue,
        'created_at': now + 1,
      });

      // Conserve les discussions anciennes, tout en empêchant une seule
      // discussion de grossir sans limite sur un petit téléphone.
      await txn.rawDelete('''
        DELETE FROM messages
        WHERE conversation_id = ?
          AND id NOT IN (
            SELECT id FROM messages
            WHERE conversation_id = ?
            ORDER BY created_at DESC, id DESC
            LIMIT 300
          )
      ''', [conversationId, conversationId]);

      final lesson = assistantResponse.lesson;
      final oldTitle = '${ownership.first['title'] ?? ''}';
      final oldSummary = '${ownership.first['summary'] ?? ''}';
      final oldSubject = '${ownership.first['subject'] ?? ''}';
      final oldTopic = '${ownership.first['topic'] ?? ''}';
      final oldCourseId = '${ownership.first['course_id'] ?? ''}';
      final oldStatus = '${ownership.first['status'] ?? 'active'}';
      final localSummary = _buildLocalSummary(
        subject: lesson.subject,
        topic: lesson.topic,
        userText: compactUser,
        assistantText: assistantText,
      );
      await txn.update(
        'conversations',
        {
          'title': oldTitle == 'Nouvelle discussion' && compactUser.isNotEmpty
              ? _titleFromMessage(compactUser)
              : oldTitle,
          'subject': lesson.subject.trim().isEmpty
              ? oldSubject
              : lesson.subject.trim(),
          'topic': lesson.topic.trim().isEmpty ? oldTopic : lesson.topic.trim(),
          'course_id': lesson.courseId.trim().isEmpty
              ? oldCourseId
              : lesson.courseId.trim(),
          'status': lesson.completed
              ? 'completed'
              : lesson.isActive
                  ? 'active'
                  : oldStatus,
          'summary': _mergeSummary(oldSummary, localSummary),
          'updated_at': now + 1,
        },
        where: 'id = ? AND user_id = ?',
        whereArgs: [conversationId, userId],
      );
    });
  }

  void _updateGuestConversationRecord({
    required _ConversationRecord record,
    required String userText,
    required String assistantText,
    required AiTutorResponse assistantResponse,
    required int updatedAt,
  }) {
    final lesson = assistantResponse.lesson;
    record.updatedAt = updatedAt;
    if (record.title == 'Nouvelle discussion' && userText.isNotEmpty) {
      record.title = _titleFromMessage(userText);
    }
    if (lesson.subject.trim().isNotEmpty) record.subject = lesson.subject.trim();
    if (lesson.topic.trim().isNotEmpty) record.topic = lesson.topic.trim();
    if (lesson.courseId.trim().isNotEmpty) record.courseId = lesson.courseId.trim();
    record.status = lesson.completed ? 'completed' : 'active';
    record.summary = _mergeSummary(
      record.summary,
      _buildLocalSummary(
        subject: lesson.subject,
        topic: lesson.topic,
        userText: userText,
        assistantText: assistantText,
      ),
    );
  }

  Future<CompactConversationContext> buildCompactContext(
    int conversationId, {
    int recentMessageCount = 3,
  }) async {
    final conversation = await getConversation(conversationId);
    final messages = await loadMessages(
      conversationId,
      limit: recentMessageCount.clamp(1, 4).toInt(),
    );
    return CompactConversationContext(
      summary: _clipRaw(conversation?.summary ?? '', 220),
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
    if (_guestMode || _accountId == null) return const <String, dynamic>{};
    final userId = _accountId!;
    final db = await _db();
    final where = <String>['user_id = ?'];
    final args = <Object?>[userId];
    if (subject?.trim().isNotEmpty == true) {
      where.add('subject = ?');
      args.add(subject!.trim());
    }
    if (topic?.trim().isNotEmpty == true) {
      where.add('topic = ?');
      args.add(topic!.trim());
    }
    final rows = await db.query(
      'skill_progress',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
      limit: limit.clamp(0, 4).toInt(),
    );
    return {
      'skills': rows
          .map(
            (row) => {
              'label': '${row['skill_label'] ?? ''}',
              'mastery': (row['mastery'] as num?)?.toInt() ?? 0,
              'attempts': (row['attempts'] as num?)?.toInt() ?? 0,
            },
          )
          .toList(growable: false),
    };
  }

  /// Profil pédagogique minimal envoyé au modèle.
  /// Les coordonnées, l'e-mail, le téléphone et l'établissement ne sont
  /// jamais ajoutés au prompt.
  Future<Map<String, dynamic>> buildTutorProfile() async {
    if (_guestMode) return const <String, dynamic>{'mode': 'guest'};
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

  /// Sauvegarde automatique appelée après chaque réponse évaluée.
  ///
  /// Chaque manche de jeu validée ajoute une tentative et 1 XP. Une bonne
  /// réponse augmente aussi la maîtrise. Un journal d'événements empêche une
  /// même manche d'être comptée deux fois après un retry ou un redémarrage.
  Future<ProgressSaveResult> saveProgressIfValid({
    required int conversationId,
    required LessonState lesson,
    required ProgressUpdate progress,
  }) async {
    final userId = _accountId;
    if (_guestMode || userId == null || !progress.isValid) {
      return ProgressSaveResult.none;
    }
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

    final db = await _db();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'skill_progress',
        where: 'user_id = ? AND subject = ? AND topic = ? AND skill_id = ?',
        whereArgs: [userId, lesson.subject, lesson.topic, id],
        limit: 1,
      );
      final old = rows.isEmpty ? null : _skillFromRow(rows.first);
      final oldMastery = old?.mastery ?? 0;
      final gameActivity = <String>{
        'quiz',
        'game',
        'memory',
        'chrono',
        'true_false',
        'truefalse',
        'vrai_faux',
      }.contains(lesson.activity.toLowerCase());
      final now = DateTime.now().millisecondsSinceEpoch;

      if (gameActivity) {
        final evaluatedRound = progress.lessonCompleted
            ? lesson.gameTotal.clamp(1, 2).toInt()
            : (lesson.gameQuestion - 1).clamp(1, 2).toInt();
        final eventKey = 'game_round_$evaluatedRound';
        final existingEvent = await txn.query(
          'progress_events',
          columns: ['id'],
          where: 'user_id = ? AND course_id = ? AND event_key = ?',
          whereArgs: [userId, lesson.courseId, eventKey],
          limit: 1,
        );
        if (existingEvent.isNotEmpty) {
          return ProgressSaveResult(
            saved: true,
            positiveEvolution: false,
            pointsAdded: 0,
            mastery: oldMastery,
          );
        }
        await txn.insert('progress_events', {
          'user_id': userId,
          'conversation_id': conversationId,
          'course_id': lesson.courseId,
          'event_key': eventKey,
          'activity': lesson.activity,
          'subject': lesson.subject,
          'topic': lesson.topic,
          'correct': progress.correct == null
              ? null
              : (progress.correct! ? 1 : 0),
          'score': progress.score,
          'max_score': progress.maxScore,
          'xp': 1,
          'created_at': now,
        });
      }

      final attempts = (old?.attempts ?? 0) + 1;
      final positiveAnswer = progress.correct ??
          (progress.maxScore > 0 && progress.score == progress.maxScore);
      final correctAnswers =
          (old?.correctAnswers ?? 0) + (positiveAnswer ? 1 : 0);

      // Si Gemma ne fournit pas understanding, une bonne réponse apporte
      // quand même une petite évolution locale visible.
      final requestedMastery = progress.understanding > 0
          ? progress.understanding
          : oldMastery + (positiveAnswer ? 10 : 0);
      final newMastery = positiveAnswer
          ? requestedMastery.clamp(oldMastery, 100).toInt()
          : oldMastery;
      final positiveEvolution = newMastery > oldMastery;
      final pointsAdded = gameActivity ? 1 : 0;

      if (progress.lessonCompleted && progress.maxScore > 0) {
        await txn.insert(
          'completed_activities',
          {
            'user_id': userId,
            'conversation_id': conversationId,
            'course_id': lesson.courseId,
            'activity': lesson.activity,
            'subject': lesson.subject,
            'topic': lesson.topic,
            'score': progress.score,
            'max_score': progress.maxScore,
            'points': pointsAdded,
            'completed_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await txn.insert(
        'skill_progress',
        {
          'user_id': userId,
          'subject': lesson.subject,
          'topic': lesson.topic,
          'skill_id': id,
          'skill_label': _clipInline(label, 120),
          'mastery': newMastery,
          'attempts': attempts,
          'correct_answers': correctAnswers,
          'xp': (old?.xp ?? 0) + pointsAdded,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return ProgressSaveResult(
        saved: true,
        positiveEvolution: positiveEvolution,
        pointsAdded: pointsAdded,
        mastery: newMastery,
      );
    });
  }

  Future<LearningOverview> getLearningOverview() async {
    final userId = _accountId;
    if (_guestMode || userId == null) {
      return const LearningOverview(
        totalXp: 0,
        completedLessons: 0,
        averageMastery: 0,
        totalAttempts: 0,
        totalCorrectAnswers: 0,
        skills: [],
      );
    }
    final db = await _db();
    final rows = await db.query(
      'skill_progress',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
      limit: 100,
    );
    final skills = rows.map(_skillFromRow).toList(growable: false);
    final totalXp = skills.fold<int>(0, (sum, item) => sum + item.xp);
    final average = skills.isEmpty
        ? 0
        : (skills.fold<int>(0, (sum, item) => sum + item.mastery) /
                skills.length)
            .round();
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM completed_activities WHERE user_id = ?',
      [userId],
    );
    final completed = (countRows.first['total'] as num?)?.toInt() ?? 0;
    final totalAttempts =
        skills.fold<int>(0, (sum, item) => sum + item.attempts);
    final totalCorrectAnswers =
        skills.fold<int>(0, (sum, item) => sum + item.correctAnswers);
    return LearningOverview(
      totalXp: totalXp,
      completedLessons: completed,
      averageMastery: average,
      totalAttempts: totalAttempts,
      totalCorrectAnswers: totalCorrectAnswers,
      skills: List.unmodifiable(skills.take(20)),
    );
  }

  StoredSkillProgress _skillFromRow(Map<String, Object?> row) {
    return StoredSkillProgress(
      subject: '${row['subject'] ?? ''}',
      topic: '${row['topic'] ?? ''}',
      skillId: '${row['skill_id'] ?? ''}',
      skillLabel: '${row['skill_label'] ?? ''}',
      mastery: (row['mastery'] as num?)?.toInt() ?? 0,
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
      correctAnswers: (row['correct_answers'] as num?)?.toInt() ?? 0,
      xp: (row['xp'] as num?)?.toInt() ?? 0,
      updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> saveLocalProfile(Map<String, dynamic> profile) async {
    _localProfile = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(profile)) as Map,
    );
    if (_accountId != null) await _upsertSettings();
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

  /// Compatibilité avec les appels d'outil éventuels du modèle.
  /// La progression principale est néanmoins sauvegardée directement par
  /// ChatScreen afin qu'un JSON imparfait de Gemma ne puisse pas la perdre.
  Future<Map<String, dynamic>> applyProgressFunction({
    required int conversationId,
    required Map<String, dynamic> arguments,
  }) async {
    final rawSkills = arguments['skills'];
    Map<String, dynamic> skill = const {};
    if (rawSkills is List && rawSkills.isNotEmpty && rawSkills.first is Map) {
      skill = Map<String, dynamic>.from(rawSkills.first as Map);
    }
    final eventType = '${arguments['event_type'] ?? ''}'.trim();
    final lessonCompleted = eventType == 'lesson_completed';
    final lesson = LessonState(
      courseId: '${arguments['course_id'] ?? arguments['courseId'] ?? ''}'.trim(),
      subject: '${arguments['subject'] ?? ''}'.trim(),
      topic: '${arguments['topic'] ?? ''}'.trim(),
      activity: '${arguments['activity'] ?? 'lesson'}'.trim(),
      completed: lessonCompleted,
    );
    final progress = ProgressUpdate(
      save: true,
      skillId: '${skill['id'] ?? skill['skill_id'] ?? ''}'.trim(),
      skillLabel: '${skill['label'] ?? skill['name'] ?? ''}'.trim(),
      evidence: '${skill['evidence'] ?? arguments['summary'] ?? ''}'.trim(),
      correct: _asNullableBool(skill['correct']),
      score: _asInt(arguments['score']),
      maxScore: _asInt(arguments['max_score'] ?? arguments['maxScore']),
      understanding: _asInt(
        arguments['understanding'] ?? skill['mastery'],
      ).clamp(0, 100).toInt(),
      xp: _asInt(arguments['xp']),
      lessonCompleted: lessonCompleted,
    );
    final result = await saveProgressIfValid(
      conversationId: conversationId,
      lesson: lesson,
      progress: progress,
    );
    return {
      'saved': result.saved,
      'points_added': result.pointsAdded,
      'mastery': result.mastery,
      'positive_evolution': result.positiveEvolution,
    };
  }

  Future<Map<String, dynamic>> getProgressContext({
    String? subject,
    String? topic,
  }) async {
    final compact = await buildCompactProgress(
      subject: subject,
      topic: topic,
      limit: 4,
    );
    final overview = await getLearningOverview();
    return {
      ...compact,
      'total_xp': overview.totalXp,
      'completed_activities': overview.completedLessons,
      'average_mastery': overview.averageMastery,
      'total_attempts': overview.totalAttempts,
      'total_correct_answers': overview.totalCorrectAnswers,
    };
  }

  Future<OnlineApiSettings> loadOnlineApiSettings() async {
    if (_guestMode) return _guestOnlineApiSettings;
    final userId = _accountId;
    if (userId == null) return const OnlineApiSettings();
    final db = await _db();
    final rows = await db.query(
      'online_api_settings',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return const OnlineApiSettings();
    return OnlineApiSettings(
      baseUrl: '${rows.first['base_url'] ?? ''}'.trim(),
    );
  }

  Future<void> saveOnlineApiSettings({
    required String baseUrl,
  }) async {
    final settings = OnlineApiSettings(
      baseUrl: baseUrl.trim(),
    );
    if (_guestMode) {
      _guestOnlineApiSettings = settings;
      return;
    }
    final userId = _accountId;
    if (userId == null) {
      throw StateError('Aucun compte local actif.');
    }
    final db = await _db();
    await db.insert(
      'online_api_settings',
      {
        'user_id': userId,
        'base_url': settings.baseUrl,
        // Colonne historique conservée uniquement pour la compatibilité SQLite.
        'api_key': '',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> runMaintenance() async {
    final userId = _accountId;
    if (userId == null) return;
    final db = await _db();
    // Suppression uniquement des discussions vides abandonnées depuis 30 jours.
    // Les discussions contenant des messages sont conservées.
    final threshold = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await db.rawDelete('''
      DELETE FROM conversations
      WHERE user_id = ?
        AND updated_at < ?
        AND NOT EXISTS (
          SELECT 1 FROM messages WHERE messages.conversation_id = conversations.id
        )
    ''', [userId, threshold]);
  }
}

Map<String, dynamic> _decodeMap(Object? value) {
  try {
    final decoded = jsonDecode('${value ?? '{}'}');
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  } catch (_) {
    return {};
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

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('${value ?? ''}'.trim()) ?? fallback;
}

bool? _asNullableBool(dynamic value) {
  if (value is bool) return value;
  final normalized = '${value ?? ''}'.trim().toLowerCase();
  if (<String>{'true', '1', 'yes', 'oui', 'vrai', 'correct'}.contains(normalized)) {
    return true;
  }
  if (<String>{'false', '0', 'no', 'non', 'faux', 'incorrect'}.contains(normalized)) {
    return false;
  }
  return null;
}
