import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/chat_message.dart';
import '../services/voice_interaction_service.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  String get _timeLabel {
    final hour = message.createdAt.hour.toString().padLeft(2, '0');
    final minute = message.createdAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _buildUserBubble(context) : _buildAssistantBubble(context);
  }

  Widget _buildUserBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.only(top: 7, bottom: 7, left: 70),
        padding: const EdgeInsets.fromLTRB(17, 14, 14, 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF4EFFF), Color(0xFFEDE4FF)],
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
                  fontSize: 15,
                  height: 1.4,
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
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.done_all_rounded,
                    size: 17,
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 7, bottom: 7, right: 52),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: AppTheme.lavender,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE4D8FF)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Image.asset(
                  'assets/images/mascot.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Container(
                padding: const EdgeInsets.fromLTRB(17, 15, 13, 11),
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
                    const Text(
                      '📚 Commençons ensemble.',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (message.hasAudio)
                      _AudioMessagePreview(
                        duration: message.audioDuration ?? Duration.zero,
                        foreground: AppTheme.textPrimary,
                      )
                    else if (message.status == MessageStatus.streaming &&
                        message.text.isEmpty)
                      const _TypingIndicator()
                    else
                      MarkdownBody(
                        data: message.text,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(
                            fontSize: 14.5,
                            color: AppTheme.textPrimary,
                            height: 1.5,
                          ),
                          strong: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                          h1: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                          h2: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                          listBullet: const TextStyle(fontSize: 14.5),
                          code: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.accentDark,
                            backgroundColor: AppTheme.softLavender,
                          ),
                        ),
                      ),
                    if (message.status == MessageStatus.error) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Essaie de renvoyer un message plus court.',
                        style: TextStyle(
                          color: AppTheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _timeLabel,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        if (message.status == MessageStatus.done &&
                            message.text.trim().isNotEmpty)
                          ValueListenableBuilder<bool>(
                            valueListenable:
                                VoiceInteractionService.instance.isSpeaking,
                            builder: (_, speaking, __) {
                              return InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: speaking
                                    ? VoiceInteractionService.instance.stop
                                    : () {
                                        VoiceInteractionService.instance.speak(
                                          message.text,
                                          languageMode:
                                              message.voiceLanguageMode,
                                        );
                                      },
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: Icon(
                                    speaking
                                        ? Icons.stop_circle_outlined
                                        : Icons.volume_up_outlined,
                                    size: 19,
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
    const heights = <double>[8, 15, 11, 20, 14, 9, 18, 12, 22, 10, 16, 8, 13, 19];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mic_rounded, color: foreground, size: 22),
        const SizedBox(width: 8),
        ...List.generate(heights.length, (index) {
          return Container(
            width: 2.3,
            height: heights[index],
            margin: const EdgeInsets.symmetric(horizontal: 1.1),
            decoration: BoxDecoration(
              color: foreground.withOpacity(0.76),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
        const SizedBox(width: 8),
        Text(
          _durationLabel,
          style: TextStyle(
            color: foreground,
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
    return SizedBox(
      width: 42,
      height: 18,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return Row(
            children: List.generate(3, (index) {
              final phase = (_controller.value - index * 0.2) % 1.0;
              final scale =
                  0.55 + 0.45 * (1 - (phase - 0.5).abs() * 2).clamp(0, 1);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
