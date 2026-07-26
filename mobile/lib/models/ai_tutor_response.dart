import 'dart:convert';

import 'audio_language_mode.dart';

class TutorChoice {
  final String id;
  final String label;
  final String message;

  const TutorChoice({
    required this.id,
    required this.label,
    required this.message,
  });

  factory TutorChoice.fromDynamic(dynamic value, int index) {
    if (value is String) {
      final text = _cleanInline(value);
      return TutorChoice(id: 'choice_$index', label: text, message: text);
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final label = _cleanInline(
        map['label'] ?? map['text'] ?? map['title'] ?? map['value'],
      );
      final message = _cleanInline(
        map['message'] ?? map['prompt'] ?? map['value'] ?? label,
      );
      return TutorChoice(
        id: _cleanInline(map['id']).isEmpty
            ? 'choice_$index'
            : _cleanInline(map['id']),
        label: label.isEmpty ? message : label,
        message: message.isEmpty ? label : message,
      );
    }
    final text = _cleanInline(value);
    return TutorChoice(id: 'choice_$index', label: text, message: text);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'message': message,
      };
}

class LessonState {
  final String courseId;
  final String subject;
  final String topic;
  final String activity;
  final String stage;
  final int step;
  final int totalSteps;
  final bool awaitingAnswer;
  final bool completed;
  final int gameQuestion;
  final int gameTotal;
  final int gameCorrect;

  const LessonState({
    this.courseId = '',
    this.subject = '',
    this.topic = '',
    this.activity = '',
    this.stage = '',
    this.step = 0,
    this.totalSteps = 3,
    this.awaitingAnswer = false,
    this.completed = false,
    this.gameQuestion = 0,
    this.gameTotal = 2,
    this.gameCorrect = 0,
  });

  bool get isActive => courseId.trim().isNotEmpty && !completed;

  factory LessonState.fromDynamic(dynamic value) {
    final map = value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
    final status = _cleanInline(map['status']).toLowerCase();
    return LessonState(
      courseId: _cleanInline(
        map['course_id'] ?? map['courseId'] ?? map['id'],
      ),
      subject: _normalizeSubject(map['subject'] ?? map['matiere']),
      topic: _cleanInline(map['topic'] ?? map['title'] ?? map['lesson']),
      activity: _cleanInline(map['activity'] ?? map['mode'] ?? map['type']),
      stage: _cleanInline(map['stage'] ?? map['step_name'] ?? map['phase']),
      step: _asInt(map['step'] ?? map['step_index']).clamp(0, 3).toInt(),
      totalSteps: _asInt(
        map['total_steps'] ?? map['totalSteps'],
        fallback: 3,
      ).clamp(1, 3).toInt(),
      awaitingAnswer: _asBool(
        map['awaiting_answer'] ?? map['awaitingAnswer'],
      ),
      completed: _asBool(map['completed']) || status == 'completed',
      gameQuestion: _asInt(
        map['game_question'] ?? map['question_index'] ?? map['round'],
      ).clamp(0, 2).toInt(),
      gameTotal: _asInt(
        map['game_total'] ?? map['question_total'] ?? map['total_rounds'],
        fallback: 2,
      ).clamp(1, 2).toInt(),
      gameCorrect: _asInt(
        map['game_correct'] ?? map['correct_count'],
      ).clamp(0, 2).toInt(),
    );
  }

  LessonState copyWith({
    String? courseId,
    String? subject,
    String? topic,
    String? activity,
    String? stage,
    int? step,
    int? totalSteps,
    bool? awaitingAnswer,
    bool? completed,
    int? gameQuestion,
    int? gameTotal,
    int? gameCorrect,
  }) {
    return LessonState(
      courseId: courseId ?? this.courseId,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      activity: activity ?? this.activity,
      stage: stage ?? this.stage,
      step: step ?? this.step,
      totalSteps: totalSteps ?? this.totalSteps,
      awaitingAnswer: awaitingAnswer ?? this.awaitingAnswer,
      completed: completed ?? this.completed,
      gameQuestion: gameQuestion ?? this.gameQuestion,
      gameTotal: gameTotal ?? this.gameTotal,
      gameCorrect: gameCorrect ?? this.gameCorrect,
    );
  }

