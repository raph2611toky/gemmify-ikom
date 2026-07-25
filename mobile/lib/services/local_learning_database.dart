import 'package:sqflite/sqflite.dart';

import '../models/audio_language_mode.dart';

class StoredChatMessage {
  final int id;
  final int conversationId;
  final bool isUser;
  final String text;
  final String modality;
  final int? audioDurationMs;
  final AudioLanguageMode languageMode;
  final int createdAt;

  const StoredChatMessage({
    required this.id,
    required this.conversationId,
    required this.isUser,
    required this.text,
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
      modality: (map['modality'] as String?) ?? 'text',
      audioDurationMs: map['audio_duration_ms'] as int?,
      languageMode: audioLanguageModeFromStorage(
        map['language_mode'] as String?,
      ),
      createdAt: (map['created_at'] as int?) ?? 0,
    );
  }
}

/// Base SQLite locale de Gemmafy.
///
/// La V10 conserve la discussion active sur le téléphone. Les fichiers audio
/// et les images ne sont pas enregistrés : seule la structure du message et
/// le texte de la réponse sont persistés. Pendant que l'application reste
/// ouverte, la session native garde le contexte multimodal exact.
class LocalLearningDatabase {
  LocalLearningDatabase._();

  static final LocalLearningDatabase instance = LocalLearningDatabase._();

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
      version: 2,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE app_settings (
            setting_key TEXT PRIMARY KEY,
            setting_value TEXT NOT NULL
          )
        ''');
        await _createChatTables(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createChatTables(database);
        }
      },
    );

    _database = db;
    return db;
  }

  static Future<void> _createChatTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
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

  Future<int> createConversation({String title = 'Discussion principale'}) async {
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
    await _saveSetting('active_conversation_id', '$id');
    return id;
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
    required String assistantText,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((transaction) async {
      await transaction.insert(
        'chat_messages',
        {
          'conversation_id': conversationId,
          'role': 'user',
          'text': userText,
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
          'text': assistantText,
          'modality': 'text',
          'audio_duration_ms': null,
          'language_mode': languageMode.storageValue,
          'created_at': now + 1,
        },
      );

      await transaction.update(
        'conversations',
        {'updated_at': now + 1},
        where: 'id = ?',
        whereArgs: [conversationId],
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
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
