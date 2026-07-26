import 'dart:convert';

class OnlineToolChoice {
  final String label;
  final String message;

  const OnlineToolChoice({
    required this.label,
    required this.message,
  });

  factory OnlineToolChoice.fromDynamic(dynamic value) {
    if (value is String) {
      final clean = _clean(value);
      return OnlineToolChoice(label: clean, message: clean);
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final label = _clean(
        map['label'] ?? map['title'] ?? map['text'] ?? map['value'],
      );
      final message = _clean(
        map['message'] ?? map['prompt'] ?? map['value'] ?? label,
      );
      return OnlineToolChoice(
        label: label.isEmpty ? message : label,
        message: message.isEmpty ? label : message,
      );
    }
    final clean = _clean(value);
    return OnlineToolChoice(label: clean, message: clean);
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'message': message,
      };
}

/// Réponse commune aux outils Gemmify IKOM.
///
/// Certains endpoints renvoient un objet externe dont le champ `response`
/// contient lui-même une chaîne JSON. Le parseur réalise donc un second
/// `jsonDecode`. Si cette chaîne interne est tronquée ou mal formée, elle est
/// conservée telle quelle dans [report] au lieu de provoquer une erreur opaque.
///
/// L'endpoint vidéo réel renvoie notamment :
/// `success`, `video_url`, `script`, `sujet`, `duree_max` et `voix`.
class OnlineToolResponse {
  final String report;
  final List<OnlineToolChoice> choices;
  final String videoUrl;
  final String status;
  final String jobId;
  final String script;
  final String subject;
  final String voice;
  final int? durationSeconds;
  final bool success;
  final Map<String, dynamic> raw;

  const OnlineToolResponse({
    required this.report,
    this.choices = const [],
    this.videoUrl = '',
    this.status = '',
    this.jobId = '',
    this.script = '',
    this.subject = '',
    this.voice = '',
    this.durationSeconds,
    this.success = true,
    this.raw = const {},
  });

  bool get hasVideo => videoUrl.trim().isNotEmpty;
  bool get isPending {
    final value = status.toLowerCase();
    return value == 'pending' ||
        value == 'processing' ||
        value == 'queued' ||
        value == 'en_cours';
  }

  OnlineToolResponse copyWith({
    String? report,
    List<OnlineToolChoice>? choices,
    String? videoUrl,
    String? status,
    String? jobId,
    String? script,
    String? subject,
    String? voice,
    int? durationSeconds,
    bool? success,
    Map<String, dynamic>? raw,
  }) {
    return OnlineToolResponse(
      report: report ?? this.report,
      choices: choices ?? this.choices,
      videoUrl: videoUrl ?? this.videoUrl,
      status: status ?? this.status,
      jobId: jobId ?? this.jobId,
      script: script ?? this.script,
      subject: subject ?? this.subject,
      voice: voice ?? this.voice,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      success: success ?? this.success,
      raw: raw ?? this.raw,
    );
  }

