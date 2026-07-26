import 'package:flutter_gemma/flutter_gemma.dart';

import 'local_learning_database.dart';

class LearningToolService {
  LearningToolService._();

  static final LearningToolService instance = LearningToolService._();

  static const List<Tool> tools = [
    Tool(
      name: 'save_learning_progress',
      description:
          'Enregistre une preuve réelle de progression de l’élève. Utilise cet '
          'outil uniquement quand progress_tools_allowed=true et après une '
          'réponse réellement évaluée. Ne jamais l’appeler pendant le choix ou '
          'le démarrage d’une leçon.',
      parameters: {
        'type': 'object',
        'properties': {
          'event_type': {
            'type': 'string',
            'enum': [
              'answer_evaluated',
              'skill_progress',
              'lesson_completed',
            ],
          },
          'course_id': {'type': 'string'},
          'subject': {'type': 'string'},
          'topic': {'type': 'string'},
          'score': {'type': 'integer'},
          'max_score': {'type': 'integer'},
          'understanding': {
            'type': 'integer',
            'description': 'Compréhension globale de 0 à 100.',
          },
          'xp': {'type': 'integer'},
          'summary': {
            'type': 'string',
            'description': 'Résumé très court de la preuve observée.',
          },
          'skills': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
                'label': {'type': 'string'},
                'mastery': {'type': 'integer'},
                'status': {
                  'type': 'string',
                  'enum': [
                    'mastered',
                    'in_progress',
                    'discover',
                    'reinforce',
                  ],
                },
                'correct': {'type': 'boolean'},
                'xp': {'type': 'integer'},
                'evidence': {'type': 'string'},
              },
              'required': ['id', 'label', 'mastery', 'status', 'evidence'],
            },
          },
        },
        'required': [
          'event_type',
          'course_id',
          'subject',
          'topic',
          'skills',
        ],
      },
    ),
    Tool(
      name: 'get_learning_progress',
      description:
          'Lit la progression locale enregistrée afin d’adapter le prochain '
          'cours ou afficher les compétences déjà acquises.',
      parameters: {
        'type': 'object',
        'properties': {
          'subject': {'type': 'string'},
          'topic': {'type': 'string'},
        },
      },
    ),
  ];

  Future<Map<String, dynamic>> execute({
    required int conversationId,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    switch (name) {
      case 'save_learning_progress':
        final validation = _validateProgressArguments(arguments);
        if (validation != null) {
          return {
            'status': 'rejected',
            'code': validation.code,
            'message': validation.message,
            'instruction':
                'N’enregistre rien. Renvoie maintenant la réponse JSON pédagogique visible et poursuis la leçon normalement.',
          };
        }

        final result =
            await LocalLearningDatabase.instance.applyProgressFunction(
          conversationId: conversationId,
          arguments: arguments,
        );
        return {
          'status': 'saved',
          'conversation_id': conversationId,
          'progress': result,
        };

      case 'get_learning_progress':
        final subject = _asString(arguments['subject']);
        final topic = _asString(arguments['topic']);
        final result = await LocalLearningDatabase.instance.getProgressContext(
          subject: subject.isEmpty ? null : subject,
          topic: topic.isEmpty ? null : topic,
        );
        return {
          'status': 'ok',
          'progress': result,
        };

      default:
        return {
          'status': 'error',
          'message': 'Outil inconnu: $name',
        };
    }
  }
}

_ProgressValidationError? _validateProgressArguments(
  Map<String, dynamic> arguments,
) {
  final eventType = _asString(
    arguments['event_type'] ?? arguments['eventType'],
  ).toLowerCase();
  const allowedEvents = {
    'answer_evaluated',
    'skill_progress',
    'lesson_completed',
  };
  if (!allowedEvents.contains(eventType)) {
    return const _ProgressValidationError(
      'INVALID_EVENT_TYPE',
      'Le type d’événement de progression est invalide.',
    );
  }

  final courseId = _asString(
    arguments['course_id'] ?? arguments['courseId'],
  ).toLowerCase();
  if (courseId.isEmpty ||
      courseId == 'none' ||
      courseId == 'null' ||
      courseId == 'undefined') {
    return const _ProgressValidationError(
      'INVALID_COURSE_ID',
      'Aucun cours réel n’est actif. course_id ne peut pas être vide ou « none ».',
    );
  }

  final subject = _asString(arguments['subject']);
  final topic = _asString(arguments['topic']);
  if (subject.isEmpty || topic.isEmpty) {
    return const _ProgressValidationError(
      'MISSING_LESSON_IDENTITY',
      'La matière et le thème doivent être connus avant tout enregistrement.',
    );
  }

  final rawSkills = arguments['skills'];
  if (rawSkills is! List || rawSkills.isEmpty) {
    return const _ProgressValidationError(
      'MISSING_SKILLS',
      'Aucune compétence évaluée n’a été fournie.',
    );
  }

  var hasEvidence = false;
  for (final raw in rawSkills) {
    if (raw is! Map) continue;
    final skill = Map<String, dynamic>.from(raw);
    final id = _asString(skill['id'] ?? skill['skill_id']);
    final label = _asString(skill['label'] ?? skill['name']);
    final evidence = _asString(skill['evidence'] ?? skill['feedback']);
    if ((id.isNotEmpty || label.isNotEmpty) && evidence.isNotEmpty) {
      hasEvidence = true;
      break;
    }
  }

  final score = _asNullableInt(arguments['score']);
  final maxScore = _asNullableInt(
    arguments['max_score'] ?? arguments['maxScore'],
  );
  final hasValidScore = score != null &&
      maxScore != null &&
      maxScore > 0 &&
      score >= 0 &&
      score <= maxScore;

  if (!hasEvidence && !hasValidScore) {
    return const _ProgressValidationError(
      'MISSING_EVIDENCE',
      'Une note valide ou une preuve textuelle de compétence est nécessaire.',
    );
  }

  if (eventType == 'lesson_completed' && (!hasValidScore || !hasEvidence)) {
    return const _ProgressValidationError(
      'LESSON_NOT_COMPLETABLE',
      'Une leçon ne peut être terminée sans note, barème et preuve de compétence.',
    );
  }

  return null;
}

class _ProgressValidationError {
  final String code;
  final String message;

  const _ProgressValidationError(this.code, this.message);
}

String _asString(dynamic value) => value == null ? '' : '$value'.trim();

int? _asNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(_asString(value));
}
