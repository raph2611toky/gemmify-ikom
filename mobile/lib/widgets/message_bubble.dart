import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/ai_tutor_response.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final ValueChanged<TutorChoice>? onChoiceSelected;
  final VoidCallback? onSpeak;

  const MessageBubble({
    super.key,
    required this.message,
    this.onChoiceSelected,
    this.onSpeak,
  });

  String get _timeLabel {
    final hour = message.createdAt.hour.toString().padLeft(2, '0');
    final minute = message.createdAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _userBubble(context) : _assistantBubble(context);
  }

  Widget _userBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.79,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 7),
          padding: const EdgeInsets.fromLTRB(17, 13, 13, 9),
          decoration: BoxDecoration(
            color: const Color(0xFFF0E9FF),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(23),
              topRight: Radius.circular(23),
              bottomLeft: Radius.circular(23),
              bottomRight: Radius.circular(8),
            ),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (message.imageBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    message.imageBytes!,
                    height: 180,
                    width: 230,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 9),
              ],
              if (message.hasAudio)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.graphic_eq_rounded, color: AppTheme.accent),
                    SizedBox(width: 8),
                    Text('Message vocal'),
                  ],
                ),
              if (message.text.trim().isNotEmpty)
                Text(
                  message.text,
                  style: const TextStyle(
                    fontSize: 15.5,
                    height: 1.38,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeLabel,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.done_all_rounded,
                    size: 15,
                    color: AppTheme.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assistantBubble(BuildContext context) {
    final response = message.tutorResponse;
    final lesson = response?.lesson;
    final text = response?.response.trim().isNotEmpty == true
        ? response!.response
        : message.text;
    final isGameMenu = response?.flow == 'game_menu';
    final feedback = response?.progress.correct;
    final accent = feedback == true
        ? AppTheme.success
        : feedback == false
            ? AppTheme.error
            : AppTheme.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MascotAvatar(),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: AppTheme.softShadow,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 4, color: accent),
                        Expanded(
                          child: Padding(
                          padding: const EdgeInsets.fromLTRB(17, 16, 14, 11),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (lesson?.isActive == true ||
                                  lesson?.completed == true) ...[
                                _LessonHeader(lesson: lesson!),
                                const SizedBox(height: 13),
                              ] else if (lesson != null &&
                                  (lesson.subject.trim().isNotEmpty ||
                                      lesson.topic.trim().isNotEmpty)) ...[
                                _SubjectTopicBadge(lesson: lesson),
                                const SizedBox(height: 11),
                              ],
                              if (feedback != null) ...[
                                _FeedbackTitle(correct: feedback),
                                const SizedBox(height: 9),
                              ],
                              if (message.status == MessageStatus.streaming &&
                                  text.trim().isEmpty)
                                const _ThinkingLine()
                              else if (message.status == MessageStatus.error)
                                Text(
                                  text,
                                  style: const TextStyle(
                                    color: AppTheme.error,
                                    fontSize: 14,
                                    height: 1.42,
                                  ),
                                )
                              else
                                MarkdownBody(
                                  data: text,
                                  selectable: true,
                                  styleSheet: _markdownStyle(),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    _timeLabel,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (onSpeak != null &&
                                      message.status == MessageStatus.done &&
                                      text.trim().isNotEmpty)
                                    InkWell(
                                      onTap: onSpeak,
                                      borderRadius: BorderRadius.circular(20),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.volume_up_outlined,
                                          size: 19,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (response != null && response.choices.isNotEmpty) ...[
                  const SizedBox(height: 11),
                  if (isGameMenu)
                    _GameChoiceArea(
                      choices: response.choices,
                      enabled: message.choicesEnabled &&
                          message.status == MessageStatus.done,
                      selectedChoiceId: message.selectedChoiceId,
                      onSelected: onChoiceSelected,
                    )
                  else
                    _ChoiceArea(
                      choices: response.choices,
                      enabled: message.choicesEnabled &&
                          message.status == MessageStatus.done,
                      selectedChoiceId: message.selectedChoiceId,
                      onSelected: onChoiceSelected,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle() {
    return MarkdownStyleSheet(
      p: const TextStyle(
        fontSize: 15.2,
        height: 1.5,
        color: AppTheme.textPrimary,
      ),
      h1: const TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w800,
        color: AppTheme.textPrimary,
      ),
      h2: const TextStyle(
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w800,
        color: AppTheme.accent,
      ),
      h3: const TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w800,
        color: AppTheme.textPrimary,
      ),
      strong: const TextStyle(
        fontWeight: FontWeight.w800,
        color: AppTheme.textPrimary,
      ),
      em: const TextStyle(
        fontStyle: FontStyle.italic,
        color: AppTheme.textSecondary,
      ),
      listBullet: const TextStyle(
        fontSize: 15,
        color: AppTheme.accent,
      ),
      blockquote: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 14.5,
        height: 1.45,
      ),
      code: const TextStyle(
        color: AppTheme.accent,
        backgroundColor: AppTheme.softLavender,
        fontSize: 14,
      ),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.border),
        ),
      ),
    );
  }
}

class _LessonHeader extends StatelessWidget {
  final LessonState lesson;

  const _LessonHeader({required this.lesson});

  @override
  Widget build(BuildContext context) {
    final baseStage = lesson.stage.trim().isEmpty
        ? 'Leçon guidée'
        : lesson.stage;
    final stage = lesson.step == 3 && lesson.gameQuestion > 0
        ? '$baseStage · Question ${lesson.gameQuestion}/${lesson.gameTotal}'
        : baseStage;
    final topic = lesson.topic.trim();
    final subject = lesson.subject.trim();
    final title = topic.isEmpty
        ? subject
        : subject.isEmpty || subject.toLowerCase() == topic.toLowerCase()
            ? topic
            : '$subject — $topic';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.softLavender,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: AppTheme.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.accent,
                  ),
                ),
                if (title.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (lesson.completed)
            const Icon(Icons.check_circle_rounded, color: AppTheme.success),
        ],
      ),
    );
  }
}

