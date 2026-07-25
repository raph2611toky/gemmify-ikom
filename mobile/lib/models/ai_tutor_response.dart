import 'dart:convert';

enum TutorCardType {
  none,
  understanding,
  activityResult,
  progression,
}

class TutorChoice {
  final String id;
  final String label;
  final String message;
  final String style;

  const TutorChoice({
    required this.id,
    required this.label,
    required this.message,
    this.style = 'chip',
  });

  factory TutorChoice.fromDynamic(dynamic value, int index) {
    if (value is String) {
      return TutorChoice(
        id: 'choice_$index',
        label: value,
        message: value,
      );
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final label = _stringValue(
        map['label'] ?? map['text'] ?? map['title'] ?? map['value'],
      );
      final message = _stringValue(
        map['message'] ?? map['prompt'] ?? map['value'] ?? label,
      );
      return TutorChoice(
        id: _stringValue(map['id']).isEmpty
            ? 'choice_$index'
            : _stringValue(map['id']),
        label: label.isEmpty ? message : label,
        message: message.isEmpty ? label : message,
        style: _stringValue(map['style']).isEmpty
            ? 'chip'
            : _stringValue(map['style']),
      );
    }

    return TutorChoice(
      id: 'choice_$index',
      label: '$value',
      message: '$value',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'message': message,
        'style': style,
      };
}

class TutorSkill {
  final String id;
  final String label;
  final int mastery;
  final String status;
  final String evidence;

  const TutorSkill({
    required this.id,
    required this.label,
    required this.mastery,
    required this.status,
    this.evidence = '',
  });

  factory TutorSkill.fromDynamic(dynamic value, int index) {
    if (value is String) {
      return TutorSkill(
        id: 'skill_$index',
        label: value,
        mastery: 0,
        status: 'discover',
      );
    }

    final map = value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
    final label = _stringValue(
      map['label'] ?? map['name'] ?? map['skill'] ?? map['skill_label'],
    );
    return TutorSkill(
      id: _stringValue(map['id'] ?? map['skill_id']).isEmpty
          ? 'skill_$index'
          : _stringValue(map['id'] ?? map['skill_id']),
      label: label.isEmpty ? 'Compétence ${index + 1}' : label,
      mastery: _intValue(map['mastery'] ?? map['understanding']).clamp(0, 100).toInt(),
      status: _normalizeStatus(_stringValue(map['status'])),
      evidence: _stringValue(map['evidence'] ?? map['feedback']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'mastery': mastery,
        'status': status,
        if (evidence.isNotEmpty) 'evidence': evidence,
      };
}

class AiTutorResponse {
  final String response;
  final List<TutorChoice> choices;
  final TutorCardType cardType;
  final Map<String, dynamic> ui;
  final Map<String, dynamic> lesson;
  final Map<String, dynamic> assessment;
  final Map<String, dynamic> memory;
  final Map<String, dynamic> raw;

  const AiTutorResponse({
    required this.response,
    this.choices = const [],
    this.cardType = TutorCardType.none,
    this.ui = const {},
    this.lesson = const {},
    this.assessment = const {},
    this.memory = const {},
    this.raw = const {},
  });

  factory AiTutorResponse.fallback(String text) {
    return AiTutorResponse(response: text.trim());
  }

  factory AiTutorResponse.fromJsonMap(Map<String, dynamic> map) {
    final rawChoices = map['choices'] ?? map['choice'] ?? const [];
    final choices = <TutorChoice>[];
    if (rawChoices is List) {
      for (var i = 0; i < rawChoices.length; i++) {
        final choice = TutorChoice.fromDynamic(rawChoices[i], i);
        if (choice.label.trim().isNotEmpty) choices.add(choice);
      }
    } else if (rawChoices != null) {
      final choice = TutorChoice.fromDynamic(rawChoices, 0);
      if (choice.label.trim().isNotEmpty) choices.add(choice);
    }

    final ui = _mapValue(map['ui']);
    final lesson = _mapValue(map['lesson']);
    final assessment = _mapValue(map['assessment'] ?? map['evaluation']);
    final memory = _mapValue(map['memory'] ?? map['conversation']);

    final cardName = _stringValue(
      ui['card'] ?? map['card'] ?? map['card_type'],
    ).toLowerCase();

    return AiTutorResponse(
      response: _stringValue(
        map['response'] ?? map['message'] ?? map['answer'] ?? map['text'],
      ),
      choices: choices,
      cardType: switch (cardName) {
        'understanding' || 'comprehension' => TutorCardType.understanding,
        'activity_result' || 'result' || 'activity' =>
          TutorCardType.activityResult,
        'progression' || 'progress' => TutorCardType.progression,
        _ => TutorCardType.none,
      },
      ui: ui,
      lesson: lesson,
      assessment: assessment,
      memory: memory,
      raw: Map<String, dynamic>.from(map),
    );
  }

  static AiTutorResponse parse(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return const AiTutorResponse(
        response: 'Je suis prêt à continuer avec toi.',
      );
    }

    final cleaned = trimmed
        .replaceAll(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();

    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    final candidate = firstBrace >= 0 && lastBrace > firstBrace
        ? cleaned.substring(firstBrace, lastBrace + 1)
        : cleaned;

    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map) {
        final result = AiTutorResponse.fromJsonMap(
          Map<String, dynamic>.from(decoded),
        );
        if (result.response.isNotEmpty ||
            result.choices.isNotEmpty ||
            result.cardType != TutorCardType.none) {
          return result;
        }
      }
    } catch (_) {
      // Réponse de secours ci-dessous.
    }

    return AiTutorResponse.fallback(trimmed);
  }

