import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';

class OnlineVideoPlayer extends StatefulWidget {
  final String url;
  final bool isMalagasy;

  const OnlineVideoPlayer({
    super.key,
    required this.url,
    required this.isMalagasy,
  });

  @override
  State<OnlineVideoPlayer> createState() => _OnlineVideoPlayerState();
}

class _OnlineVideoPlayerState extends State<OnlineVideoPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initialization;
  String _error = '';

  String _tr(String french, String malagasy) =>
      widget.isMalagasy ? malagasy : french;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant OnlineVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _createController();
    }
  }

  void _createController() {
    final uri = Uri.tryParse(widget.url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _error = _tr(
        'Le lien vidéo reçu est invalide.',
        'Tsy mety ny rohin’ny horonan-tsary voaray.',
      );
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    _initialization = controller.initialize().then((_) async {
      await controller.setLooping(false);
      if (mounted) setState(() {});
    }).catchError((Object error) {
      if (!mounted) return;
      setState(() {
        _error = _tr(
          'Impossible de charger la vidéo. Vérifie que le téléphone et le serveur sont sur le même réseau.',
          'Tsy afaka nampiditra ny horonan-tsary. Hamarino fa tambajotra iray ihany no ampiasain’ny finday sy ny serveur.',
        );
      });
    });
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    _initialization = null;
    if (controller != null) await controller.dispose();
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFCDD2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(_error)),
          ],
        ),
      );
    }

    final controller = _controller;
    final initialization = _initialization;
    if (controller == null || initialization == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<void>(
      future: initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return Container(
            height: 190,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const CircularProgressIndicator(),
          );
        }

        final aspectRatio = controller.value.aspectRatio <= 0
            ? 16 / 9
            : controller.value.aspectRatio;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: Colors.black,
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: VideoPlayer(controller),
                ),
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: EdgeInsets.zero,
                ),
                Material(
                  color: Colors.black,
                  child: Row(
                    children: [
                      IconButton(
                        color: Colors.white,
                        tooltip: controller.value.isPlaying
                            ? _tr('Pause', 'Ajanony vetivety')
                            : _tr('Lire', 'Alefaso'),
                        onPressed: () async {
                          if (controller.value.isPlaying) {
                            await controller.pause();
                          } else {
                            if (controller.value.position >=
                                controller.value.duration) {
                              await controller.seekTo(Duration.zero);
                            }
                            await controller.play();
                          }
                          if (mounted) setState(() {});
                        },
                        icon: Icon(
                          controller.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      IconButton(
                        color: Colors.white,
                        tooltip: _tr('Recommencer', 'Avereno'),
                        onPressed: () async {
                          await controller.seekTo(Duration.zero);
                          await controller.play();
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.replay_rounded),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          _formatDuration(controller.value.duration),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
