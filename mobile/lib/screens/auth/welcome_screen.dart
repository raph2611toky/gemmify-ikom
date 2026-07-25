import 'package:flutter/material.dart';

import '../../core/app_assets.dart';
import '../../services/local_learning_database.dart';
import '../../theme/app_theme.dart';
import '../app_entry_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String _language = 'Français';
  bool _busy = false;

  Future<void> _continueWithoutAccount() async {
    if (_busy) return;
    setState(() => _busy = true);
    await LocalLearningDatabase.instance.enterGuestMode();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AppEntryScreen()),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
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
              final heroHeight = compact ? 168.0 : 220.0;
              final logoSize = compact ? 62.0 : 78.0;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: _LanguagePicker(
                            value: _language,
                            onChanged: (value) =>
                                setState(() => _language = value),
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 14),
                        SafeAssetImage(
                          path: AppAssets.logo,
                          width: logoSize,
                          height: logoSize,
                          fallback: const Icon(
                            Icons.school_rounded,
                            color: AppTheme.accent,
                            size: 62,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _BrandTitle(fontSize: compact ? 34 : 39),
                        const SizedBox(height: 4),
                        const Text(
                          'Ton compagnon d’apprentissage intelligent',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const _PoweredBadge(),
                        SizedBox(height: compact ? 8 : 12),
                        SafeAssetImage(
                          path: AppAssets.hero,
                          width: double.infinity,
                          height: heroHeight,
                          fit: BoxFit.contain,
                          fallback: const Icon(
                            Icons.auto_stories_rounded,
                            color: AppTheme.accent,
                            size: 130,
                          ),
                        ),
                        SizedBox(height: compact ? 7 : 12),
                        const Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontSize: 17.5,
                              height: 1.25,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary,
                            ),
                            children: [
                              TextSpan(text: 'Apprends, comprends et progresse\n'),
                              TextSpan(text: 'à ton rythme avec '),
                              TextSpan(
                                text: 'l’IA.',
                                style: TextStyle(color: AppTheme.accent),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Des explications claires, des exercices adaptés et un suivi personnalisé.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        SizedBox(height: compact ? 14 : 20),
                        _PrimaryAuthButton(
                          icon: Icons.login_rounded,
                          label: 'Se connecter',
                          onPressed: () => _open(const LoginScreen()),
                        ),
                        const SizedBox(height: 10),
                        _OutlineAuthButton(
                          icon: Icons.person_add_alt_1_rounded,
                          label: 'Créer un compte',
                          onPressed: () => _open(const RegisterScreen()),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: _busy ? null : _continueWithoutAccount,
                          child: Text(
                            _busy
                                ? 'Ouverture…'
                                : 'Continuer sans compte',
                            style: const TextStyle(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Text(
                          'En mode invité, les discussions restent seulement pendant cette ouverture et aucune progression n’est enregistrée.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.35,
                            color: AppTheme.textSecondary,
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

class _BrandTitle extends StatelessWidget {
  final double fontSize;

  const _BrandTitle({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: fontSize,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
          children: const [
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

class _PoweredBadge extends StatelessWidget {
  const _PoweredBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.lavender,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
          children: [
            TextSpan(text: '✨  Propulsé par '),
            TextSpan(
              text: 'Gemma',
              style: TextStyle(color: AppTheme.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _LanguagePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.lavender,
        borderRadius: BorderRadius.circular(15),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppTheme.accent,
          ),
          style: const TextStyle(
            color: AppTheme.accent,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
          items: const [
            DropdownMenuItem(value: 'Français', child: Text('Français')),
            DropdownMenuItem(value: 'Malagasy', child: Text('Malagasy')),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

class _PrimaryAuthButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _PrimaryAuthButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.softShadow,
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white, size: 22),
          label: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineAuthButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _OutlineAuthButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: AppTheme.accent, size: 22),
        label: Text(
          label,
          style: const TextStyle(
            color: AppTheme.accent,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.accent, width: 1.4),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
