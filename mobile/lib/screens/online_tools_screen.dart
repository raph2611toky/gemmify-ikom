import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/audio_language_mode.dart';
import '../models/online_tool_response.dart';
import '../services/gemmify_ikom_service.dart';
import '../services/local_learning_database.dart';
import '../theme/app_theme.dart';
import '../widgets/online_video_player.dart';

class OnlineToolsScreen extends StatefulWidget {
  final AudioLanguageMode languageMode;
  final String initialSubject;
  final String initialTopic;
  final int initialTab;

  const OnlineToolsScreen({
    super.key,
    required this.languageMode,
    this.initialSubject = '',
    this.initialTopic = '',
    this.initialTab = 0,
  });

  @override
  State<OnlineToolsScreen> createState() => _OnlineToolsScreenState();
}

class _OnlineToolsScreenState extends State<OnlineToolsScreen>
    with SingleTickerProviderStateMixin {
  final _service = GemmifyIkomService.instance;
  final _db = LocalLearningDatabase.instance;
  final _analysisController = TextEditingController();
  final _videoSubjectController = TextEditingController();
  final _videoContextController = TextEditingController();
  final _analysisScrollController = ScrollController();

  late final TabController _tabController;
  final List<OnlinePickedFile> _files = [];

  String _baseUrl = GemmifyIkomService.defaultBaseUrl;
  bool _loadingSettings = true;
  bool _analysisLoading = false;
  bool _videoLoading = false;
  String _analysisError = '';
  String _videoError = '';
  bool _analysisCanRetry = false;
  bool _videoCanRetry = false;
  OnlineToolResponse? _analysisResponse;
  OnlineToolResponse? _videoResponse;
  String _voiceSex = 'MASCULIN';
  double _maxDuration = 15;

  bool get _isMalagasy => widget.languageMode.normalized.isMalagasy;
  String _tr(String french, String malagasy) =>
      _isMalagasy ? malagasy : french;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1).toInt(),
    );
    _videoSubjectController.text = widget.initialTopic.trim().isNotEmpty
        ? widget.initialTopic.trim()
        : widget.initialSubject.trim();
    final subject = widget.initialSubject.trim();
    final topic = widget.initialTopic.trim();
    if (subject.isNotEmpty || topic.isNotEmpty) {
      _videoContextController.text = [subject, topic]
          .where((item) => item.isNotEmpty)
          .join(' — ');
    }
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _analysisController.dispose();
    _videoSubjectController.dispose();
    _videoContextController.dispose();
    _analysisScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _db.loadOnlineApiSettings();
      if (!mounted) return;
      setState(() {
        if (settings.baseUrl.isNotEmpty) _baseUrl = settings.baseUrl;
        _loadingSettings = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  Future<bool> _ensureConfigured() async {
    if (_baseUrl.trim().isNotEmpty) return true;
    await _showApiSettings();
    return _baseUrl.trim().isNotEmpty;
  }

  Future<void> _showApiSettings() async {
    final baseController = TextEditingController(text: _baseUrl);
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr(
          'Configurer Gemmify IKOM',
          'Hametraka Gemmify IKOM',
        )),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: _tr('Adresse de base API', 'Adiresy API'),
                  hintText: GemmifyIkomService.defaultBaseUrl,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _tr(
                  'Le backend gère tout directement. Aucune clé API n’est demandée par l’application.',
                  'Ny backend no mikarakara ny zava-drehetra. Tsy mila lakile API ny application.',
                ),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_tr('Annuler', 'Hanafoana')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'base_url': baseController.text.trim(),
            }),
            child: Text(_tr('Enregistrer', 'Hitahiry')),
          ),
        ],
      ),
    );
    baseController.dispose();
    if (result == null) return;
    final baseUrl = result['base_url'] ?? '';
    try {
      await _db.saveOnlineApiSettings(baseUrl: baseUrl);
      if (!mounted) return;
      setState(() {
        _baseUrl = baseUrl;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_tr('Configuration non sauvegardée', 'Tsy voatahiry ny fanamboarana')} : $error')),
      );
    }
  }

  Future<void> _pickFiles() async {
    if (_analysisLoading) return;
    const acceptedTypes = XTypeGroup(
      label: 'Images, PDF et textes',
      extensions: <String>[
        'jpg',
        'jpeg',
        'png',
        'webp',
        'pdf',
        'txt',
        'md',
        'csv',
      ],
      mimeTypes: <String>[
        'image/jpeg',
        'image/png',
        'image/webp',
        'application/pdf',
        'text/plain',
        'text/markdown',
        'text/csv',
      ],
    );

    final pickedFiles = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[acceptedTypes],
      confirmButtonText: _tr('Ajouter', 'Hanampy'),
    );
    if (pickedFiles.isEmpty) return;

    final selected = <OnlinePickedFile>[];
    for (final item in pickedFiles) {
      final path = item.path.trim();
      if (path.isEmpty) continue;

      var size = 0;
      try {
        size = await item.length();
      } catch (_) {
        // La validation du service vérifiera de nouveau le fichier avant envoi.
      }

      selected.add(
        OnlinePickedFile(
          path: path,
          name: item.name,
          sizeBytes: size,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      final existing = _files.map((item) => item.path).toSet();
      for (final item in selected) {
        if (existing.add(item.path)) _files.add(item);
      }
      if (_files.length > GemmifyIkomService.maxFiles) {
        _files.removeRange(GemmifyIkomService.maxFiles, _files.length);
      }
    });
  }

  Future<void> _runAnalysis({String? followUp}) async {
    if (_analysisLoading || !await _ensureConfigured()) return;
    final text = (followUp ?? _analysisController.text).trim();
    if (text.isEmpty) {
      setState(() {
        _analysisError = _tr(
          'Écris une consigne ou le corrigé attendu.',
          'Soraty aloha ny toromarika na ny valiny fanitsiana.',
        );
        _analysisCanRetry = false;
      });
      return;
    }
    setState(() {
      _analysisLoading = true;
      _analysisError = '';
      _analysisCanRetry = false;
      if (followUp == null) _analysisResponse = null;
    });
    try {
      final response = await _service.analyzeCopies(
        baseUrl: _baseUrl,
        text: _withLanguageInstruction(text),
        files: List.unmodifiable(_files),
        languageCode: _isMalagasy ? 'mg' : 'fr',
      );
      if (!mounted) return;
      setState(() => _analysisResponse = response);
      _scrollToAnalysisResult();
    } on GemmifyIkomException catch (error) {
      if (!mounted) return;
      setState(() {
        _analysisError = _localizedError(error);
        _analysisCanRetry = error.canRetry;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _analysisError = _tr(
          'Une erreur inattendue est survenue. Réessaie.',
          'Nisy olana tsy nampoizina. Andramo indray.',
        );
        _analysisCanRetry = true;
      });
    } finally {
      if (mounted) setState(() => _analysisLoading = false);
    }
  }

  void _scrollToAnalysisResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_analysisScrollController.hasClients) return;
      _analysisScrollController.animateTo(
        _analysisScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _runVideo() async {
    if (_videoLoading || !await _ensureConfigured()) return;
    setState(() {
      _videoLoading = true;
      _videoError = '';
      _videoCanRetry = false;
      _videoResponse = null;
    });
    try {
      final response = await _service.generateTutorial(
        baseUrl: _baseUrl,
        subject: _videoSubjectController.text,
        context: _withLanguageInstruction(_videoContextController.text),
        voiceSex: _voiceSex,
        maxDuration: _maxDuration.round(),
        languageCode: _isMalagasy ? 'mg' : 'fr',
      );
      if (!mounted) return;
      setState(() => _videoResponse = response);
    } on GemmifyIkomException catch (error) {
      if (!mounted) return;
      setState(() {
        _videoError = _localizedError(error);
        _videoCanRetry = error.canRetry;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _videoError = _tr(
          'La génération vidéo a échoué. Réessaie.',
          'Tsy nahomby ny famoronana horonan-tsary. Andramo indray.',
        );
        _videoCanRetry = true;
      });
    } finally {
      if (mounted) setState(() => _videoLoading = false);
    }
  }

  String _withLanguageInstruction(String text) {
    final clean = text.trim();
    if (!_isMalagasy) return clean;
    const instruction =
        'Valio sy soraty amin’ny teny malagasy ihany ny valin’ny fanadihadiana.';
    return clean.isEmpty ? instruction : '$clean\n\n$instruction';
  }

  String _localizedError(GemmifyIkomException error) {
    if (!_isMalagasy) return error.message;
    if (error is GemmifyIkomTimeoutException) {
      return 'Ela loatra ny fikarakarana. Andramo indray.';
    }
    if (error is GemmifyIkomNetworkException) {
      return 'Tsy misy fifandraisana internet azo ampiasaina.';
    }
    if (error is GemmifyIkomServerException) {
      return 'Misy olana vetivety amin’ny serveur. Andramo indray afaka fotoana fohy.';
    }
    if (error is GemmifyIkomValidationException) {
      return 'Hamarino ny toromarika, ny rakitra ary ny adiresin’ny serveur.';
    }
    return 'Nisy olana tamin’ny fitaovana an-tserasera. Andramo indray.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7FF),
      appBar: AppBar(
        title: Text(_tr('Outils en ligne', 'Fitaovana an-tserasera')),
        actions: [
          IconButton(
            tooltip: _tr('Configurer le serveur', 'Hametraka ny serveur'),
            onPressed: _showApiSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.fact_check_outlined),
              text: _tr('Analyser des copies', 'Hanadihady valin’asa'),
            ),
            Tab(
              icon: const Icon(Icons.play_circle_outline_rounded),
              text: _tr('Tutoriel vidéo', 'Horonan-tsary fampianarana'),
            ),
          ],
        ),
      ),
      body: _loadingSettings
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildOnlineBanner(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAnalysisTab(),
                      _buildVideoTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildOnlineBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8C9FF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_outlined, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _tr(
                'Connexion requise. Le tuteur Gemma local reste disponible hors ligne.',
                'Mila internet. Mbola azo ampiasaina tsy misy internet ny mpampianatra Gemma ao an-telefaonina.',
              ),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisTab() {
    return ListView(
      controller: _analysisScrollController,
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(
          _tr('Consigne et corrigé', 'Toromarika sy valiny fanitsiana'),
          Icons.edit_note_rounded,
        ),
        TextField(
          controller: _analysisController,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: _tr(
              'Exemple : analyse ces copies, repère les erreurs communes et propose une remédiation.',
              'Ohatra: diniho ireo valin’asa, tadiavo ny fahadisoana miverimberina ary omeo fanarenana.',
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _analysisLoading ? null : _pickFiles,
          icon: const Icon(Icons.attach_file_rounded),
          label: Text(_tr(
            'Ajouter images, PDF ou textes',
            'Hanampy sary, PDF na lahatsoratra',
          )),
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._files.asMap().entries.map(
                (entry) => Card(
                  elevation: 0,
                  child: ListTile(
                    dense: true,
                    leading: Icon(_fileIcon(entry.value.extension)),
                    title: Text(
                      entry.value.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_formatBytes(entry.value.sizeBytes)),
                    trailing: IconButton(
                      onPressed: _analysisLoading
                          ? null
                          : () => setState(() => _files.removeAt(entry.key)),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _analysisLoading ? null : () => _runAnalysis(),
          icon: _analysisLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_rounded),
          label: Text(_analysisLoading
              ? _tr('Analyse en cours…', 'Mandeha ny fanadihadiana…')
              : _tr('Analyser les copies', 'Hanadihady ireo valin’asa')),
        ),
        if (_analysisLoading)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _tr(
                'L’envoi de nombreux fichiers peut prendre 60 à 90 secondes.',
                'Mety haharitra 60 ka hatramin’ny 90 segondra ny fandefasana rakitra maro.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        if (_analysisError.isNotEmpty)
          _errorCard(
            _analysisError,
            canRetry: _analysisCanRetry,
            onRetry: () => _runAnalysis(),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          child: _analysisResponse == null
              ? const SizedBox.shrink()
              : _analysisResultCard(_analysisResponse!),
        ),
      ],
    );
  }

  Widget _buildVideoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(
          _tr('Créer un tutoriel vidéo', 'Hamorona horonan-tsary fampianarana'),
          Icons.movie_creation_outlined,
        ),
        TextField(
          controller: _videoSubjectController,
          decoration: InputDecoration(
            labelText: _tr('Sujet', 'Lohahevitra'),
            hintText: _tr('Exemple : les fractions', 'Ohatra: ny ampahany'),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _videoContextController,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: _tr('Contexte facultatif', 'Fanazavana fanampiny'),
            hintText: _tr(
              'Niveau, objectif, points à expliquer…',
              'Haavo, tanjona, zavatra hazavaina…',
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _voiceSex,
          decoration: InputDecoration(
            labelText: _tr('Voix', 'Feo'),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          items: [
            DropdownMenuItem(
              value: 'FEMININ',
              child: Text(_tr('Voix féminine', 'Feon-dehivavy')),
            ),
            DropdownMenuItem(
              value: 'MASCULIN',
              child: Text(_tr('Voix masculine', 'Feon-dehilahy')),
            ),
          ],
          onChanged: _videoLoading
              ? null
              : (value) => setState(() => _voiceSex = value ?? 'MASCULIN'),
        ),
        const SizedBox(height: 16),
        Text(
          '${_tr('Durée maximale', 'Faharetana farany ambony')} : ${_maxDuration.round()} s',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Slider(
          value: _maxDuration,
          min: 15,
          max: 120,
          divisions: 7,
          label: '${_maxDuration.round()} s',
          onChanged: _videoLoading
              ? null
              : (value) => setState(() => _maxDuration = value),
        ),
        FilledButton.icon(
          onPressed: _videoLoading ? null : _runVideo,
          icon: _videoLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.video_call_rounded),
          label: Text(_videoLoading
              ? _tr('Génération en cours…', 'Mamorona horonan-tsary…')
              : _tr('Générer la vidéo', 'Hamorona horonan-tsary')),
        ),
        if (_videoLoading)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _tr(
                'La vidéo est générée en ligne. Ne ferme pas cet écran.',
                'Atao an-tserasera ny horonan-tsary. Aza akatona ity pejy ity.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        if (_videoError.isNotEmpty)
          _errorCard(
            _videoError,
            canRetry: _videoCanRetry,
            onRetry: _runVideo,
          ),
        if (_videoResponse != null)
          _reportCard(
            title: _tr('Résultat vidéo', 'Vokatry ny horonan-tsary'),
            response: _videoResponse!,
          ),
      ],
    );
  }

  Widget _analysisResultCard(OnlineToolResponse response) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(response.report),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(top: 18, bottom: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7657F6), Color(0xFFA660F2)],
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: Color(0x337657F6),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            const Positioned(
              right: 18,
              top: 14,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: Color(0x66FFFFFF),
                size: 34,
              ),
            ),
            const Positioned(
              right: 54,
              top: 48,
              child: Icon(
                Icons.star_rounded,
                color: Color(0x55FFFFFF),
                size: 18,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          color: AppTheme.accent,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _tr(
                                'Analyse terminée !',
                                'Vita ny fanadihadiana!',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _tr(
                                'Voici directement le résultat du tuteur.',
                                'Ity avy hatrany ny valin’ny mpampianatra.',
                              ),
                              style: const TextStyle(
                                color: Color(0xFFEDE8FF),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: MarkdownBody(
                      data: response.report,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                          color: AppTheme.textPrimary,
                          height: 1.48,
                          fontSize: 15,
                        ),
                        strong: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                        h1: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                        h2: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                        listBullet: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: response.report),
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _tr(
                                'Analyse copiée.',
                                'Voakopia ny fanadihadiana.',
                              ),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(_tr('Copier', 'Handika')),
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

  Widget _reportCard({
    required String title,
    required OnlineToolResponse response,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0D6FF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 10),
          MarkdownBody(data: response.report),
          if (response.status.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${_tr('État', 'Toetra')} : ${response.status}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if (response.jobId.isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText('ID : ${response.jobId}'),
          ],
          if (response.subject.isNotEmpty ||
              response.voice.isNotEmpty ||
              response.durationSeconds != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (response.subject.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.topic_outlined, size: 17),
                    label: Text(response.subject),
                  ),
                if (response.voice.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.record_voice_over_outlined, size: 17),
                    label: Text(response.voice),
                  ),
                if (response.durationSeconds != null)
                  Chip(
                    avatar: const Icon(Icons.timer_outlined, size: 17),
                    label: Text('${response.durationSeconds} s'),
                  ),
              ],
            ),
          ],
          if (response.hasVideo) ...[
            const SizedBox(height: 14),
            const Divider(),
            Text(
              _tr('Tutoriel généré', 'Horonan-tsary voaforona'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            OnlineVideoPlayer(
              url: response.videoUrl,
              isMalagasy: _isMalagasy,
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                _tr('Afficher le lien technique', 'Asehoy ny rohy teknika'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(response.videoUrl),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: response.videoUrl),
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_tr(
                            'Lien copié.',
                            'Voakopia ny rohy.',
                          )),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(_tr('Copier le lien', 'Handika ny rohy')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorCard(
    String message, {
    required bool canRetry,
    required VoidCallback onRetry,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFC9CF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppTheme.error),
              const SizedBox(width: 9),
              Expanded(child: Text(message)),
            ],
          ),
          if (canRetry) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_tr('Réessayer', 'Andramo indray')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _fileIcon(String extension) {
  switch (extension) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'webp':
      return Icons.image_outlined;
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    default:
      return Icons.description_outlined;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes o';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} Ko';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} Mo';
}