  Map<String, dynamic> toJson() => {
        'course_id': courseId,
        'subject': subject,
        'topic': topic,
        'activity': activity,
        'stage': stage,
        'step': step,
        'total_steps': totalSteps,
        'awaiting_answer': awaitingAnswer,
        'completed': completed,
        'game_question': gameQuestion,
        'game_total': gameTotal,
        'game_correct': gameCorrect,
      };
}

class ProgressUpdate {
  final bool save;
  final String skillId;
  final String skillLabel;
  final String evidence;
  final bool? correct;
  final int score;
  final int maxScore;
  final int understanding;
  final int xp;
  final bool lessonCompleted;

  const ProgressUpdate({
    this.save = false,
    this.skillId = '',
    this.skillLabel = '',
    this.evidence = '',
    this.correct,
    this.score = 0,
    this.maxScore = 0,
    this.understanding = 0,
    this.xp = 0,
    this.lessonCompleted = false,
  });

  bool get isValid {
    if (!save) return false;
    final hasMinimalEvaluation =
        skillLabel.trim().isNotEmpty && correct != null;
    final hasEvidence =
        skillLabel.trim().isNotEmpty && evidence.trim().isNotEmpty;
    final hasScore = maxScore > 0 && score >= 0 && score <= maxScore;
    return hasMinimalEvaluation || hasEvidence || hasScore;
  }

  factory ProgressUpdate.fromDynamic(dynamic value) {
    final map = value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};

    final rawSkills = map['skills'];
    Map<String, dynamic> firstSkill = const {};
    if (rawSkills is List && rawSkills.isNotEmpty && rawSkills.first is Map) {
      firstSkill = Map<String, dynamic>.from(rawSkills.first as Map);
    }

    final skillId = _cleanInline(
      map['skill_id'] ?? firstSkill['id'] ?? firstSkill['skill_id'],
    );
    final skillLabel = _cleanInline(
      map['skill_label'] ??
          map['skill'] ??
          firstSkill['label'] ??
          firstSkill['name'],
    );
    final correct = _asNullableBool(map['correct'] ?? firstSkill['correct']);
    final explicitSave = _asBool(
      map['save'] ??
          map['should_save'] ??
          map['record'] ??
          map['evaluated'] ??
          map['done'],
    );

    return ProgressUpdate(
      // Le modèle ne renvoie désormais que skill + correct quand une réponse
      // vient réellement d'être évaluée. Tous les autres calculs sont locaux.
      save: explicitSave ||
          (map.isNotEmpty && (skillLabel.isNotEmpty || correct != null)),
      skillId: skillId,
      skillLabel: skillLabel,
      evidence: normalizeTutorMarkdown(
        map['evidence'] ?? firstSkill['evidence'] ?? firstSkill['feedback'],
      ),
      correct: correct,
      score: _asInt(map['score']),
      maxScore: _asInt(
        map['max_score'] ?? map['maxScore'] ?? map['max'],
      ),
      understanding: _asInt(
        map['understanding'] ?? map['mastery'] ?? firstSkill['mastery'],
      ).clamp(0, 100).toInt(),
      xp: _asInt(map['xp'] ?? map['points']).clamp(0, 250).toInt(),
      lessonCompleted: _asBool(
        map['lesson_completed'] ??
            map['lessonCompleted'] ??
            map['completed'],
      ),
    );
  }

  ProgressUpdate copyWith({
    bool? save,
    String? skillId,
    String? skillLabel,
    String? evidence,
    bool? correct,
    bool clearCorrect = false,
    int? score,
    int? maxScore,
    int? understanding,
    int? xp,
    bool? lessonCompleted,
  }) {
    return ProgressUpdate(
      save: save ?? this.save,
      skillId: skillId ?? this.skillId,
      skillLabel: skillLabel ?? this.skillLabel,
      evidence: evidence ?? this.evidence,
      correct: clearCorrect ? null : (correct ?? this.correct),
      score: score ?? this.score,
      maxScore: maxScore ?? this.maxScore,
      understanding: understanding ?? this.understanding,
      xp: xp ?? this.xp,
      lessonCompleted: lessonCompleted ?? this.lessonCompleted,
    );
  }

  Map<String, dynamic> toJson() => {
        if (skillLabel.trim().isNotEmpty) 'skill': skillLabel.trim(),
        if (correct != null) 'correct': correct,
        if (lessonCompleted) 'completed': true,
      };
}

