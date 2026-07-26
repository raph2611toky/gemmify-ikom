import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme/app_theme.dart';

class ChatInputBar extends StatefulWidget {
  final void Function(
    String text,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    Duration? audioDuration,
  ) onSend;
  final bool isGenerating;
  final VoidCallback onStop;
  final VoidCallback onRecordingStarted;
  final bool voiceConversationEnabled;
  final int autoListenRequestId;

  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.isGenerating,
    required this.onStop,
    required this.onRecordingStarted,
    required this.voiceConversationEnabled,
    required this.autoListenRequestId,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _textController = TextEditingController();
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();

  Uint8List? _pendingImage;
  bool _showAttachments = false;
  bool _isPickingImage = false;
  bool _isRecording = false;
  bool _isStoppingRecording = false;
  DateTime? _recordingStartedAt;
  DateTime? _lastVoiceAt;
  bool _heardVoice = false;
  Duration _recordingDuration = Duration.zero;
  double _amplitude = 0;
  String? _recordingPath;

  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Timer? _recordingTimer;

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.autoListenRequestId != oldWidget.autoListenRequestId &&
        widget.voiceConversationEnabled &&
        !widget.isGenerating &&
        !_isRecording) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startRecording(autoTriggered: true);
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPickingImage || widget.isGenerating || _isRecording) return;

    setState(() {
      _isPickingImage = true;
      _showAttachments = false;
    });

    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1200,
        maxHeight: 1200,
        requestFullMetadata: false,
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('L’image sélectionnée est vide.');
      }

      if (!mounted) return;
      setState(() => _pendingImage = bytes);
      debugPrint('🖼️ Image sélectionnée : ${bytes.length} octets');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de lire l’image : $error')),
      );
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  void _showFileMessage() {
    setState(() => _showAttachments = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Le sélecteur de documents utilise le module natif FileSelector.',
        ),
      ),
    );
  }

  Future<void> _startRecording({bool autoTriggered = false}) async {
    if (_isRecording || _isStoppingRecording || widget.isGenerating) return;

    widget.onRecordingStarted();
    setState(() => _showAttachments = false);

    try {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Autorise le microphone dans les paramètres pour utiliser le mode vocal.',
            ),
          ),
        );
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final voiceDirectory = Directory('${directory.path}/voice_messages');
      if (!await voiceDirectory.exists()) {
        await voiceDirectory.create(recursive: true);
      }

      final path =
          '${voiceDirectory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';

      setState(() {
        _pendingImage = null;
        _isRecording = true;
        _recordingStartedAt = DateTime.now();
        _recordingDuration = Duration.zero;
        _lastVoiceAt = null;
        _heardVoice = false;
        _amplitude = 0;
        _recordingPath = path;
      });

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
          audioInterruption: AudioInterruptionMode.pauseResume,
        ),
        path: path,
      );

      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((value) {
        if (!mounted || !_isRecording) return;

        final normalized = ((value.current + 60) / 60).clamp(0.0, 1.0);
        if (value.current > -42) {
          _heardVoice = true;
          _lastVoiceAt = DateTime.now();
        }

        setState(() => _amplitude = normalized);
      });

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _updateRecording(autoTriggered: autoTriggered),
      );
    } catch (error) {
      await _cleanupRecordingState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de démarrer le microphone : $error')),
      );
    }
  }

  void _updateRecording({required bool autoTriggered}) {
    final startedAt = _recordingStartedAt;
    if (!_isRecording || startedAt == null) return;

    final now = DateTime.now();
    final elapsed = now.difference(startedAt);

    if (mounted) setState(() => _recordingDuration = elapsed);

    final lastVoice = _lastVoiceAt;
    final silenceDuration = lastVoice == null ? elapsed : now.difference(lastVoice);

    final shouldStopAfterSilence =
        widget.voiceConversationEnabled &&
        _heardVoice &&
        elapsed >= const Duration(milliseconds: 1200) &&
        silenceDuration >= const Duration(milliseconds: 1400);

    final maximumReached = elapsed >= const Duration(seconds: 28);

    if (shouldStopAfterSilence || maximumReached) {
      _stopRecording(send: true);
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_isRecording || _isStoppingRecording) return;

    _isStoppingRecording = true;
    final duration = _recordingDuration;
    final knownPath = _recordingPath;

    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;

      final stoppedPath = await _recorder.stop();
      final path = stoppedPath ?? knownPath;

      if (send && path != null) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.length > 44) {
            widget.onSend('', null, bytes, duration);
            await file.delete();
          }
        }
      } else if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de terminer l’audio : $error')),
        );
      }
    } finally {
      await _cleanupRecordingState();
      _isStoppingRecording = false;
    }
  }

  Future<void> _cleanupRecordingState() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _recordingStartedAt = null;
      _recordingDuration = Duration.zero;
      _lastVoiceAt = null;
      _heardVoice = false;
      _amplitude = 0;
      _recordingPath = null;
    });
  }

  void _handleSend() {
    if (widget.isGenerating || _isRecording) return;

    final text = _textController.text.trim();
    final image = _pendingImage;
    if (text.isEmpty && image == null) return;

    widget.onSend(text, image, null, null);
    _textController.clear();
    setState(() {
      _pendingImage = null;
      _showAttachments = false;
    });
  }

  String get _durationLabel {
    final minutes =
        _recordingDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        _recordingDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _amplitudeSubscription?.cancel();
    _recorder.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.background,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingImage != null && !_isRecording)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 9, left: 8),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          _pendingImage!,
                          height: 76,
                          width: 76,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -7,
                        right: -7,
                        child: InkWell(
                          onTap: widget.isGenerating
                              ? null
                              : () => setState(() => _pendingImage = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppTheme.textPrimary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _showAttachments && !_isRecording
                  ? Align(
                      key: const ValueKey('attachment-menu'),
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10, left: 4),
                        child: _AttachmentMenu(
                          loading: _isPickingImage,
                          onCamera: () => _pickImage(ImageSource.camera),
                          onGallery: () => _pickImage(ImageSource.gallery),
                          onFile: _showFileMessage,
                          onScan: () => _pickImage(ImageSource.camera),
                          onAudio: _startRecording,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('attachment-empty')),
            ),
            if (_isRecording)
              _RecordingPanel(
                amplitude: _amplitude,
                durationLabel: _durationLabel,
                automatic: widget.voiceConversationEnabled,
                onCancel: () => _stopRecording(send: false),
                onSend: () => _stopRecording(send: true),
              )
            else
              Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.softShadow,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: widget.isGenerating
                          ? null
                          : () {
                              setState(() => _showAttachments = !_showAttachments);
                            },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _showAttachments
                              ? AppTheme.accent
                              : AppTheme.lavender,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _showAttachments ? Icons.close_rounded : Icons.add_rounded,
                          size: 25,
                          color: _showAttachments ? Colors.white : AppTheme.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 4,
                        enabled: !widget.isGenerating,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Pose ta question...',
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 11),
                        ),
                        onTap: () {
                          if (_showAttachments) {
                            setState(() => _showAttachments = false);
                          }
                        },
                        onSubmitted: (_) => _handleSend(),
                      ),
                    ),
                    const SizedBox(width: 5),
                    InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: widget.isGenerating ? widget.onStop : _handleSend,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x365A22E8),
                              blurRadius: 14,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.isGenerating
                              ? Icons.stop_rounded
                              : Icons.arrow_upward_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentMenu extends StatelessWidget {
  final bool loading;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final VoidCallback onScan;
  final VoidCallback onAudio;

  const _AttachmentMenu({
    required this.loading,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    required this.onScan,
    required this.onAudio,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: (MediaQuery.sizeOf(context).width - 36).clamp(240.0, 286.0).toDouble(),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x210C1238),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachmentTile(
            icon: Icons.camera_alt_outlined,
            color: AppTheme.accent,
            label: 'Caméra',
            onTap: loading ? null : onCamera,
          ),
          _AttachmentTile(
            icon: Icons.image_outlined,
            color: const Color(0xFF19B86A),
            label: 'Galerie',
            onTap: loading ? null : onGallery,
          ),
          _AttachmentTile(
            icon: Icons.description_outlined,
            color: const Color(0xFF2788F6),
            label: 'Fichier',
            onTap: onFile,
          ),
          _AttachmentTile(
            icon: Icons.document_scanner_outlined,
            color: const Color(0xFFFF7A1A),
            label: 'Scanner un document',
            onTap: loading ? null : onScan,
          ),
          _AttachmentTile(
            icon: Icons.mic_none_rounded,
            color: AppTheme.accent,
            label: 'Enregistrer un audio',
            onTap: onAudio,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  final bool showDivider;

  const _AttachmentTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 23),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 43, color: AppTheme.border),
      ],
    );
  }
}

