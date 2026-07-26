enum AudioLanguageMode {
  malagasy,

  /// Conservé uniquement pour relire les anciennes données SQLite.
  /// L'interface ne propose plus ce mode ambigu.
  mixed,
  french,
}

/// Les deux seuls choix visibles dans l'application.
const List<AudioLanguageMode> selectableAudioLanguageModes = [
  AudioLanguageMode.french,
  AudioLanguageMode.malagasy,
];

extension AudioLanguageModeX on AudioLanguageMode {
  bool get isMalagasy => this == AudioLanguageMode.malagasy;

  /// Toute ancienne valeur `mixed` est ramenée vers le français afin que
  /// chaque discussion ait désormais une langue unique et prévisible.
  AudioLanguageMode get normalized =>
      this == AudioLanguageMode.mixed ? AudioLanguageMode.french : this;

  String get label {
    switch (normalized) {
      case AudioLanguageMode.malagasy:
        return 'Malagasy';
      case AudioLanguageMode.french:
        return 'Français';
      case AudioLanguageMode.mixed:
        return 'Français';
    }
  }

  String get shortLabel => isMalagasy ? 'MG' : 'FR';

  String get storageValue => normalized.name;

  String get transcriptionInstruction {
    if (isMalagasy) {
      return '''
Ny mpiteny dia miteny amin'ny teny malagasy.
Soraty amin'ny teny malagasy marina ilay feo.
Aza adika amin'ny teny frantsay na anglisy.
Tehirizo araka izay azo atao ny anarana, ny isa, ny raikipohy ary ny mari-pamantarana.
Raha misy teny tsy mazava dia soraty hoe [tsy mazava].
Aza manampy fanazavana na valiny: ny transcription ihany no averina.
''';
    }
    return '''
La personne parle principalement français.
Transcris exactement le message en français.
Conserve les noms, nombres, formules et symboles.
Si un mot est incompréhensible, écris [inaudible].
Ne donne aucune explication ni réponse : retourne uniquement la transcription.
''';
  }

  String get responseInstruction {
    if (isMalagasy) {
      return '''
Valio amin'ny teny malagasy ihany.
Ny fanazavana, fanontaniana, fanitsiana, lalao, safidy ary fampaherezana rehetra dia tsy maintsy amin'ny teny malagasy.
Aza mampiasa teny na fehezanteny frantsay. Tehirizo fotsiny ny isa, ny raikipohy, ny mari-pamantarana ary ny anarana manokana tsy azo ovaina.
Hazavao tsotra sy fohy toy ny mpampianatra manam-paharetana.
Ho an'ny marina na diso dia ampiasao ny safidy « Marina » sy « Diso ».
''';
    }
    return '''
Réponds uniquement en français clair et pédagogique.
Les explications, questions, corrections, jeux, choix et encouragements doivent tous être en français.
Explique brièvement et adapte le vocabulaire au niveau de l'élève.
''';
  }

  List<String> get preferredTtsLocales =>
      isMalagasy ? const ['mg-MG', 'fr-FR'] : const ['fr-FR'];
}

AudioLanguageMode audioLanguageModeFromStorage(String? value) {
  if (value == AudioLanguageMode.malagasy.name) {
    return AudioLanguageMode.malagasy;
  }
  return AudioLanguageMode.french;
}