class _SubjectTopicBadge extends StatelessWidget {
  final LessonState lesson;

  const _SubjectTopicBadge({required this.lesson});

  @override
  Widget build(BuildContext context) {
    final subject = lesson.subject.trim();
    final topic = lesson.topic.trim();
    final label = subject.isNotEmpty && topic.isNotEmpty
        ? '$subject · $topic'
        : subject.isNotEmpty
            ? subject
            : topic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.softLavender,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.accent,
        ),
      ),
    );
  }
}

class _FeedbackTitle extends StatelessWidget {
  final bool correct;

  const _FeedbackTitle({required this.correct});

  @override
  Widget build(BuildContext context) {
    final color = correct ? AppTheme.success : AppTheme.error;
    return Row(
      children: [
        Icon(
          correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: color,
          size: 27,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            correct ? 'Ce que tu as bien fait' : 'L’erreur que j’ai trouvée',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChoiceArea extends StatelessWidget {
  final List<TutorChoice> choices;
  final bool enabled;
  final String? selectedChoiceId;
  final ValueChanged<TutorChoice>? onSelected;

  const _ChoiceArea({
    required this.choices,
    required this.enabled,
    required this.selectedChoiceId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final useFullWidth = choices.length <= 3 &&
        choices.any((choice) => choice.label.length > 20);

    if (useFullWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: choices
            .map(
              (choice) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ChoiceButton(
                  choice: choice,
                  enabled: enabled,
                  selected: selectedChoiceId == choice.id,
                  fullWidth: true,
                  onTap: () => onSelected?.call(choice),
                ),
              ),
            )
            .toList(growable: false),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = choices.length == 4 && constraints.maxWidth >= 300;
        if (!twoColumns) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices
                .map(
                  (choice) => _ChoiceButton(
                    choice: choice,
                    enabled: enabled,
                    selected: selectedChoiceId == choice.id,
                    onTap: () => onSelected?.call(choice),
                  ),
                )
                .toList(growable: false),
          );
        }

        final width = (constraints.maxWidth - 9) / 2;
        return Wrap(
          spacing: 9,
          runSpacing: 9,
          children: choices
              .map(
                (choice) => SizedBox(
                  width: width,
                  child: _ChoiceButton(
                    choice: choice,
                    enabled: enabled,
                    selected: selectedChoiceId == choice.id,
                    fullWidth: true,
                    onTap: () => onSelected?.call(choice),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final TutorChoice choice;
  final bool enabled;
  final bool selected;
  final bool fullWidth;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.choice,
    required this.enabled,
    required this.selected,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      constraints: BoxConstraints(minHeight: fullWidth ? 49 : 43),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppTheme.lavender : Colors.white,
        borderRadius: BorderRadius.circular(fullWidth ? 17 : 22),
        border: Border.all(
          color: selected ? AppTheme.accent : const Color(0xFFD8C9FF),
        ),
        boxShadow: selected ? AppTheme.softShadow : null,
      ),
      child: Center(
        child: Text(
          choice.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.18,
            fontWeight: FontWeight.w700,
            color: enabled ? AppTheme.accent : AppTheme.textSecondary,
          ),
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.58,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(22),
        child: fullWidth ? SizedBox(width: double.infinity, child: child) : child,
      ),
    );
  }
}

class _GameChoiceArea extends StatelessWidget {
  final List<TutorChoice> choices;
  final bool enabled;
  final String? selectedChoiceId;
  final ValueChanged<TutorChoice>? onSelected;

  const _GameChoiceArea({
    required this.choices,
    required this.enabled,
    required this.selectedChoiceId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: choices.map((choice) {
        final metadata = _gameMetadata(choice.id);
        final selected = selectedChoiceId == choice.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Opacity(
            opacity: enabled ? 1 : 0.58,
            child: InkWell(
              onTap: enabled ? () => onSelected?.call(choice) : null,
              borderRadius: BorderRadius.circular(22),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.softLavender : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: selected ? AppTheme.accent : AppTheme.border,
                  ),
                  boxShadow: AppTheme.softShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: AppTheme.softLavender,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        metadata.$1,
                        size: 35,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            choice.label,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            metadata.$2,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.accent,
                      size: 30,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

(IconData, String) _gameMetadata(String id) {
  switch (id) {
    case 'game_memory':
      return (Icons.style_rounded, 'Deux associations rapides.');
    case 'game_chrono':
      return (Icons.timer_rounded, 'Deux défis rapides.');
    case 'game_true_false':
      return (Icons.rule_rounded, 'Deux affirmations vrai ou faux.');
    default:
      return (Icons.quiz_rounded, 'Réponds à deux questions courtes.');
  }
}

class _MascotAvatar extends StatelessWidget {
  const _MascotAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 37,
      height: 37,
      margin: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.lavender,
      ),
      padding: const EdgeInsets.all(5),
      child: Image.asset(
        'assets/images/mascot.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.smart_toy_rounded,
          color: AppTheme.accent,
          size: 22,
        ),
      ),
    );
  }
}

class _ThinkingLine extends StatelessWidget {
  const _ThinkingLine();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Préparation de la réponse complète…',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}
