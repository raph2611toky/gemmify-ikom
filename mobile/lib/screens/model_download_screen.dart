import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/background_model_download_service.dart';
import '../services/gemma_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen>
    with WidgetsBindingObserver {
  final GemmaService _gemma = GemmaService();

  StreamSubscription<ModelDownloadSnapshot>? _subscription;
  ModelDownloadSnapshot? _snapshot;

  String _status = 'Vérification du modèle...';
  bool _error = false;
  bool _openingChat = false;
  bool _preparing = false;

  double get _progress => _snapshot?.progress ?? 0;
  int get _percentage => _snapshot?.percentage ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_prepare());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAfterResume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_preparing || _openingChat) return;
    _preparing = true;

    try {
      final alreadyInstalled = await _gemma.isModelAlreadyDownloaded();

      if (alreadyInstalled) {
        _openingChat = true;
        _openChatImmediately();
        return;
      }

      final initial = await _gemma.startBackgroundDownload();
      _applySnapshot(initial);
      await _startWatching();
    } on PlatformException catch (error) {
      _showError(error.message ?? error.code);
    } catch (error) {
      _showError(error.toString());
    } finally {
      _preparing = false;
    }
  }

  Future<void> _startWatching() async {
    await _subscription?.cancel();

    _subscription = _gemma.watchDownload().listen(
      _applySnapshot,
      onError: (Object error, StackTrace stackTrace) {
        _showError(error.toString());
      },
    );
  }

  Future<void> _refreshAfterResume() async {
    if (_openingChat) return;

    try {
      final current = await _gemma.getDownloadState();
      _applySnapshot(current);

      if (current.isActive) {
        await _startWatching();
      }
    } catch (_) {
      // Le Worker Android continue même si une lecture ponctuelle échoue.
    }
  }

  void _applySnapshot(ModelDownloadSnapshot snapshot) {
    if (!mounted) return;

    setState(() {
      _snapshot = snapshot;
      _error = snapshot.hasError;
      _status = _statusFor(snapshot);
    });

    if (snapshot.isCompleted && snapshot.filePath != null && !_openingChat) {
      unawaited(_installAndOpen(snapshot.filePath!));
    }
  }

  String _statusFor(ModelDownloadSnapshot snapshot) {
    return switch (snapshot.status) {
      ModelDownloadStatus.idle => 'Préparation du téléchargement...',
      ModelDownloadStatus.queued =>
        'Téléchargement planifié. Démarrage automatique...',
      ModelDownloadStatus.downloading =>
        'Téléchargement en arrière-plan · ${snapshot.percentage} %',
      ModelDownloadStatus.waiting =>
        'Connexion interrompue · reprise automatique à ${snapshot.percentage} %',
      ModelDownloadStatus.completed =>
        'Téléchargement terminé · installation du modèle...',
      ModelDownloadStatus.error =>
        snapshot.error ?? 'Erreur pendant le téléchargement.',
      ModelDownloadStatus.cancelled =>
        'Téléchargement annulé à ${snapshot.percentage} %.',
    };
  }

  Future<void> _installAndOpen(String filePath) async {
    if (_openingChat) return;
    _openingChat = true;

    try {
      await _showStage(
        'Vérification et enregistrement du modèle local...',
      );

      await _gemma.installDownloadedModel(filePath);
      await _showStage('Modèle installé. Ouverture de Mpanabe AI…');
      _openChatImmediately();
    } catch (error) {
      _openingChat = false;
      _showError('Installation impossible : $error');
    }
  }

  void _openChatImmediately() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ChatScreen()),
    );
  }

  Future<void> _showStage(String message) async {
    if (!mounted) return;

    setState(() {
      _error = false;
      _status = message;
    });

    // Laisse Flutter dessiner le nouveau texte avant l’appel natif lourd.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _error = true;
      _status = message;
    });
  }

  Future<void> _retry() async {
    if (mounted) {
      setState(() {
        _error = false;
        _status = 'Reprise depuis $_percentage %...';
      });
    }

    try {
      final snapshot = await _gemma.startBackgroundDownload();
      _applySnapshot(snapshot);
      await _startWatching();
    } catch (error) {
      _showError(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final showDownloadDetails = snapshot != null && !snapshot.isCompleted;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Mpanabe AI',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Assistant pédagogique 100% offline',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Text(
                    '$_percentage %',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: AppTheme.border,
                      color: _error ? AppTheme.error : AppTheme.accent,
                      minHeight: 9,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: _error
                          ? AppTheme.error
                          : AppTheme.textSecondary,
                    ),
                  ),
                  if (showDownloadDetails) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${snapshot.downloadedLabel} / ${snapshot.totalLabel}'
                      '${snapshot.speedBytesPerSecond > 0 ? ' · ${snapshot.speedLabel}' : ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                  if (snapshot?.isActive == true) ...[
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 20,
                            color: AppTheme.accent,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Vous pouvez réduire l’application ou éteindre '
                              'l’écran. Le téléchargement continue dans la '
                              'notification Android et reprend au même '
                              'pourcentage après une coupure.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_error ||
                      snapshot?.status == ModelDownloadStatus.cancelled) ...[
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _retry,
                        child: const Text('Reprendre le téléchargement'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