class AiTutorResponse {
  final String response;
  final List<TutorChoice> choices;
  final LessonState lesson;
  final ProgressUpdate progress;
  final String memorySummary;
  final String flow;
  final String action;
  final Map<String, dynamic> raw;
  final bool wasTruncated;

  const AiTutorResponse({
    required this.response,
    this.choices = const [],
    this.lesson = const LessonState(),
    this.progress = const ProgressUpdate(),
    this.memorySummary = '',
    this.flow = '',
    this.action = 'none',
    this.raw = const {},
    this.wasTruncated = false,
  });

  bool get awaitingAnswer => lesson.awaitingAnswer;
  bool get lessonCompleted => lesson.completed || progress.lessonCompleted;

  factory AiTutorResponse.local({
    required String response,
    List<TutorChoice> choices = const [],
    LessonState lesson = const LessonState(),
    String flow = '',
    String action = 'none',
  }) {
    return AiTutorResponse(
      response: normalizeTutorMarkdown(response),
      choices: choices,
      lesson: lesson,
      flow: flow,
      action: action,
    );
  }

  factory AiTutorResponse.fromJsonMap(
    Map<String, dynamic> map, {
    bool wasTruncated = false,
  }) {
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

    final memory = map['memory'];
    final memorySummary = memory is Map
        ? _cleanInline(memory['summary'])
        : _cleanInline(map['memory_summary'] ?? memory);

    final ui = map['ui'];
    final uiFlow = ui is Map ? _cleanInline(ui['flow']) : '';
    final action = _normalizeAction(
      map['action'] ?? map['next_action'] ?? map['state'],
    );

    final lessonSource = map['lesson'] is Map
        ? Map<String, dynamic>.from(map['lesson'] as Map)
        : <String, dynamic>{
            'subject': map['subject'] ?? map['matiere'],
            'topic': map['topic'] ?? map['sujet'],
          };

    return AiTutorResponse(
      response: normalizeTutorMarkdown(
        map['response'] ?? map['message'] ?? map['answer'] ?? map['text'],
      ),
      choices: choices.take(4).toList(growable: false),
      lesson: LessonState.fromDynamic(lessonSource),
      progress: ProgressUpdate.fromDynamic(
        map['progress'] ?? map['assessment'] ?? map['evaluation'],
      ),
      memorySummary: memorySummary,
      flow: _cleanInline(map['flow']).isEmpty
          ? uiFlow
          : _cleanInline(map['flow']),
      action: action,
      raw: Map<String, dynamic>.from(map),
      wasTruncated: wasTruncated,
    );
  }