class _RecordingPanel extends StatelessWidget {
  final double amplitude;
  final String durationLabel;
  final bool automatic;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const _RecordingPanel({
    required this.amplitude,
    required this.durationLabel,
    required this.automatic,
    required this.onCancel,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Annuler',
            onPressed: onCancel,
            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
          ),
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.lavender,
                borderRadius: BorderRadius.circular(21),
              ),
              child: Row(
                children: [
                  const _PulsingMic(),
                  const SizedBox(width: 9),
                  Expanded(child: _LiveWaveform(amplitude: amplitude)),
                  const SizedBox(width: 9),
                  Text(
                    durationLabel,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: automatic ? 'Envoyer maintenant' : 'Envoyer le vocal',
            onPressed: onSend,
            icon: const Icon(Icons.send_rounded, color: AppTheme.accent),
          ),
        ],
      ),
    );
  }
}

class _PulsingMic extends StatefulWidget {
  const _PulsingMic();

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 1).animate(_controller),
      child: const Icon(Icons.mic_rounded, color: AppTheme.accent),
    );
  }
}

class _LiveWaveform extends StatelessWidget {
  final double amplitude;

  const _LiveWaveform({required this.amplitude});

  @override
  Widget build(BuildContext context) {
    const pattern = <double>[
      0.35,
      0.65,
      0.45,
      0.9,
      0.58,
      0.38,
      0.78,
      0.5,
      1,
      0.42,
      0.72,
      0.32,
      0.56,
      0.82,
      0.46,
      0.68,
    ];
    final level = 0.18 + amplitude * 0.82;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: pattern.map((factor) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 2.5,
          height: 8 + 24 * factor * level,
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }).toList(),
    );
  }
}
