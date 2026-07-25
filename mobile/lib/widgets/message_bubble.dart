import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/ai_tutor_response.dart';
import '../models/chat_message.dart';
import '../services/voice_interaction_service.dart';
import '../theme/app_theme.dart';
import 'learning_cards.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final ValueChanged<TutorChoice>? onChoiceSelected;

  const MessageBubble({
    super.key,
    required this.message,
    this.onChoiceSelected,
  });

  String get _timeLabel {
    final hour = message.createdAt.hour.toString().padLeft(2, '0');
    final minute = message.createdAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    if (message.isUser) return _buildUserBubble(context);

    final structured = message.tutorResponse;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAssistantBubble(context),
          if (structured != null &&
              structured.cardType != TutorCardType.none) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 43),
              child: LearningCard(response: structured),
            ),
          ],
          if (structured != null && structured.choices.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 43),
              child: _ChoiceArea(
                choices: structured.choices,
                enabled: message.choicesEnabled &&
                    message.status == MessageStatus.done,
                selectedChoiceId: message.selectedChoiceId,
                onSelected: onChoiceSelected,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUserBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(top: 6, bottom: 6, left: 48),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 9),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5F0FF), Color(0xFFEDE4FF)],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(7),
          ),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imageBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    message.imageBytes!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (message.hasAudio)
              _AudioMessagePreview(
                duration: message.audioDuration ?? Duration.zero,
                foreground: AppTheme.textPrimary,
              )
            else
              Text(
                message.text,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13.5,
                  height: 1.38,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeLabel,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.done_all_rounded,
                    size: 16,
                    color: AppTheme.accent,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(BuildContext context) {
    final assistantText = message.tutorResponse?.response.trim().isNotEmpty == true
        ? message.tutorResponse!.response.trim()
        : message.text.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MascotAvatar(size: 35),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            padding: const EdgeInsets.fromLTRB(15, 12, 11, 9),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(22),
              ),
              border: Border.all(color: AppTheme.border),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.status == MessageStatus.streaming &&
                    assistantText.isEmpty)
                  const _TypingIndicator()
                else if (message.hasAudio)
                  _AudioMessagePreview(
                    duration: message.audioDuration ?? Duration.zero,
                    foreground: AppTheme.textPrimary,
                  )
                else
                  MarkdownBody(
                    data: assistantText,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        fontSize: 13.3,
                        color: AppTheme.textPrimary,
                        height: 1.42,
                        fontWeight: FontWeight.w500,
                      ),
                      strong: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                      h1: const TextStyle(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                      ),
                      h2: const TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                      ),
                      listBullet: const TextStyle(fontSize: 13),
                      code: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.accentDark,
                        backgroundColor: AppTheme.softLavender,
                      ),
                    ),
                  ),
                if (message.status == MessageStatus.error) ...[
                  const SizedBox(height: 7),
                  const Text(
                    'Réessaie avec une question un peu plus courte.',
                    style: TextStyle(
                      color: AppTheme.error,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _timeLabel,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                    if (message.status == MessageStatus.done &&
                        assistantText.isNotEmpty)
                      ValueListenableBuilder<bool>(
                        valueListenable:
                            VoiceInteractionService.instance.isSpeaking,
                        builder: (_, speaking, __) {
                          return InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: speaking
                                ? VoiceInteractionService.instance.stop
                                : () => VoiceInteractionService.instance.speak(
                                      assistantText,
                                      languageMode: message.voiceLanguageMode,
                                    ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                speaking
                                    ? Icons.stop_circle_outlined
                                    : Icons.volume_up_outlined,
                                size: 18,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
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
    final useButtons = choices.any(
      (choice) => choice.style.toLowerCase() == 'button' ||
          choice.label.length > 24,
    );

    if (useButtons) {
      return Column(
        children: choices
            .map(
              (choice) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _FullWidthChoice(
                  choice: choice,
                  enabled: enabled,
                  selected: selectedChoiceId == choice.id,
                  onTap: onSelected,
                ),
              ),
            )
            .toList(growable: false),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: choices
          .map(
            (choice) => _ChoiceChip(
              choice: choice,
              enabled: enabled,
              selected: selectedChoiceId == choice.id,
              onTap: onSelected,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final TutorChoice choice;
  final bool enabled;
  final bool selected;
  final ValueChanged<TutorChoice>? onTap;

  const _ChoiceChip({
    required this.choice,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.lavender : Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: enabled && onTap != null ? () => onTap!(choice) : null,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(minHeight: 39),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? AppTheme.accent
                  : const Color(0xFFDCCEFF),
            ),
          ),
          child: Text(
            choice.label,
            style: TextStyle(
              color: enabled || selected
                  ? AppTheme.accent
                  : AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _FullWidthChoice extends StatelessWidget {
  final TutorChoice choice;
  final bool enabled;
  final bool selected;
  final ValueChanged<TutorChoice>? onTap;

  const _FullWidthChoice({
    required this.choice,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: enabled && onTap != null ? () => onTap!(choice) : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(49),
          foregroundColor: AppTheme.accent,
          disabledForegroundColor:
              selected ? AppTheme.accent : AppTheme.textSecondary,
          side: BorderSide(
            color: selected ? AppTheme.accent : const Color(0xFFBFA5FF),
          ),
          backgroundColor: selected ? AppTheme.lavender : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        ),
        child: Text(
          choice.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.2,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _MascotAvatar extends StatelessWidget {
  final double size;

  const _MascotAvatar({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(top: 7),
      decoration: BoxDecoration(
        color: AppTheme.lavender,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE4D8FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Image.asset(
          'assets/images/mascot.png',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.school_rounded,
            color: AppTheme.accent,
            size: 21,
          ),
        ),
      ),
    );
  }
}

class _AudioMessagePreview extends StatelessWidget {
  final Duration duration;
  final Color foreground;

  const _AudioMessagePreview({
    required this.duration,
    required this.foreground,
  });

  String get _durationLabel {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    const heights = <double>[8, 15, 11, 20, 14, 9, 18, 12, 22, 10, 16, 8];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mic_rounded, color: foreground, size: 20),
        const SizedBox(width: 7),
        ...heights.map(
          (height) => Container(
            width: 2.5,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.3),
            decoration: BoxDecoration(
              color: foreground.withOpacity(.72),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _durationLabel,
          style: TextStyle(
            color: foreground.withOpacity(.72),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value + index * .22) % 1.0;
            final opacity =
                0.45 + 0.55 * (1 - (phase - .5).abs() * 2).clamp(0.0, 1.0);
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