  static AiTutorResponse parse(
    String rawText, {
    AudioLanguageMode languageMode = AudioLanguageMode.french,
  }) {
    final cleaned = rawText
        .trim()
        .replaceAll(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();

    if (cleaned.isEmpty) {
      final malagasy = languageMode.normalized.isMalagasy;
      return AiTutorResponse(
        response: malagasy
            ? 'Tsy tonga ny valiny. Andramo indray ity asa ity.'
            : 'La réponse n’est pas arrivée. Réessaie cette étape.',
        choices: [
          TutorChoice(
            id: 'retry_empty',
            label: malagasy ? 'Andramo indray' : 'Réessayer',
            message: malagasy
                ? 'Avereno fohy sy mazava ity asa ity.'
                : 'Reprends exactement la même étape, très brièvement.',
          ),
        ],
        wasTruncated: true,
      );
    }

    final candidate = _extractJsonObject(cleaned);
    if (candidate != null) {
      final decoded = _decodeLenient(candidate);
      final repairedOrIncomplete =
          decoded.$2 || !candidate.trimRight().endsWith('}');
      if (!repairedOrIncomplete && decoded.$1 is Map) {
        final parsed = AiTutorResponse.fromJsonMap(
          Map<String, dynamic>.from(decoded.$1 as Map),
        );
        if (parsed.response.isNotEmpty || parsed.choices.isNotEmpty) {
          return parsed;
        }
      }

      // Ne jamais afficher un texte réparé artificiellement : une chaîne JSON
      // refermée localement peut contenir une phrase réellement coupée.
      if (repairedOrIncomplete) {
        final malagasy = languageMode.normalized.isMalagasy;
        return AiTutorResponse(
          response: malagasy
              ? 'Tapaka ny valiny. Averintsika amin’ny fomba fohy sy mazava ity asa ity.'
              : 'La réponse a été interrompue. Reprenons cette étape proprement.',
          choices: [
            TutorChoice(
              id: 'retry_truncated',
              label: malagasy ? 'Avereno' : 'Reprendre',
              message: malagasy
                  ? 'Avereno ity asa ity amin’ny valiny fohy sy feno.'
                  : 'Reprends exactement cette étape avec une réponse courte et complète.',
            ),
          ],
          wasTruncated: true,
        );
      }
    }

    if (cleaned.startsWith('{') || cleaned.contains('"response"')) {
      // Une sortie JSON coupée ne doit jamais afficher une phrase inachevée.
      // Le service effectuera un essai compact unique; si celui-ci échoue,
      // cette réponse locale, complète, sera affichée.
      final malagasy = languageMode.normalized.isMalagasy;
      return AiTutorResponse(
        response: malagasy
            ? 'Tapaka ny valiny. Averintsika amin’ny fomba fohy sy mazava ity asa ity.'
            : 'La réponse a été interrompue. Reprenons cette étape proprement.',
        choices: [
          TutorChoice(
            id: 'retry_truncated',
            label: malagasy ? 'Avereno' : 'Reprendre',
            message: malagasy
                ? 'Avereno fohy ity asa ity.'
                : 'Reprends exactement cette étape avec une réponse courte.',
          ),
        ],
        wasTruncated: true,
      );
    }

    return AiTutorResponse(response: normalizeTutorMarkdown(cleaned));
  }

  AiTutorResponse normalized({
    required LessonState fallbackLesson,
    required bool lessonMode,
    AudioLanguageMode languageMode = AudioLanguageMode.french,
  }) {
    var completeText = normalizeTutorMarkdown(response);
    if (completeText.isEmpty) {
      completeText = languageMode.normalized.isMalagasy
          ? lessonMode
              ? 'Tohizantsika ity ampahan’ny lesona ity.'
              : 'Vonona hanampy anao aho.'
          : lessonMode
              ? 'Continuons cette étape de la leçon.'
              : 'Je suis prêt à t’aider.';
    }

    var normalizedLesson = lesson;
    if (lessonMode) {
      normalizedLesson = lesson.copyWith(
        courseId: lesson.courseId.isEmpty
            ? fallbackLesson.courseId
            : lesson.courseId,
        subject: lesson.subject.isEmpty
            ? fallbackLesson.subject
            : lesson.subject,
        topic: lesson.topic.isEmpty ? fallbackLesson.topic : lesson.topic,
        activity: lesson.activity.isEmpty
            ? fallbackLesson.activity
            : lesson.activity,
        stage: lesson.stage.isEmpty ? fallbackLesson.stage : lesson.stage,
        step: lesson.step <= 0 ? fallbackLesson.step : lesson.step,
        totalSteps: 3,
        completed: lesson.completed,
        gameQuestion: lesson.gameQuestion < fallbackLesson.gameQuestion
            ? fallbackLesson.gameQuestion
            : lesson.gameQuestion,
        gameTotal: lesson.gameTotal <= 0
            ? fallbackLesson.gameTotal
            : lesson.gameTotal,
        gameCorrect: lesson.gameCorrect < fallbackLesson.gameCorrect
            ? fallbackLesson.gameCorrect
            : lesson.gameCorrect,
      );
    }

    var normalizedChoices = choices
        .where((choice) => choice.label.trim().isNotEmpty)
        .take(4)
        .toList(growable: false);
    normalizedChoices = _localizeCommonChoices(
      normalizedChoices,
      languageMode,
    );

    // Gemma peut parfois écrire les options dans le Markdown au lieu du
    // tableau JSON `choices`. On les récupère pour éviter une étape bloquée.
    if (lessonMode &&
        normalizedChoices.isEmpty &&
        completeText.contains('?')) {
      normalizedChoices = _extractChoicesFromMarkdown(completeText);
    }

    final normalizedAction = _normalizeAction(action);
    final shouldWait = normalizedAction == 'wait_answer' ||
        (normalizedChoices.isNotEmpty && normalizedAction != 'finish') ||
        (lessonMode &&
            normalizedAction != 'finish' &&
            completeText.contains('?'));

    if (lessonMode) {
      normalizedLesson = normalizedLesson.copyWith(
        awaitingAnswer: shouldWait,
      );
    }

    // Ne jamais utiliser « J’ai compris » comme réponse générique dans un
    // exercice ou un jeu. Chaque étape reçoit des actions adaptées.
    if (lessonMode && shouldWait && normalizedChoices.isEmpty) {
      normalizedChoices = _fallbackChoicesForLesson(
        normalizedLesson,
        languageMode,
      );
    }

    return AiTutorResponse(
      response: completeText,
      choices: normalizedChoices,
      lesson: normalizedLesson,
      progress: progress,
      memorySummary: _cleanInline(memorySummary),
      flow: flow,
      action: normalizedAction,
      raw: raw,
      wasTruncated: wasTruncated,
    );
  }

  AiTutorResponse copyWith({
    String? response,
    List<TutorChoice>? choices,
    LessonState? lesson,
    ProgressUpdate? progress,
    String? memorySummary,
    String? flow,
    String? action,
    Map<String, dynamic>? raw,
    bool? wasTruncated,
  }) {
    return AiTutorResponse(
      response: response ?? this.response,
      choices: choices ?? this.choices,
      lesson: lesson ?? this.lesson,
      progress: progress ?? this.progress,
      memorySummary: memorySummary ?? this.memorySummary,
      flow: flow ?? this.flow,
      action: action ?? this.action,
      raw: raw ?? this.raw,
      wasTruncated: wasTruncated ?? this.wasTruncated,
    );
  }

  Map<String, dynamic> toJson() => {
        'response': response,
        'choices': choices.map((choice) => choice.toJson()).toList(),
        'action': action,
        if (lesson.subject.isNotEmpty) 'subject': lesson.subject,
        if (lesson.topic.isNotEmpty) 'topic': lesson.topic,
        'lesson': lesson.toJson(),
        if (progress.isValid) 'evaluation': progress.toJson(),
        if (flow.isNotEmpty) 'flow': flow,
      };

  String toCompactJson() => jsonEncode(toJson());
}


List<TutorChoice> _extractChoicesFromMarkdown(String text) {
  final matches = RegExp(
    r'^\s*(?:[-•]\s+|(?:[A-Da-d]|[1-4])[\)\.\-:]\s+)(.+?)\s*$',
    multiLine: true,
  ).allMatches(text);

  final seen = <String>{};
  final result = <TutorChoice>[];
  for (final match in matches) {
    final label = _cleanInline(match.group(1));
    if (label.length < 1 || label.length > 70) continue;
    final key = label.toLowerCase();
    if (!seen.add(key)) continue;
    result.add(
      TutorChoice(
        id: 'choice_${result.length}',
        label: label,
        message: label,
      ),
    );
    if (result.length == 4) break;
  }
  return result;
}

List<TutorChoice> _fallbackChoicesForLesson(
  LessonState lesson,
  AudioLanguageMode languageMode,
) {
  final malagasy = languageMode.normalized.isMalagasy;
  if (lesson.step <= 1) {
    return [
      TutorChoice(
        id: 'continue_to_exercise',
        label: malagasy ? 'Hanomboka fanazaran-tena' : 'Passer à l’exercice',
        message: malagasy
            ? 'Atombohy izao ny fanazaran-tena misy tari-dalana.'
            : 'Commence maintenant l’étape 2 avec un exercice guidé.',
      ),
      TutorChoice(
        id: 'example',
        label: malagasy ? 'Ohatra hafa' : 'Un autre exemple',
        message: malagasy
            ? 'Hazavao indray amin’ny ohatra iray tena tsotra.'
            : 'Explique encore avec un autre exemple très simple.',
      ),
      TutorChoice(
        id: 'dont_know',
        label: malagasy ? 'Tsy haiko' : 'Je ne sais pas',
        message: malagasy
            ? 'Hazavao moramora indray ity hevitra ity.'
            : 'Reprends doucement cette notion étape par étape.',
      ),
    ];
  }

  if (lesson.step == 2) {
    return [
      TutorChoice(
        id: 'exercise_hint',
        label: malagasy ? '💡 Soso-kevitra' : '💡 Un indice',
        message: malagasy
            ? 'Omeo soso-kevitra fohy ary avereno ilay fanazaran-tena sy ny safidy.'
            : 'Donne un indice court puis répète le même exercice avec ses choix.',
      ),
      TutorChoice(
        id: 'exercise_retry',
        label: malagasy ? 'Fanazaran-tena hafa' : 'Nouvel exercice',
        message: malagasy
            ? 'Omeo fanazaran-tena hafa mora kokoa miaraka amin’ny safidy.'
            : 'Propose un autre exercice plus simple avec des choix.',
      ),
    ];
  }

  final activity = lesson.activity.toLowerCase();
  if (activity == 'true_false' ||
      activity == 'truefalse' ||
      activity == 'vrai_faux') {
    return [
      TutorChoice(
        id: 'game_true',
        label: malagasy ? '✅ Marina' : '✅ Vrai',
        message: malagasy ? 'Marina' : 'Vrai',
      ),
      TutorChoice(
        id: 'game_false',
        label: malagasy ? '❌ Diso' : '❌ Faux',
        message: malagasy ? 'Diso' : 'Faux',
      ),
    ];
  }

  return [
    TutorChoice(
      id: 'game_hint',
      label: malagasy ? '💡 Soso-kevitra' : '💡 Indice',
      message: malagasy
          ? 'Omeo soso-kevitra fohy ary avereno ilay fanontaniana sy ny safidy.'
          : 'Donne un indice court et répète la même question avec ses choix.',
    ),
    TutorChoice(
      id: 'game_skip',
      label: malagasy ? '⏭️ Mandalo' : '⏭️ Passer',
      message: malagasy
          ? 'Handalo ity fanontaniana ity aho.'
          : 'Je passe cette question.',
    ),
  ];
}

List<TutorChoice> _localizeCommonChoices(
  List<TutorChoice> choices,
  AudioLanguageMode languageMode,
) {
  if (!languageMode.normalized.isMalagasy) return choices;

  String localize(String value) {
    final clean = value.trim();
    final key = clean
        .toLowerCase()
        .replaceAll('✅', '')
        .replaceAll('❌', '')
        .replaceAll('💡', '')
        .replaceAll('⏭️', '')
        .trim();
    if (key == 'vrai' || key == 'true') return clean.contains('✅') ? '✅ Marina' : 'Marina';
    if (key == 'faux' || key == 'false') return clean.contains('❌') ? '❌ Diso' : 'Diso';
    if (key == 'réessayer' || key == 'reessayer') return 'Andramo indray';
    if (key == 'reprendre') return 'Avereno';
    if (key == 'indice' || key == 'un indice') return '💡 Soso-kevitra';
    if (key == 'passer') return '⏭️ Mandalo';
    return clean;
  }

  return choices
      .map(
        (choice) => TutorChoice(
          id: choice.id,
          label: localize(choice.label),
          message: localize(choice.message),
        ),
      )
      .toList(growable: false);
}


String normalizeTutorMarkdown(dynamic value) {
  var text = value == null ? '' : '$value';
  text = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '  ')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  while (text.endsWith('\\')) {
    text = text.substring(0, text.length - 1).trimRight();
  }

