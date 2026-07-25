enum AudioLanguageMode {
  malagasy,
  mixed,
  french,
}

extension AudioLanguageModeX on AudioLanguageMode {
  String get label {
    switch (this) {
      case AudioLanguageMode.malagasy:
        return 'Malagasy';
      case AudioLanguageMode.mixed:
        return 'Malagasy + français';
      case AudioLanguageMode.french:
        return 'Français';
    }
  }

  String get shortLabel {
    switch (this) {
      case AudioLanguageMode.malagasy:
        return 'MG';
      case AudioLanguageMode.mixed:
        return 'MG + FR';
      case AudioLanguageMode.french:
        return 'FR';
    }
  }

  String get storageValue => name;

  String get transcriptionInstruction {
    switch (this) {
      case AudioLanguageMode.malagasy:
        return '''
Ny mpiteny dia miteny amin'ny teny malagasy.
Adikao ho soratra malagasy marina ilay feo.
Aza adika amin'ny teny frantsay na anglisy.
Tehirizo araka izay azo atao ny fomba fiteny sy ny anaran-toerana malagasy.
Raha misy teny tsy mazava dia soraty hoe [tsy mazava].
Aza manampy fanazavana na valiny: ny transcription ihany no averina.
''';
      case AudioLanguageMode.mixed:
        return '''
Ny mpiteny dia mety hampifangaro teny malagasy sy teny frantsay, indrindra ireo voambolana ampiasaina any an-tsekoly.
Adikao marina ilay feo ary aza adika ireo teny teknika frantsay.
Tehirizo ny teny malagasy, ny anarana, ny formule ary ny voambolana toy ny équation, fonction, dérivée, théorème, cellule, énergie, grammaire.
Raha misy teny tsy mazava dia soraty hoe [tsy mazava].
Aza manampy fanazavana na valiny: ny transcription ihany no averina.
''';
      case AudioLanguageMode.french:
        return '''
La personne parle principalement français.
Transcris exactement le message en français.
Conserve les mots malagasy éventuellement prononcés.
Si un mot est incompréhensible, écris [inaudible].
Ne donne aucune explication ni réponse : retourne uniquement la transcription.
''';
    }
  }

  String get responseInstruction {
    switch (this) {
      case AudioLanguageMode.malagasy:
        return '''
Valio amin'ny teny malagasy mazava sy tsotra.
Hazavao tsikelikely toy ny mpampianatra manam-paharetana.
Afaka mampiasa teny teknika frantsay mahazatra any an-tsekoly rehefa ilaina, saingy hazavao amin'ny teny malagasy.
''';
      case AudioLanguageMode.mixed:
        return '''
Valio amin'ny teny malagasy mazava, ary tehirizo ireo voambolana teknika frantsay mahazatra any an-tsekoly.
Hazavao tsikelikely ary omeo ohatra mifanaraka amin'ny mpianatra eto Madagasikara.
''';
      case AudioLanguageMode.french:
        return '''
Réponds en français clair et pédagogique.
Explique étape par étape et adapte le vocabulaire au niveau d'un élève.
''';
    }
  }

  List<String> get preferredTtsLocales {
    switch (this) {
      case AudioLanguageMode.malagasy:
      case AudioLanguageMode.mixed:
        return const ['mg-MG', 'fr-FR'];
      case AudioLanguageMode.french:
        return const ['fr-FR'];
    }
  }
}

AudioLanguageMode audioLanguageModeFromStorage(String? value) {
  for (final mode in AudioLanguageMode.values) {
    if (mode.storageValue == value) return mode;
  }
  return AudioLanguageMode.mixed;
}
