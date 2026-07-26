import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

class LocalAuthUser {
  const LocalAuthUser({
    required this.id,
    required this.profile,
  });

  final int id;
  final Map<String, dynamic> profile;
}

class LocalAuthResult {
  const LocalAuthResult._({
    required this.success,
    required this.message,
    this.user,
  });

  final bool success;
  final String message;
  final LocalAuthUser? user;

  factory LocalAuthResult.ok(LocalAuthUser user) => LocalAuthResult._(
        success: true,
        message: '',
        user: user,
      );

  factory LocalAuthResult.error(String message) => LocalAuthResult._(
        success: false,
        message: message,
      );
}

/// Authentification locale et hors ligne.
///
/// Cette base ne contient que les comptes et la session. Les discussions et
/// la progression sont enregistrées dans gemmafy_learning.db.
class LocalAuthService {
  LocalAuthService._();

  static final LocalAuthService instance = LocalAuthService._();

  Database? _database;
  LocalAuthUser? _currentUser;

  LocalAuthUser? get currentUserSync => _currentUser;
  bool get isSignedInSync => _currentUser != null;

  Future<void> initialize() async {
    if (_database != null) return;
    final base = await getDatabasesPath();
    _database = await openDatabase(
      '$base/gemmafy_auth.db',
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT,
            phone TEXT,
            password_hash TEXT NOT NULL,
            password_salt TEXT NOT NULL,
            profile_json TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX users_email_unique
          ON users(lower(email))
          WHERE email IS NOT NULL AND email <> ''
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX users_phone_unique
          ON users(phone)
          WHERE phone IS NOT NULL AND phone <> ''
        ''');
        await db.execute('''
          CREATE TABLE auth_session (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            user_id INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        ''');
      },
    );
    await _restoreRememberedSession();
  }

  Future<LocalAuthResult> register({
    required Map<String, dynamic> profile,
    required String password,
    bool remember = true,
  }) async {
    await initialize();
    final db = _database!;
    final email = _normalizeEmail('${profile['email'] ?? ''}');
    final phone = _normalizePhone('${profile['phone'] ?? ''}');

    if (email.isEmpty && phone.isEmpty) {
      return LocalAuthResult.error(
        'Ajoute une adresse e-mail ou un numéro de téléphone.',
      );
    }
    if (password.length < 6) {
      return LocalAuthResult.error(
        'Le mot de passe doit contenir au moins 6 caractères.',
      );
    }

    final existing = await _findUserRow(email: email, phone: phone);
    if (existing != null) {
      return LocalAuthResult.error(
        'Un compte existe déjà avec cet e-mail ou ce téléphone.',
      );
    }

    final random = Random.secure();
    final saltBytes = List<int>.generate(
      16,
      (_) => random.nextInt(256),
      growable: false,
    );
    final salt = base64UrlEncode(saltBytes).replaceAll('=', '');
    final passwordHash = _PasswordHasher.hash(password, saltBytes);
    final cleanProfile = Map<String, dynamic>.from(profile)
      ..['email'] = email
      ..['phone'] = phone;

    try {
      final id = await db.insert('users', {
        'email': email.isEmpty ? null : email,
        'phone': phone.isEmpty ? null : phone,
        'password_hash': passwordHash,
        'password_salt': salt,
        'profile_json': jsonEncode(cleanProfile),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final user = LocalAuthUser(id: id, profile: cleanProfile);
      _currentUser = user;
      await _writeSession(user.id, remember: remember);
      return LocalAuthResult.ok(user);
    } on DatabaseException catch (error) {
      if (error.toString().toLowerCase().contains('unique constraint')) {
        return LocalAuthResult.error(
          'Un compte existe déjà avec cet e-mail ou ce téléphone.',
        );
      }
      return LocalAuthResult.error('Création du compte impossible.');
    }
  }

  Future<LocalAuthResult> login({
    required String identifier,
    required String password,
    required bool remember,
  }) async {
    await initialize();
    final cleanIdentifier = identifier.trim();
    if (cleanIdentifier.isEmpty || password.isEmpty) {
      return LocalAuthResult.error('Saisis ton identifiant et ton mot de passe.');
    }

    final isEmail = cleanIdentifier.contains('@');
    final email = isEmail ? _normalizeEmail(cleanIdentifier) : '';
    final phone = isEmail ? '' : _normalizePhone(cleanIdentifier);
    final row = await _findUserRow(email: email, phone: phone);
    if (row == null) {
      return LocalAuthResult.error('Compte introuvable sur ce téléphone.');
    }

    final salt = _decodeSalt('${row['password_salt']}');
    final expected = '${row['password_hash']}';
    final actual = _PasswordHasher.hash(password, salt);
    if (!_constantTimeEquals(expected, actual)) {
      return LocalAuthResult.error('Mot de passe incorrect.');
    }

    final user = _userFromRow(row);
    _currentUser = user;
    await _writeSession(user.id, remember: remember);
    return LocalAuthResult.ok(user);
  }

  Future<void> logout() async {
    await initialize();
    _currentUser = null;
    await _database!.delete('auth_session');
  }

  Future<LocalAuthUser?> currentUser() async {
    await initialize();
    return _currentUser;
  }

  Future<Map<String, Object?>?> _findUserRow({
    required String email,
    required String phone,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (email.isNotEmpty) {
      conditions.add('lower(email) = ?');
      args.add(email);
    }
    if (phone.isNotEmpty) {
      conditions.add('phone = ?');
      args.add(phone);
    }
    if (conditions.isEmpty) return null;

    final rows = await _database!.query(
      'users',
      where: conditions.join(' OR '),
      whereArgs: args,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _restoreRememberedSession() async {
    final db = _database!;
    final rows = await db.rawQuery('''
      SELECT users.*
      FROM auth_session
      INNER JOIN users ON users.id = auth_session.user_id
      WHERE auth_session.id = 1
      LIMIT 1
    ''');
    _currentUser = rows.isEmpty ? null : _userFromRow(rows.first);
  }

  Future<void> _writeSession(int userId, {required bool remember}) async {
    final db = _database!;
    await db.delete('auth_session');
    if (!remember) return;
    await db.insert('auth_session', {
      'id': 1,
      'user_id': userId,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  LocalAuthUser _userFromRow(Map<String, Object?> row) {
    Map<String, dynamic> profile;
    try {
      profile = Map<String, dynamic>.from(
        jsonDecode('${row['profile_json']}') as Map,
      );
    } catch (_) {
      profile = <String, dynamic>{};
    }
    return LocalAuthUser(
      id: (row['id'] as num).toInt(),
      profile: profile,
    );
  }
}

String _normalizeEmail(String value) => value.trim().toLowerCase();

String _normalizePhone(String value) {
  var clean = value.replaceAll(RegExp(r'[^0-9+]'), '');
  if (clean.startsWith('00')) clean = '+${clean.substring(2)}';
  if (clean.startsWith('0') && clean.length == 10) {
    clean = '+261${clean.substring(1)}';
  }
  return clean;
}

List<int> _decodeSalt(String value) {
  final normalized = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return base64Url.decode(normalized);
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

class _PasswordHasher {
  static const int _rounds = 2500;

  static String hash(String password, List<int> salt) {
    final passwordBytes = utf8.encode(password);
    var block = _sha256(<int>[...salt, ...passwordBytes]);
    for (var i = 1; i < _rounds; i++) {
      block = _sha256(<int>[...block, ...salt, ...passwordBytes]);
    }
    return base64UrlEncode(block).replaceAll('=', '');
  }
}

const List<int> _sha256Constants = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

List<int> _sha256(List<int> input) {
  final message = List<int>.from(input);
  final bitLength = message.length * 8;
  message.add(0x80);
  while (message.length % 64 != 56) {
    message.add(0);
  }
  for (var shift = 56; shift >= 0; shift -= 8) {
    message.add((bitLength ~/ (1 << shift)) & 0xff);
  }

  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;
  final words = List<int>.filled(64, 0);

  for (var offset = 0; offset < message.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      final index = offset + i * 4;
      words[i] = ((message[index] << 24) |
              (message[index + 1] << 16) |
              (message[index + 2] << 8) |
              message[index + 3]) &
          0xffffffff;
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotateRight(words[i - 15], 7) ^
          _rotateRight(words[i - 15], 18) ^
          (words[i - 15] >>> 3);
      final s1 = _rotateRight(words[i - 2], 17) ^
          _rotateRight(words[i - 2], 19) ^
          (words[i - 2] >>> 10);
      words[i] = (words[i - 16] + s0 + words[i - 7] + s1) & 0xffffffff;
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;

    for (var i = 0; i < 64; i++) {
      final sum1 = _rotateRight(e, 6) ^
          _rotateRight(e, 11) ^
          _rotateRight(e, 25);
      final choice = (e & f) ^ ((~e) & g);
      final temp1 =
          (h + sum1 + choice + _sha256Constants[i] + words[i]) & 0xffffffff;
      final sum0 = _rotateRight(a, 2) ^
          _rotateRight(a, 13) ^
          _rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (sum0 + majority) & 0xffffffff;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }

    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
  }

  final digest = <int>[];
  for (final value in <int>[h0, h1, h2, h3, h4, h5, h6, h7]) {
    digest
      ..add((value >>> 24) & 0xff)
      ..add((value >>> 16) & 0xff)
      ..add((value >>> 8) & 0xff)
      ..add(value & 0xff);
  }
  return digest;
}

int _rotateRight(int value, int amount) =>
    ((value >>> amount) | ((value << (32 - amount)) & 0xffffffff)) &
    0xffffffff;