  text = _removeDanglingMarker(text, '**');
  text = _removeDanglingMarker(text, '__');
  text = _removeDanglingMarker(text, '`');

  return text;
}

String _removeDanglingMarker(String text, String marker) {
  if (marker.isEmpty) return text;
  var count = 0;
  var index = 0;
  while (true) {
    index = text.indexOf(marker, index);
    if (index < 0) break;
    count++;
    index += marker.length;
  }
  if (count.isEven) return text;
  final last = text.lastIndexOf(marker);
  return last < 0
      ? text
      : '${text.substring(0, last)}${text.substring(last + marker.length)}';
}

String? _extractJsonObject(String text) {
  final start = text.indexOf('{');
  if (start < 0) return null;
  final end = text.lastIndexOf('}');
  if (end > start) return text.substring(start, end + 1);
  return text.substring(start);
}

(dynamic, bool) _decodeLenient(String candidate) {
  try {
    return (jsonDecode(candidate), false);
  } catch (_) {
    var repaired = candidate.trimRight();
    if (_isInsideString(repaired)) repaired += '"';
    final balance = _jsonBalance(repaired);
    repaired += List<String>.filled(balance.$2, ']').join();
    repaired += List<String>.filled(balance.$1, '}').join();
    try {
      return (jsonDecode(repaired), true);
    } catch (_) {
      return (null, true);
    }
  }
}

