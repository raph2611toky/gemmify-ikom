import 'dart:async';

import 'package:flutter/services.dart';

enum ModelDownloadStatus {
  idle,
  queued,
  downloading,
  waiting,
  completed,
  error,
  cancelled,
}

class ModelDownloadSnapshot {
  const ModelDownloadSnapshot({
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speedBytesPerSecond,
    required this.filePath,
    required this.error,
  });

  final ModelDownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final int speedBytesPerSecond;
  final String? filePath;
  final String? error;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
  }

  int get percentage => (progress * 100).floor();

  bool get isActive =>
      status == ModelDownloadStatus.queued ||
      status == ModelDownloadStatus.downloading ||
      status == ModelDownloadStatus.waiting;

  bool get isCompleted => status == ModelDownloadStatus.completed;
  bool get hasError => status == ModelDownloadStatus.error;

  String get downloadedLabel => formatBytes(downloadedBytes);
  String get totalLabel => totalBytes > 0 ? formatBytes(totalBytes) : '—';
  String get speedLabel =>
      speedBytesPerSecond > 0 ? '${formatBytes(speedBytesPerSecond)}/s' : '—';

  static ModelDownloadSnapshot fromMap(Map<Object?, Object?> map) {
    return ModelDownloadSnapshot(
      status: _statusFromString(map['status']?.toString()),
      downloadedBytes: _toInt(map['downloadedBytes']),
      totalBytes: _toInt(map['totalBytes']),
      speedBytesPerSecond: _toInt(map['speedBytesPerSecond']),
      filePath: _nullableString(map['filePath']),
      error: _nullableString(map['error']),
    );
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString();
    return text == null || text.isEmpty ? null : text;
  }

  static ModelDownloadStatus _statusFromString(String? value) {
    return switch (value) {
      'queued' => ModelDownloadStatus.queued,
      'downloading' => ModelDownloadStatus.downloading,
      'waiting' => ModelDownloadStatus.waiting,
      'completed' => ModelDownloadStatus.completed,
      'error' => ModelDownloadStatus.error,
      'cancelled' => ModelDownloadStatus.cancelled,
      _ => ModelDownloadStatus.idle,
    };
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes o';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} Ko';
    final mib = kib / 1024;
    if (mib < 1024) return '${mib.toStringAsFixed(1)} Mo';
    final gib = mib / 1024;
    return '${gib.toStringAsFixed(2)} Go';
  }
}

/// Pont Flutter -> WorkManager Android.
///
/// Le téléchargement est exécuté nativement dans un Worker foreground :
/// il continue lorsque l'application est réduite et publie le pourcentage
/// dans une notification Android. L'UI relit simplement l'état persistant.
class BackgroundModelDownloadService {
  BackgroundModelDownloadService._();

  static final BackgroundModelDownloadService instance =
      BackgroundModelDownloadService._();

  static const MethodChannel _channel =
      MethodChannel('gemmafy/model_download');

  Future<ModelDownloadSnapshot> start({
    required String url,
    required String fileName,
    required int expectedTotalBytes,
  }) async {
    final raw = await _channel.invokeMethod<Object?>('startModelDownload', {
      'url': url,
      'fileName': fileName,
      'expectedTotalBytes': expectedTotalBytes,
    });
    return _decode(raw);
  }

  Future<ModelDownloadSnapshot> getState() async {
    final raw =
        await _channel.invokeMethod<Object?>('getModelDownloadState');
    return _decode(raw);
  }

  Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancelModelDownload');
  }

  /// Flux de suivi destiné uniquement à l'écran visible.
  ///
  /// Quand Flutter est suspendu, le Worker Android et la notification continuent.
  /// Au retour dans l'application, le prochain appel relit les octets persistés.
  Stream<ModelDownloadSnapshot> watch({
    Duration interval = const Duration(milliseconds: 800),
  }) async* {
    ModelDownloadSnapshot? previous;

    while (true) {
      final current = await getState();

      final changed = previous == null ||
          current.status != previous.status ||
          current.downloadedBytes != previous.downloadedBytes ||
          current.totalBytes != previous.totalBytes ||
          current.error != previous.error;

      if (changed) {
        yield current;
        previous = current;
      }

      if (current.isCompleted ||
          current.hasError ||
          current.status == ModelDownloadStatus.cancelled) {
        return;
      }

      await Future<void>.delayed(interval);
    }
  }

  ModelDownloadSnapshot _decode(Object? raw) {
    if (raw is Map<Object?, Object?>) {
      return ModelDownloadSnapshot.fromMap(raw);
    }

    throw PlatformException(
      code: 'invalid_download_state',
      message: 'État de téléchargement Android invalide.',
    );
  }
}