  String get courseId => _stringValue(
        lesson['course_id'] ?? lesson['courseId'] ?? lesson['id'],
      );

  String get subject => _stringValue(lesson['subject']);

  String get topic => _stringValue(lesson['topic'] ?? lesson['title']);

  String get lessonStatus => _stringValue(lesson['status']);

  bool get lessonCompleted =>
      lessonStatus == 'completed' ||
      lessonStatus == 'finished' ||
      _boolValue(lesson['completed']);

  int? get score => _nullableInt(assessment['score']);

  int? get maxScore =>
      _nullableInt(assessment['max_score'] ?? assessment['maxScore']);

  int get xp => _intValue(assessment['xp']);

  int get understanding =>
      _intValue(assessment['understanding'] ?? assessment['mastery'])
          .clamp(0, 100).toInt();

  String get title => _stringValue(memory['title']);

  String get summary => _stringValue(memory['summary']);

  String get levelLabel => _stringValue(
        assessment['level_label'] ?? assessment['levelLabel'],
      );

  int get currentXp => _intValue(
        assessment['current_xp'] ?? assessment['currentXp'],
      );

  int get nextLevelXp => _intValue(
        assessment['next_level_xp'] ?? assessment['nextLevelXp'],
      );

  int get streakDays => _intValue(
        assessment['streak_days'] ?? assessment['streakDays'],
      );

  String get learningTime => _stringValue(
        assessment['learning_time'] ?? assessment['learningTime'],
      );

  List<TutorSkill> get skills {
    final rawSkills = assessment['skills'] ?? lesson['skills'] ?? const [];
    if (rawSkills is! List) return const [];
    return List<TutorSkill>.generate(
      rawSkills.length,
      (index) => TutorSkill.fromDynamic(rawSkills[index], index),
      growable: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'response': response,
        'choices': choices.map((choice) => choice.toJson()).toList(),
        'ui': {
          ...ui,
          'card': switch (cardType) {
            TutorCardType.none => 'none',
            TutorCardType.understanding => 'understanding',
            TutorCardType.activityResult => 'activity_result',
            TutorCardType.progression => 'progression',
          },
        },
        'lesson': lesson,
        'assessment': assessment,
        'memory': memory,
      };

  String toJsonString() => jsonEncode(toJson());
}

Map<String, dynamic> _mapValue(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String _stringValue(dynamic value) {
  if (value == null) return '';
  return '$value'.trim();
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(_stringValue(value)) ?? 0;
}

int? _nullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(_stringValue(value));
}

bool _boolValue(dynamic value) {
  if (value is bool) return value;
  return const {'true', '1', 'yes', 'oui'}.contains(
    _stringValue(value).toLowerCase(),
  );
}

String _normalizeStatus(String status) {
  switch (status.toLowerCase()) {
    case 'mastered':
    case 'maitrise':
    case 'maîtrisé':
    case 'maîtrisee':
    case 'maîtrisée':
      return 'mastered';
    case 'in_progress':
    case 'en cours':
    case 'progressing':
      return 'in_progress';
    case 'reinforce':
    case 'a renforcer':
    case 'à renforcer':
      return 'reinforce';
    default:
      return 'discover';
  }
}
