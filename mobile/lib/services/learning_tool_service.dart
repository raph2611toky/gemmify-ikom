import 'package:flutter_gemma/flutter_gemma.dart';

import 'local_learning_database.dart';

class LearningToolService {
  LearningToolService._();

  static final LearningToolService instance = LearningToolService._();

  static const List<Tool> tools = [
    Tool(
      name: 'save_learning_progress',
      description:
          'Enregistre une preuve réelle de progression de l’élève. Appelle cet '
          'outil après avoir évalué une réponse, observé une compétence ou '
          'terminé une leçon. Ne l’appelle pas sans preuve dans la discussion.',
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
              'required': ['id', 'label', 'mastery', 'status'],
            },
          },
        },
        'required': ['event_type', 'subject', 'topic', 'skills'],
      },
    ),
    Tool(
      name: 'get_learning_progress',
      description:
          'Lit la progression locale enregistrée afin d’adapter le prochain '
          'cours, afficher la progression ou éviter de répéter ce qui est déjà '
          'maîtrisé.',
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
        final result = await LocalLearningDatabase.instance.applyProgressFunction(
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

String _asString(dynamic value) => value == null ? '' : '$value'.trim();
