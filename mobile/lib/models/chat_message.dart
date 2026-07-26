import 'dart:typed_data';

import 'ai_tutor_response.dart';
import 'audio_language_mode.dart';

enum MessageStatus { streaming, done, error }

class ChatMessage {
  final String id;
  final bool isUser;
  String text;
  AiTutorResponse? tutorResponse;
  final Uint8List? imageBytes;
  final Uint8List? audioBytes;
  final bool audioPlaceholder;
  final Duration? audioDuration;
  final DateTime createdAt;
  AudioLanguageMode voiceLanguageMode;
  MessageStatus status;
  bool choicesEnabled;
  String? selectedChoiceId;

  ChatMessage({
    required this.id,
    required this.isUser,
    this.text = '',
    this.tutorResponse,
    this.imageBytes,
    this.audioBytes,
    this.audioPlaceholder = false,
    this.audioDuration,
    DateTime? createdAt,
    this.voiceLanguageMode = AudioLanguageMode.mixed,
    this.status = MessageStatus.done,
    this.choicesEnabled = true,
    this.selectedChoiceId,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get hasAudio =>
      audioPlaceholder || (audioBytes != null && audioBytes!.isNotEmpty);

  bool get hasChoices =>
      !isUser &&
      choicesEnabled &&
      (tutorResponse?.choices.isNotEmpty ?? false);
}