(int, int) _jsonBalance(String text) {
  var braces = 0;
  var brackets = 0;
  var inString = false;
  var escaped = false;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == '\\' && inString) {
      escaped = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (char == '{') braces++;
    if (char == '}') braces--;
    if (char == '[') brackets++;
    if (char == ']') brackets--;
  }
  return (
    braces.clamp(0, 20).toInt(),
    brackets.clamp(0, 20).toInt(),
  );
}

bool _isInsideString(String text) {
  var inString = false;
  var escaped = false;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == '\\' && inString) {
      escaped = true;
      continue;
    }
    if (char == '"') inString = !inString;
  }
  return inString;
}

String _extractJsonStringField(String text, String field) {
  final marker = '"$field"';
  final index = text.indexOf(marker);
  if (index < 0) return '';
  final colon = text.indexOf(':', index + marker.length);
  if (colon < 0) return '';
  final quote = text.indexOf('"', colon + 1);
  if (quote < 0) return '';

  final buffer = StringBuffer();
  var escaped = false;
  for (var i = quote + 1; i < text.length; i++) {
    final char = text[i];
    if (escaped) {
      switch (char) {
        case 'n':
          buffer.write('\n');
          break;
        case 't':
          buffer.write('  ');
          break;
        case 'r':
          break;
        default:
          buffer.write(char);
      }
      escaped = false;
      continue;
    }
    if (char == '\\') {
      escaped = true;
      continue;
    }
    if (char == '"') break;
    buffer.write(char);
  }
  return buffer.toString().trim();
}

