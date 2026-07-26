import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/online_tool_response.dart';

class GemmifyIkomException implements Exception {
  final String message;
  final bool canRetry;

  const GemmifyIkomException(this.message, {this.canRetry = false});

  @override
  String toString() => message;
}

class GemmifyIkomValidationException extends GemmifyIkomException {
  const GemmifyIkomValidationException(String message) : super(message);
}

class GemmifyIkomTimeoutException extends GemmifyIkomException {
  const GemmifyIkomTimeoutException(String message)
      : super(message, canRetry: true);
}

class GemmifyIkomNetworkException extends GemmifyIkomException {
  const GemmifyIkomNetworkException(String message)
      : super(message, canRetry: true);
}

class GemmifyIkomServerException extends GemmifyIkomException {
  final int statusCode;

  const GemmifyIkomServerException(
    this.statusCode,
    String message,
  ) : super(message, canRetry: true);
}

class OnlinePickedFile {
  final String path;
  final String name;
  final int sizeBytes;

  const OnlinePickedFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  String get extension {
    final index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index + 1).toLowerCase();
  }
}

class GemmifyIkomService {
  GemmifyIkomService._();

  static final GemmifyIkomService instance = GemmifyIkomService._();

  static const String defaultBaseUrl = String.fromEnvironment(
    'GEMMIFY_IKOM_BASE_URL',
    defaultValue: 'http://192.168.10.102:8000',
  );

