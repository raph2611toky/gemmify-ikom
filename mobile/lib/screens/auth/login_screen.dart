import 'package:flutter/material.dart';

import '../../core/app_assets.dart';
import '../../models/audio_language_mode.dart';
import '../../services/local_auth_service.dart';
import '../../services/local_learning_database.dart';
import '../../theme/app_theme.dart';
import '../app_entry_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.initialLanguageMode = AudioLanguageMode.french,
  });

  final AudioLanguageMode initialLanguageMode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _remember = false;
  bool _busy = false;
  late AudioLanguageMode _languageMode;

  @override
  void initState() {
    super.initState();
    _languageMode = widget.initialLanguageMode.normalized;
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    final result = await LocalAuthService.instance.login(
      identifier: _loginController.text,
      password: _passwordController.text,
      remember: _remember,
    );

    if (!mounted) return;
    if (!result.success || result.user == null) {
      setState(() => _busy = false);
      _showMessage(result.message);
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _continueWithoutAccount() async {
    if (_busy) return;
    setState(() => _busy = true);
    await LocalLearningDatabase.instance.enterGuestMode(
      languageMode: _languageMode,
    );
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AppEntryScreen()),
      (_) => false,
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
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
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
                        SizedBox(height: compact ? 2 : 8),
                        SafeAssetImage(
                          path: AppAssets.logo,
                          width: compact ? 56 : 72,
                          height: compact ? 56 : 72,
                          fallback: const Icon(
                            Icons.school_rounded,
                            color: AppTheme.accent,
                            size: 58,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _LoginBrand(fontSize: compact ? 33 : 38),
                        const SizedBox(height: 3),
                        const Text(
                          'Ton compagnon d’apprentissage intelligent',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.lavender,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            '✨  Propulsé par Gemma',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 12 : 18),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.fromLTRB(
                            20,
                            compact ? 15 : 20,
                            18,
                            compact ? 15 : 20,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: AppTheme.softShadow,
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                const Text(
                                  'Se connecter',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                const Text(
                                  'Accède à ton espace d’apprentissage',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                TextFormField(
                                  controller: _loginController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(
                                      Icons.mail_rounded,
                                      color: AppTheme.accent,
                                    ),
                                    hintText: 'E-mail ou téléphone',
                                  ),
                                  validator: (value) =>
                                      value?.trim().isEmpty == true
                                          ? 'Saisis ton identifiant.'
                                          : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(
                                      Icons.lock_rounded,
                                      color: AppTheme.accent,
                                    ),
                                    hintText: 'Mot de passe',
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                        () => _obscure = !_obscure,
                                      ),
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                  validator: (value) =>
                                      (value?.length ?? 0) < 6
                                          ? 'Au moins 6 caractères.'
                                          : null,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: Checkbox(
                                        value: _remember,
                                        activeColor: AppTheme.accent,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        onChanged: (value) => setState(
                                          () => _remember = value ?? false,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Expanded(
                                      child: Text(
                                        'Se souvenir de moi',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _showMessage(
                                        'La récupération automatique n’est pas disponible hors ligne.',
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        minimumSize: const Size(0, 36),
                                      ),
                                      child: const Text(
                                        'Mot de passe oublié ?',
                                        style: TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: AppTheme.primaryGradient,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: ElevatedButton.icon(
                                      onPressed: _busy ? null : _submit,
                                      icon: const Icon(
                                        Icons.login_rounded,
                                        color: Colors.white,
                                      ),
                                      label: Text(
                                        _busy
                                            ? 'Connexion…'
                                            : 'Se connecter',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        disabledBackgroundColor:
                                            Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed:
                              _busy ? null : _continueWithoutAccount,
                          child: const Text(
                            'Continuer sans compte',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => RegisterScreen(
                                initialLanguageMode: _languageMode,
                              ),
                            ),
                          ),
                          child: const Text.rich(
                            TextSpan(
                              style: TextStyle(color: AppTheme.textSecondary),
                              children: [
                                TextSpan(text: 'Pas encore de compte ?  '),
                                TextSpan(
                                  text: 'Créer un compte',
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
}

class _LoginBrand extends StatelessWidget {
  final double fontSize;

  const _LoginBrand({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900),
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