String _cleanInline(dynamic value) {
  if (value == null) return '';
  return '$value'
      .replaceAll(r'\n', ' ')
      .replaceAll(r'\t', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _normalizeAction(dynamic value) {
  final text = _cleanInline(value).toLowerCase().replaceAll('-', '_');
  switch (text) {
    case 'wait':
    case 'question':
    case 'await_answer':
    case 'wait_answer':
      return 'wait_answer';
    case 'next':
    case 'continue':
    case 'next_step':
      return 'next_step';
    case 'complete':
    case 'completed':
    case 'finish':
      return 'finish';
    default:
      return 'none';
  }
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(_cleanInline(value)) ?? fallback;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final text = _cleanInline(value).toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'oui';
}

String _normalizeSubject(dynamic value) {
  final raw = _cleanInline(value);
  final lower = raw.toLowerCase();
  if (lower.contains('math')) return 'Mathématiques';
  if (lower.contains('fran')) return 'Français';
  if (lower.contains('angl') || lower.contains('english')) return 'Anglais';
  if (lower.contains('science') ||
      lower.contains('physique') ||
      lower.contains('chimie') ||
      lower.contains('svt')) {
    return 'Sciences';
  }
  return raw;
}

bool? _asNullableBool(dynamic value) {
  if (value == null) return null;
  return _asBool(value);
}