  static const Set<String> acceptedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'pdf',
    'txt',
    'md',
    'csv',
  };

  static const int maxFiles = 40;
  static const int maxFileBytes = 15 * 1024 * 1024;
  static const int maxTotalBytes = 120 * 1024 * 1024;

  HttpClient _newClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    client.idleTimeout = const Duration(seconds: 20);
    return client;
  }

  Uri _endpoint(String baseUrl, String path) {
    final normalized = baseUrl.trim();
    if (normalized.isEmpty) {
      throw const GemmifyIkomValidationException(
        'L’adresse de l’API Gemmify IKOM n’est pas configurée.',
      );
    }
    final base = Uri.tryParse(normalized);
    if (base == null ||
        (base.scheme != 'http' && base.scheme != 'https') ||
        base.host.isEmpty) {
      throw const GemmifyIkomValidationException(
        'L’adresse de l’API est invalide. Utilise une adresse http ou https complète.',
      );
    }
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final prefix = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: '$prefix$cleanPath');
  }

  Future<bool> hasConnectivity(String baseUrl) async {
    try {
      final uri = _endpoint(baseUrl, '/');
      if (InternetAddress.tryParse(uri.host) != null ||
          uri.host == 'localhost') {
        return true;
      }
      final result = await InternetAddress.lookup(uri.host)
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<OnlineToolResponse> analyzeCopies({
    required String baseUrl,
    required String text,
    required List<OnlinePickedFile> files,
    String languageCode = 'fr',
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final instruction = text.trim();
    if (instruction.isEmpty) {
      throw const GemmifyIkomValidationException(
        'Écris une consigne ou le corrigé attendu avant l’envoi.',
      );
    }
    _validateFiles(files);
    if (!await hasConnectivity(baseUrl)) {
      throw const GemmifyIkomNetworkException(
        'Aucune connexion internet utilisable n’a été détectée.',
      );
    }

    final uri = _endpoint(baseUrl, '/api/gemmify-ikom/chat/');
    return _postMultipart(
      uri: uri,
      fields: {
        'texte': instruction,
        'language_code': languageCode,
      },
      files: files,
      fileFieldName: 'fichiers',
      timeout: timeout,
      responseOnly: true,
    );
  }

  Future<OnlineToolResponse> generateTutorial({
    required String baseUrl,
    required String subject,
    String context = '',
    String voiceSex = 'MASCULIN',
    int maxDuration = 15,
    String languageCode = 'fr',
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final cleanSubject = subject.trim();
    if (cleanSubject.isEmpty) {
      throw const GemmifyIkomValidationException(
        'Le sujet du tutoriel vidéo ne peut pas être vide.',
      );
    }
    if (maxDuration < 15 || maxDuration > 120) {
      throw const GemmifyIkomValidationException(
        'La durée maximale doit être comprise entre 15 et 120 secondes.',
      );
    }
    if (!await hasConnectivity(baseUrl)) {
      throw const GemmifyIkomNetworkException(
        'Cette fonctionnalité nécessite une connexion internet ou le même réseau local que le serveur.',
      );
    }

    final uri = _endpoint(baseUrl, '/api/gemmify-ikom/generate-tutorial/');
    final client = _newClient();
    try {
      final normalizedVoice = _normalizeVoice(voiceSex);
      var cleanContext = context.trim();
      if (languageCode.toLowerCase() == 'mg' &&
          !cleanContext.toLowerCase().contains('teny malagasy')) {
        cleanContext = cleanContext.isEmpty
            ? 'Ataovy amin’ny teny malagasy manontolo ny script sy ny fanazavana.'
            : '$cleanContext\n\nAtaovy amin’ny teny malagasy manontolo ny script sy ny fanazavana.';
      }

      // Le premier schéma conserve celui de la version stable précédente.
      // Si le backend répond 422, un seul essai de compatibilité est effectué
      // avec les noms renvoyés par la version actuelle de l'API.
      OnlineToolResponse parsed;
      try {
        parsed = await _postTutorialJson(
          client: client,
          uri: uri,
          timeout: timeout,
          payload: {
            'sujet': cleanSubject,
            if (cleanContext.isNotEmpty) 'contexte': cleanContext,
            'sexe': _legacyVoice(normalizedVoice),
            'max_duration': maxDuration,
            'language_code': languageCode,
          },
        );
      } on GemmifyIkomValidationException {
        parsed = await _postTutorialJson(
          client: client,
          uri: uri,
          timeout: timeout,
          payload: {
            'sujet': cleanSubject,
            if (cleanContext.isNotEmpty) 'contexte': cleanContext,
            'voix': normalizedVoice,
            'duree_max': maxDuration,
          },
        );
      }

      final playableUrl = _resolveMediaUrl(
        rawUrl: parsed.videoUrl,
        baseUrl: baseUrl,
      );
      return parsed.copyWith(videoUrl: playableUrl);
    } on TimeoutException {
      throw const GemmifyIkomTimeoutException(
        'La génération vidéo prend trop de temps. Réessaie sans quitter l’écran.',
      );
    } on SocketException catch (error) {
      throw GemmifyIkomNetworkException(
        'Impossible de joindre le serveur : ${error.message}',
      );
    } on HandshakeException {
      throw const GemmifyIkomNetworkException(
        'La connexion sécurisée avec le serveur a échoué.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<OnlineToolResponse> _postTutorialJson({
    required HttpClient client,
    required Uri uri,
    required Map<String, dynamic> payload,
    required Duration timeout,
  }) async {
    final request = await client.postUrl(uri).timeout(
          const Duration(seconds: 15),
        );
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.write(jsonEncode(payload));

    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    return _parseHttpResponse(response.statusCode, body);
  }

  Future<OnlineToolResponse> _postMultipart({
    required Uri uri,
    required Map<String, String> fields,
    required List<OnlinePickedFile> files,
    required String fileFieldName,
    required Duration timeout,
    bool responseOnly = false,
  }) async {
    final client = _newClient();
    final boundary = '----mpanabe-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';
    try {
      final request = await client.postUrl(uri).timeout(
            const Duration(seconds: 15),
          );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.bufferOutput = false;

      for (final entry in fields.entries) {
        request.add(utf8.encode('--$boundary\r\n'));
        request.add(utf8.encode(
          'Content-Disposition: form-data; name="${_escapeHeader(entry.key)}"\r\n\r\n',
        ));
        request.add(utf8.encode(entry.value));
        request.add(const [13, 10]);
      }

      for (final item in files) {
        final file = File(item.path);
        if (!await file.exists()) {
          throw GemmifyIkomValidationException(
            'Le fichier « ${item.name} » est introuvable.',
          );
        }
        request.add(utf8.encode('--$boundary\r\n'));
        request.add(utf8.encode(
          'Content-Disposition: form-data; name="${_escapeHeader(fileFieldName)}"; filename="${_escapeHeader(item.name)}"\r\n',
        ));
        request.add(utf8.encode(
          'Content-Type: ${_mimeType(item.extension)}\r\n\r\n',
        ));
        await request.addStream(file.openRead());
        request.add(const [13, 10]);
      }

      request.add(utf8.encode('--$boundary--\r\n'));
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      return _parseHttpResponse(
        response.statusCode,
        body,
        responseOnly: responseOnly,
      );
    } on TimeoutException {
      throw const GemmifyIkomTimeoutException(
        'Le serveur met trop de temps à analyser les fichiers. Tu peux réessayer.',
      );
    } on SocketException catch (error) {
      throw GemmifyIkomNetworkException(
        'Impossible de joindre le serveur : ${error.message}',
      );
    } on HandshakeException {
      throw const GemmifyIkomNetworkException(
        'La connexion sécurisée avec le serveur a échoué.',
      );
    } finally {
      client.close(force: true);
    }
  }

  OnlineToolResponse _parseHttpResponse(
    int statusCode,
    String body, {
    bool responseOnly = false,
  }) {
    if (statusCode >= 200 && statusCode < 300) {
      return responseOnly
          ? OnlineToolResponse.fromChatHttpBody(body)
          : OnlineToolResponse.fromHttpBody(body);
    }

    final serverMessage = _extractServerMessage(body);
    if (statusCode == 422) {
      throw GemmifyIkomValidationException(
        serverMessage.isEmpty
            ? 'Les données envoyées ne sont pas valides. Vérifie le texte et les fichiers.'
            : serverMessage,
      );
    }
    if (statusCode >= 500) {
      throw GemmifyIkomServerException(
        statusCode,
        'Le service en ligne rencontre un problème temporaire. Réessaie dans un instant.',
      );
    }
    if (statusCode == 401 || statusCode == 403) {
      throw const GemmifyIkomValidationException(
        'Le serveur a refusé la requête. Vérifie que le backend autorise cet appareil.',
      );
    }
    if (statusCode == 404) {
      throw const GemmifyIkomValidationException(
        'L’endpoint demandé est introuvable. Vérifie l’adresse de l’API.',
      );
    }
    throw GemmifyIkomException(
      serverMessage.isEmpty
          ? 'Erreur HTTP $statusCode pendant l’appel au service.'
          : serverMessage,
      canRetry: statusCode == 408 || statusCode == 429,
    );
  }

  void _validateFiles(List<OnlinePickedFile> files) {
    if (files.isEmpty) {
      throw const GemmifyIkomValidationException(
        'Ajoute au moins une copie, une image, un PDF ou un fichier texte.',
      );
    }
    if (files.length > maxFiles) {
      throw GemmifyIkomValidationException(
        'Tu peux envoyer au maximum $maxFiles fichiers à la fois.',
      );
    }

    var total = 0;
    for (final file in files) {
      if (!acceptedExtensions.contains(file.extension)) {
        throw GemmifyIkomValidationException(
          'Le format de « ${file.name} » n’est pas accepté.',
        );
      }
      if (file.sizeBytes <= 0) {
        throw GemmifyIkomValidationException(
          'Le fichier « ${file.name} » est vide.',
        );
      }
      if (file.sizeBytes > maxFileBytes) {
        throw GemmifyIkomValidationException(
          'Le fichier « ${file.name} » dépasse 15 Mo.',
        );
      }
      total += file.sizeBytes;
    }
    if (total > maxTotalBytes) {
      throw const GemmifyIkomValidationException(
        'L’ensemble des fichiers dépasse 120 Mo. Réduis ou sépare l’envoi.',
      );
    }
  }
}

String _normalizeVoice(String value) {
  final normalized = value.trim().toUpperCase();
  if (normalized.contains('FEM') || normalized.contains('FEMME')) {
    return 'FEMININ';
  }
  return 'MASCULIN';
}

String _legacyVoice(String normalizedVoice) {
  return normalizedVoice == 'FEMININ' ? 'femme' : 'homme';
}

/// Utilise immédiatement le `video_url` renvoyé dans la réponse FastAPI.
/// Les URL normales restent inchangées. Deux corrections de transport sont
/// toutefois nécessaires sur téléphone : une URL relative est complétée avec
/// le backend, et un hôte de boucle locale (`127.0.0.1`, `localhost`) est
/// remplacé par l'hôte du backend configuré. Le fichier vidéo n'est ni copié
/// ni téléchargé par un autre endpoint.
String _resolveMediaUrl({
  required String rawUrl,
  required String baseUrl,
}) {
  final clean = rawUrl.trim();
  if (clean.isEmpty) return '';

  final normalizedBase = baseUrl.trim();
  final base = Uri.tryParse(
    normalizedBase.endsWith('/') ? normalizedBase : '$normalizedBase/',
  );

  final media = Uri.tryParse(clean);
  if (media == null) return clean;

  if (!media.hasScheme) {
    if (base == null || base.host.isEmpty) return clean;
    return base.resolve(clean).toString();
  }

  final host = media.host.toLowerCase();
  final isLoopback = host == '127.0.0.1' ||
      host == 'localhost' ||
      host == '0.0.0.0' ||
      host == '::1';
  if (!isLoopback || base == null || base.host.isEmpty) return clean;

  return media
      .replace(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
      )
      .toString();
}

String _extractServerMessage(String body) {
  final clean = body.trim();
  if (clean.isEmpty) return '';
  try {
    final decoded = jsonDecode(clean);
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final value = map['detail'] ??
          map['message'] ??
          map['error'] ??
          map['response'];
      if (value is String) return value.trim();
      if (value != null) return jsonEncode(value);
    }
  } catch (_) {}
  return clean.length <= 280 ? clean : '${clean.substring(0, 279)}…';
}

String _escapeHeader(String value) {
  return value.replaceAll('"', '').replaceAll('\r', '').replaceAll('\n', '');
}

String _mimeType(String extension) {
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    case 'md':
      return 'text/markdown';
    case 'csv':
      return 'text/csv';
    default:
      return 'application/octet-stream';
  }
}
