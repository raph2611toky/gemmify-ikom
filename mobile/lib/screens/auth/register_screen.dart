import 'package:flutter/material.dart';

import '../../core/app_assets.dart';
import '../../models/audio_language_mode.dart';
import '../../services/local_auth_service.dart';
import '../../services/local_learning_database.dart';
import '../../theme/app_theme.dart';
import '../app_entry_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    this.initialLanguageMode = AudioLanguageMode.french,
  });

  final AudioLanguageMode initialLanguageMode;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _birthDate = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _school = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  int _step = 1;
  String _gender = '';
  String _accountType = 'Étudiant';
  String _level = 'CM1';
  final Set<String> _subjects = {'Mathématiques', 'Français'};
  bool _accepted = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  late AudioLanguageMode _languageMode;

  @override
  void initState() {
    super.initState();
    _languageMode = widget.initialLanguageMode.normalized;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _birthDate.dispose();
    _phone.dispose();
    _email.dispose();
    _school.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 12, now.month, now.day),
      firstDate: DateTime(1950),
      lastDate: now,
    );
    if (date == null) return;
    _birthDate.text =
        '${date.day.toString().padLeft(2, '0')} / ${date.month.toString().padLeft(2, '0')} / ${date.year}';
  }

  void _back() {
    if (_step == 1) {
      Navigator.pop(context);
    } else {
      setState(() => _step--);
    }
  }

  bool _validateStep() {
    if (_step == 1) {
      if (_firstName.text.trim().isEmpty ||
          _lastName.text.trim().isEmpty ||
          _birthDate.text.trim().isEmpty ||
          _gender.isEmpty ||
          _phone.text.trim().isEmpty) {
        _snack('Complète les informations personnelles obligatoires.');
        return false;
      }
      if (_password.text.length < 6) {
        _snack('Le mot de passe doit contenir au moins 6 caractères.');
        return false;
      }
      if (_password.text != _confirmPassword.text) {
        _snack('Les deux mots de passe ne correspondent pas.');
        return false;
      }
    }
    if (_step == 2 && _subjects.isEmpty) {
      _snack('Choisis au moins une matière.');
      return false;
    }
    return true;
  }

  void _next() {
    if (!_validateStep()) return;
    setState(() => _step = (_step + 1).clamp(1, 3).toInt());
  }

  Future<void> _createAccount() async {
    if (!_accepted) {
      _snack('Accepte les conditions d’utilisation pour continuer.');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final profile = <String, dynamic>{
      'first_name': _firstName.text.trim(),
      'last_name': _lastName.text.trim(),
      'birth_date': _birthDate.text.trim(),
      'gender': _gender,
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'account_type': _accountType,
      'subjects': _subjects.toList(growable: false),
      'level': _level,
      'school': _school.text.trim(),
    };

    final result = await LocalAuthService.instance.register(
      profile: profile,
      password: _password.text,
      remember: true,
    );

    if (!mounted) return;
    if (!result.success || result.user == null) {
      setState(() => _busy = false);
      _snack(result.message);
      return;
    }

    await LocalLearningDatabase.instance.enterAccountMode(
      userId: result.user!.id,
      profile: result.user!.profile,
      preferredLanguageMode: _languageMode,
    );
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AppEntryScreen()),
      (_) => false,
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.pageGlow),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 820 ||
                  constraints.maxWidth < 390;
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: _back,
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: AppTheme.accent,
                                size: 28,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              height: 40,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.lavender,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<AudioLanguageMode>(
                                  value: _languageMode,
                                  isDense: true,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: AppTheme.accent,
                                  ),
                                  items: selectableAudioLanguageModes
                                      .map(
                                        (mode) => DropdownMenuItem(
                                          value: mode,
                                          child: Text(mode.label),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: _busy
                                      ? null
                                      : (mode) {
                                          if (mode != null) {
                                            setState(() {
                                              _languageMode = mode.normalized;
                                            });
                                          }
                                        },
                                ),
                              ),
                            ),
                          ],
                        ),
                        SafeAssetImage(
                          path: AppAssets.logo,
                          width: compact ? 50 : 62,
                          height: compact ? 50 : 62,
                          fallback: const Icon(
                            Icons.school_rounded,
                            color: AppTheme.accent,
                            size: 50,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const _RegisterBrand(),
                        const Text(
                          'Créer un compte',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: compact ? 12 : 18),
                        _StepIndicator(currentStep: _step),
                        SizedBox(height: compact ? 14 : 20),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: switch (_step) {
                            1 => _personalStep(),
                            2 => _academicStep(),
                            _ => _confirmationStep(),
                          },
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => LoginScreen(
                                initialLanguageMode: _languageMode,
                              ),
                            ),
                          ),
                          child: const Text.rich(
                            TextSpan(
                              style: TextStyle(color: AppTheme.textSecondary),
                              children: [
                                TextSpan(text: 'Déjà un compte ?  '),
                                TextSpan(
                                  text: 'Se connecter',
                                  style: TextStyle(
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _personalStep() {
    return _stepCard(
      key: const ValueKey(1),
      icon: Icons.person_outline_rounded,
      title: 'Informations personnelles',
      subtitle: 'Étape 1 sur 3',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackFields = constraints.maxWidth < 390;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stackFields) ...[
                _field(
                  label: 'Prénom',
                  controller: _firstName,
                  hint: 'Votre prénom',
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 12),
                _field(
                  label: 'Nom',
                  controller: _lastName,
                  hint: 'Votre nom',
                  icon: Icons.person_outline_rounded,
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        label: 'Prénom',
                        controller: _firstName,
                        hint: 'Votre prénom',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        label: 'Nom',
                        controller: _lastName,
                        hint: 'Votre nom',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              const _FieldLabel('Date de naissance'),
              const SizedBox(height: 6),
              TextField(
                controller: _birthDate,
                readOnly: true,
                onTap: _pickBirthDate,
                decoration: const InputDecoration(
                  prefixIcon: Icon(
                    Icons.calendar_month_rounded,
                    color: AppTheme.accent,
                  ),
                  hintText: 'JJ / MM / AAAA',
                  suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ),
              const SizedBox(height: 12),
              const _FieldLabel('Sexe'),
              const SizedBox(height: 6),
              Row(
                children: ['Homme', 'Femme', 'Autre'].map((value) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: value == 'Autre' ? 0 : 7),
                      child: _SelectBox(
                        label: value,
                        selected: _gender == value,
                        onTap: () => setState(() => _gender = value),
                      ),
                    ),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 12),
              if (stackFields) ...[
                _field(
                  label: 'Téléphone',
                  controller: _phone,
                  hint: '+261 34 12 345 67',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                _field(
                  label: 'E-mail (facultatif)',
                  controller: _email,
                  hint: 'exemple@mail.com',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        label: 'Téléphone',
                        controller: _phone,
                        hint: '+261 34 12 345 67',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        label: 'E-mail',
                        controller: _email,
                        hint: 'exemple@mail.com',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              const _FieldLabel('Mot de passe'),
              const SizedBox(height: 6),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.lock_outline_rounded,
                    color: AppTheme.accent,
                  ),
                  hintText: 'Au moins 6 caractères',
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _FieldLabel('Confirmer le mot de passe'),
              const SizedBox(height: 6),
              TextField(
                controller: _confirmPassword,
                obscureText: _obscureConfirmation,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.verified_user_outlined,
                    color: AppTheme.accent,
                  ),
                  hintText: 'Répète le mot de passe',
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscureConfirmation = !_obscureConfirmation,
                    ),
                    icon: Icon(
                      _obscureConfirmation
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _GradientButton(label: 'Continuer', onPressed: _next),
            ],
          );
        },
      ),
    );
  }

  Widget _academicStep() {
    const availableSubjects = [
      'Mathématiques',
      'Physique-Chimie',
      'Français',
      'Anglais',
      'Sciences',
      'Histoire-Géographie',
    ];
    return _stepCard(
      key: const ValueKey(2),
      icon: Icons.school_outlined,
      title: 'Informations académiques',
      subtitle: 'Étape 2 sur 3',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Type de compte'),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _SelectBox(
                  label: 'Étudiant',
                  selected: _accountType == 'Étudiant',
                  onTap: () => setState(() => _accountType = 'Étudiant'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SelectBox(
                  label: 'Professeur',
                  selected: _accountType == 'Professeur',
                  onTap: () => setState(() => _accountType = 'Professeur'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Matière(s)'),
          const Text(
            'Plusieurs choix possibles',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppTheme.border),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: availableSubjects.map((subject) {
                final selected = _subjects.contains(subject);
                return FilterChip(
                  selected: selected,
                  label: Text(subject),
                  labelStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                  selectedColor: AppTheme.lavender,
                  checkmarkColor: AppTheme.accent,
                  side: const BorderSide(color: AppTheme.border),
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        _subjects.add(subject);
                      } else {
                        _subjects.remove(subject);
                      }
                    });
                  },
                );
              }).toList(growable: false),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 390;
              final levelField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('Classe ou niveau'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _level,
                    items: const [
                      'CP',
                      'CE1',
                      'CE2',
                      'CM1',
                      'CM2',
                      '6e',
                      '5e',
                      '4e',
                      '3e',
                      'Lycée',
                      'Université',
                    ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) setState(() => _level = value);
                    },
                  ),
                ],
              );
              final schoolField = _field(
                label: 'Établissement (facultatif)',
                controller: _school,
                hint: 'Nom de l’établissement',
                icon: Icons.account_balance_outlined,
              );
              if (stack) {
                return Column(
                  children: [
                    levelField,
                    const SizedBox(height: 12),
                    schoolField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: levelField),
                  const SizedBox(width: 10),
                  Expanded(child: schoolField),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.lavender,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.accent),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Ces informations servent uniquement à adapter les contenus au niveau de l’élève.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _OutlineButton(label: 'Retour', onPressed: _back),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GradientButton(label: 'Continuer', onPressed: _next),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _confirmationStep() {
    final rows = <(IconData, String, String)>[
      (
        Icons.person_outline_rounded,
        'Nom complet',
        '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim(),
      ),
      (Icons.calendar_month_outlined, 'Date de naissance', _birthDate.text),
      (Icons.wc_rounded, 'Sexe', _gender),
      (Icons.phone_outlined, 'Téléphone', _phone.text),
      (Icons.mail_outline_rounded, 'E-mail', _email.text.trim().isEmpty ? '—' : _email.text),
      (Icons.badge_outlined, 'Type de compte', _accountType),
      (Icons.menu_book_outlined, 'Matière(s)', _subjects.join(', ')),
      (Icons.bar_chart_rounded, 'Classe ou niveau', _level),
      (
        Icons.account_balance_outlined,
        'Établissement',
        _school.text.trim().isEmpty ? '—' : _school.text,
      ),
    ];

    return _stepCard(
      key: const ValueKey(3),
      icon: Icons.verified_user_outlined,
      title: 'Confirmation',
      subtitle: 'Étape 3 sur 3',
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Vérifie tes informations avant de créer le compte.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (row) => Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Icon(row.$1, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                    flex: 4,
                    child: Text(
                      row.$2,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: Text(
                      row.$3,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _accepted,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTheme.accent,
            dense: true,
            title: const Text(
              'J’accepte les conditions d’utilisation et la politique de confidentialité.',
              style: TextStyle(fontSize: 12.5, height: 1.3),
            ),
            onChanged: (value) => setState(() => _accepted = value ?? false),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _OutlineButton(label: 'Retour', onPressed: _back),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: _GradientButton(
                  label: _busy ? 'Création…' : 'Créer mon compte',
                  onPressed: _busy ? null : _createAccount,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepCard({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.lavender,
                ),
                child: Icon(icon, color: AppTheme.accent, size: 24),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppTheme.accent),
            hintText: hint,
          ),
        ),
      ],
    );
  }
}

class _RegisterBrand extends StatelessWidget {
  const _RegisterBrand();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: RichText(
        text: const TextSpan(
          style: TextStyle(fontSize: 33, fontWeight: FontWeight.w900),
          children: [
            TextSpan(
              text: 'Gemma ',
              style: TextStyle(color: AppTheme.textPrimary),
            ),
            TextSpan(
              text: 'Edu',
              style: TextStyle(color: AppTheme.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int currentStep;

  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (index) {
        if (index.isOdd) {
          final lineStep = (index + 1) ~/ 2;
          return Expanded(
            child: Container(
              height: 1.5,
              color: currentStep > lineStep
                  ? AppTheme.accent
                  : AppTheme.border,
            ),
          );
        }
        final step = index ~/ 2 + 1;
        final complete = step < currentStep;
        final active = step == currentStep;
        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: complete || active ? AppTheme.primaryGradient : null,
                color: complete || active ? null : const Color(0xFFEDEBF2),
              ),
              child: Center(
                child: complete
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : Text(
                        '$step',
                        style: TextStyle(
                          color: active ? Colors.white : AppTheme.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 84,
              child: Text(
                switch (step) {
                  1 => 'Informations\npersonnelles',
                  2 => 'Informations\nacadémiques',
                  _ => 'Confirmation',
                },
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  color: active || complete
                      ? AppTheme.accent
                      : AppTheme.textSecondary,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
    );
  }
}

class _SelectBox extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectBox({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.lavender : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 47),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: selected
                        ? AppTheme.accent
                        : AppTheme.textPrimary,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 5),
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.accent,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _GradientButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(15),
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _OutlineButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.accent, width: 1.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.accent,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
