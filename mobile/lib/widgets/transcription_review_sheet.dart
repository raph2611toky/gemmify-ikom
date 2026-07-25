import 'package:flutter/material.dart';

import '../models/audio_language_mode.dart';
import '../theme/app_theme.dart';

class TranscriptionReviewResult {
  final String transcript;
  final AudioLanguageMode languageMode;
  final bool consentForTraining;

  const TranscriptionReviewResult({
    required this.transcript,
    required this.languageMode,
    required this.consentForTraining,
  });
}

class TranscriptionReviewSheet extends StatefulWidget {
  final String initialTranscript;
  final AudioLanguageMode initialLanguageMode;

  const TranscriptionReviewSheet({
    super.key,
    required this.initialTranscript,
    required this.initialLanguageMode,
  });

  @override
  State<TranscriptionReviewSheet> createState() =>
      _TranscriptionReviewSheetState();
}

class _TranscriptionReviewSheetState
    extends State<TranscriptionReviewSheet> {
  late final TextEditingController _controller;
  late AudioLanguageMode _languageMode;
  bool _consentForTraining = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTranscript);
    _languageMode = widget.initialLanguageMode;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validate() {
    final transcript = _controller.text.trim();
    if (transcript.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Corrige ou saisis la transcription avant de continuer.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      TranscriptionReviewResult(
        transcript: transcript,
        languageMode: _languageMode,
        consentForTraining: _consentForTraining,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 18 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(Icons.hearing_rounded, color: Color(0xFF5A32F2)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mpanabe a compris',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Vérifie la transcription. Tes corrections servent à améliorer '
                'l’expérience malagasy sur ce téléphone.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AudioLanguageMode>(
                value: _languageMode,
                decoration: const InputDecoration(
                  labelText: 'Langue parlée',
                  prefixIcon: Icon(Icons.translate_rounded),
                ),
                items: AudioLanguageMode.values
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(),
                onChanged: (mode) {
                  if (mode != null) setState(() => _languageMode = mode);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: false,
                minLines: 3,
                maxLines: 7,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Transcription validée',
                  alignLabelWithHint: true,
                  hintText: 'Corrige ici les mots mal compris…',
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F5FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5DFFF)),
                ),
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _consentForTraining,
                  activeColor: const Color(0xFF5A32F2),
                  title: const Text(
                    'Autoriser l’ajout de cet audio au dataset local',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: const Text(
                    'L’audio et la correction restent sur le téléphone. '
                    'Ils ne sont jamais envoyés automatiquement.',
                    style: TextStyle(fontSize: 12, height: 1.35),
                  ),
                  onChanged: (value) {
                    setState(() => _consentForTraining = value ?? false);
                  },
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _validate,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Valider'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