  /// Parse la réponse du endpoint `/chat/` en ne conservant que le champ
  /// externe `response`. Aucun autre champ du backend n'est affiché dans
  /// l'interface d'analyse. Si `response` contient lui-même du JSON, seul son
  /// texte principal (`reponse`, `response`, `message`, `text` ou `content`)
  /// est extrait. En cas de JSON interne tronqué, le contenu brut reste visible.
  factory OnlineToolResponse.fromChatHttpBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const OnlineToolResponse(
        report: 'Le serveur a renvoyé une réponse vide.',
        success: false,
      );
    }

    dynamic outer;
    try {
      outer = jsonDecode(trimmed);
    } catch (_) {
      // Réponse non JSON : elle est déjà le contenu à afficher.
      return OnlineToolResponse(report: trimmed);
    }

    if (outer is! Map) {
      return OnlineToolResponse(report: _clean(outer));
    }

    final outerMap = Map<String, dynamic>.from(outer);
    if (!outerMap.containsKey('response')) {
      return const OnlineToolResponse(
        report: 'Le serveur n’a renvoyé aucun champ response lisible.',
        success: false,
      );
    }

    final rawResponse = outerMap['response'];
    var visible = '';

    if (rawResponse is String) {
      final clean = rawResponse.trim();
      if (clean.isNotEmpty) {
        try {
          visible = _mainResponseText(jsonDecode(clean));
        } catch (_) {
          // Le backend peut renvoyer un texte normal ou un JSON interrompu.
          // On tente d'abord d'extraire le texte principal sans afficher les
          // champs techniques autour.
          visible = _partialResponseText(clean);
          if (visible.isEmpty) visible = clean;
        }
      }
    } else {
      visible = _mainResponseText(rawResponse);
    }

    return OnlineToolResponse(
      report: visible.isEmpty
          ? 'Le traitement est terminé, mais la réponse est vide.'
          : visible,
      success: visible.isNotEmpty,
      raw: <String, dynamic>{'response': rawResponse},
    );
  }

  factory OnlineToolResponse.fromHttpBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const OnlineToolResponse(
        report: 'Le serveur a renvoyé une réponse vide.',
        success: false,
      );
    }

    dynamic outer;
    try {
      outer = jsonDecode(trimmed);
    } catch (_) {
      return OnlineToolResponse(report: trimmed);
    }

    if (outer is! Map) {
      return OnlineToolResponse(report: _clean(outer));
    }

    final outerMap = Map<String, dynamic>.from(outer);
    dynamic inner = outerMap['response'];
    var rawInnerFallback = '';

    if (inner is String) {
      rawInnerFallback = inner.trim();
      if (rawInnerFallback.isNotEmpty) {
        try {
          inner = jsonDecode(rawInnerFallback);
        } catch (_) {
          // Afficher le contenu brut plutôt qu'une erreur de parsing opaque.
          inner = <String, dynamic>{'reponse': rawInnerFallback};
        }
      }
    }

    final payload = <String, dynamic>{...outerMap};
    if (inner is Map) {
      payload.addAll(Map<String, dynamic>.from(inner));
    } else if (inner != null && _clean(inner).isNotEmpty) {
      payload['reponse'] = _clean(inner);
    }

    final script = _firstNonEmpty([
      payload['script'],
      payload['scenario'],
      payload['texte_video'],
    ]);

    final report = _firstNonEmpty([
      payload['reponse'],
      payload['report'],
      payload['rapport'],
      payload['message'],
      payload['result'],
      payload['texte'],
      payload['content'],
      // Pour la vidéo, le script est le contenu principal à présenter.
      script,
      // Le champ externe est utilisé en dernier recours seulement.
      rawInnerFallback,
    ]);

    final choices = _parseChoices(
      payload['choix'] ?? payload['choices'] ?? payload['actions'],
    );

    final successValue = payload['success'];
    final success = successValue is bool
        ? successValue
        : !{'false', '0', 'non', 'no'}.contains(
            _clean(successValue).toLowerCase(),
          );

    final directVideoUrl = _findVideoUrl(outerMap);

    return OnlineToolResponse(
      report: report.isEmpty
          ? 'Le traitement est terminé, mais aucun contenu lisible n’a été renvoyé.'
          : report,
      choices: choices,
      // Le champ vidéo du JSON externe est prioritaire : il vient directement
      // de la réponse FastAPI. Le payload fusionné reste un secours compatible.
      videoUrl: directVideoUrl.isNotEmpty
          ? directVideoUrl
          : _findVideoUrl(payload),
      status: _firstNonEmpty([
        payload['status'],
        payload['etat'],
        payload['state'],
      ]),
      jobId: _firstNonEmpty([
        payload['job_id'],
        payload['task_id'],
        payload['request_id'],
        payload['id'],
      ]),
      script: script,
      subject: _firstNonEmpty([
        payload['sujet'],
        payload['subject'],
        payload['topic'],
      ]),
      voice: _firstNonEmpty([
        payload['voix'],
        payload['voice'],
        payload['sexe'],
      ]),
      durationSeconds: _parseInt(
        payload['duree_max'] ??
            payload['max_duration'] ??
            payload['duration'] ??
            payload['duree'],
      ),
      success: success,
      raw: payload,
    );
  }

  Map<String, dynamic> toJson() => {
        'report': report,
        'choices': choices.map((item) => item.toJson()).toList(),
        if (videoUrl.isNotEmpty) 'video_url': videoUrl,
        if (status.isNotEmpty) 'status': status,
        if (jobId.isNotEmpty) 'job_id': jobId,
        if (script.isNotEmpty) 'script': script,
        if (subject.isNotEmpty) 'sujet': subject,
        if (voice.isNotEmpty) 'voix': voice,
        if (durationSeconds != null) 'duree_max': durationSeconds,
        'success': success,
        'raw': raw,
      };
}

String _partialResponseText(String source) {
  final complete = RegExp(
    r'"(?:reponse|response|message|text|texte|content)"\s*:\s*"((?:\\.|[^"])*)"',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(source);
  if (complete != null) {
    return _decodeLooseJsonString(complete.group(1) ?? '');
  }

  final open = RegExp(
    r'"(?:reponse|response|message|text|texte|content)"\s*:\s*"(.*)',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(source);
  if (open == null) return '';
  var value = open.group(1) ?? '';
  value = value
      .replaceFirst(RegExp(r'"?\s*[,}]?\s*$'), '')
      .trim();
  return _decodeLooseJsonString(value);
}

String _decodeLooseJsonString(String value) {
  if (value.trim().isEmpty) return '';
  try {
    return jsonDecode('"$value"') as String;
  } catch (_) {
    return value
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '')
        .replaceAll(r'\t', ' ')
        .replaceAll(r'\"', '"')
        .trim();
  }
}

String _mainResponseText(dynamic value, {int depth = 0}) {
  if (value == null || depth > 3) return '';
  if (value is String) return value.trim();
  if (value is num || value is bool) return '$value';

  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    for (final key in const [
      'reponse',
      'response',
      'message',
      'text',
      'texte',
      'content',
      'result',
      'rapport',
      'report',
    ]) {
      if (!map.containsKey(key)) continue;
      final candidate = _mainResponseText(map[key], depth: depth + 1);
      if (candidate.isNotEmpty) return candidate;
    }
    return _clean(map);
  }

  if (value is List) {
    final parts = value
        .map((item) => _mainResponseText(item, depth: depth + 1))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return parts.join('\n\n');
  }

  return _clean(value);
}

List<OnlineToolChoice> _parseChoices(dynamic value) {
  final values = value is List
      ? value
      : value == null
          ? const []
          : [value];
  final seen = <String>{};
  final result = <OnlineToolChoice>[];
  for (final item in values) {
    final choice = OnlineToolChoice.fromDynamic(item);
    final key = choice.label.toLowerCase();
    if (choice.label.isEmpty || !seen.add(key)) continue;
    result.add(choice);
    if (result.length >= 6) break;
  }
  return List.unmodifiable(result);
}

String _findVideoUrl(Map<String, dynamic> map) {
  final direct = _firstNonEmpty([
    map['video_url'],
    map['videoUrl'],
    map['url_video'],
    map['file_url'],
    map['download_url'],
    map['url'],
  ]);
  if (_looksLikeVideoLocation(direct)) return direct;

  for (final value in map.values) {
    if (value is Map) {
      final nested = _findVideoUrl(Map<String, dynamic>.from(value));
      if (nested.isNotEmpty) return nested;
    }
    if (value is List) {
      for (final item in value) {
        if (item is Map) {
          final nested = _findVideoUrl(Map<String, dynamic>.from(item));
          if (nested.isNotEmpty) return nested;
        }
      }
    }
  }
  return '';
}

bool _looksLikeVideoLocation(String value) {
  if (value.isEmpty) return false;
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  if (uri.hasScheme) {
    return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }
  return value.startsWith('/') || value.toLowerCase().endsWith('.mp4');
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(_clean(value));
}

String _firstNonEmpty(Iterable<dynamic> values) {
  for (final value in values) {
    final clean = _clean(value);
    if (clean.isNotEmpty) return clean;
  }
  return '';
}

String _clean(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is num || value is bool) return '$value';
  try {
    return jsonEncode(value);
  } catch (_) {
    return '$value'.trim();
  }
}
