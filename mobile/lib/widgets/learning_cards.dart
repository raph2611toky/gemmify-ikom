import 'package:flutter/material.dart';

import '../models/ai_tutor_response.dart';
import '../theme/app_theme.dart';

class LearningCard extends StatelessWidget {
  final AiTutorResponse response;

  const LearningCard({super.key, required this.response});

  @override
  Widget build(BuildContext context) {
    return switch (response.cardType) {
      TutorCardType.understanding => _UnderstandingCard(response: response),
      TutorCardType.activityResult => _ActivityResultCard(response: response),
      TutorCardType.progression => _ProgressionCard(response: response),
      TutorCardType.none => const SizedBox.shrink(),
    };
  }
}

class _UnderstandingCard extends StatelessWidget {
  final AiTutorResponse response;

  const _UnderstandingCard({required this.response});

  @override
  Widget build(BuildContext context) {
    final skills = response.skills;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.bar_chart_rounded, title: 'Ta compréhension'),
          const SizedBox(height: 13),
          const Divider(),
          if (skills.isEmpty)
            _SkillRow(
              skill: TutorSkill(
                id: 'global',
                label: response.topic.isEmpty
                    ? 'Compréhension du cours'
                    : response.topic,
                mastery: response.understanding,
                status: response.understanding >= 80
                    ? 'mastered'
                    : response.understanding >= 45
                        ? 'in_progress'
                        : 'discover',
              ),
            )
          else
            ...skills.map(
              (skill) => Column(
                children: [
                  _SkillRow(skill: skill),
                  if (skill != skills.last) const Divider(height: 1),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityResultCard extends StatelessWidget {
  final AiTutorResponse response;

  const _ActivityResultCard({required this.response});

  @override
  Widget build(BuildContext context) {
    final score = response.score ?? 0;
    final maxScore = response.maxScore ?? 5;
    final skills = response.skills;
    return _CardShell(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text('🎉', style: TextStyle(fontSize: 27)),
              SizedBox(width: 9),
              Flexible(
                child: Text(
                  'Activité terminée !',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            decoration: BoxDecoration(
              color: AppTheme.softLavender,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                const Text(
                  'Résultat',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('⭐', style: TextStyle(fontSize: 48)),
                    const SizedBox(width: 12),
                    Text(
                      '$score',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 50,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '/$maxScore',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text.rich(
                  TextSpan(
                    text: score >= (maxScore * .8).round()
                        ? 'Très bien '
                        : 'Continue tes efforts ',
                    children: const [
                      TextSpan(
                        text: 'Leite',
                        style: TextStyle(color: AppTheme.accent),
                      ),
                      TextSpan(text: ' !'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(15, 15, 15, 9),
            decoration: BoxDecoration(
              color: AppTheme.softLavender,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                const Text(
                  'Compétences travaillées',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                if (skills.isEmpty)
                  _SkillRow(
                    skill: TutorSkill(
                      id: 'activity',
                      label: response.topic.isEmpty
                          ? 'Compétence du cours'
                          : response.topic,
                      mastery: response.understanding,
                      status: response.understanding >= 80
                          ? 'mastered'
                          : 'in_progress',
                    ),
                  )
                else
                  ...skills.map(
                    (skill) => Column(
                      children: [
                        _SkillRow(skill: skill, compact: true),
                        if (skill != skills.last) const Divider(height: 1),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (response.xp > 0) ...[
            const SizedBox(height: 17),
            Text.rich(
              TextSpan(
                text: 'Tu as gagné ',
                children: [
                  TextSpan(
                    text: '+${response.xp} XP',
                    style: const TextStyle(color: AppTheme.accent),
                  ),
                  const TextSpan(text: ' 🏅'),
                ],
              ),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressionCard extends StatelessWidget {
  final AiTutorResponse response;

  const _ProgressionCard({required this.response});

  @override
  Widget build(BuildContext context) {
    final currentXp = response.currentXp;
    final nextXp = response.nextLevelXp <= currentXp
        ? currentXp + 100
        : response.nextLevelXp;
    final progress = nextXp <= 0 ? 0.0 : (currentXp / nextXp).clamp(0.0, 1.0);
    final skills = response.skills;

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.show_chart_rounded, title: 'Ta progression'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppTheme.softLavender,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE2D5FF)),
            ),
            child: Row(
              children: [
                Container(
                  width: 105,
                  height: 105,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9DEFF),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Image.asset(
                    'assets/images/mascot.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.school_rounded,
                      size: 60,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 17),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Niveau actuel',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        response.levelLabel.isEmpty
                            ? 'Exploratrice 1'
                            : response.levelLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 21,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 13),
                      Text.rich(
                        TextSpan(
                          text: '$currentXp',
                          style: const TextStyle(color: AppTheme.accent),
                          children: [
                            TextSpan(
                              text: ' / $nextXp XP',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: progress,
                          backgroundColor: const Color(0xFFDFD3FA),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _MetricBox(
                  icon: '🔥',
                  title: 'Séries',
                  value: response.streakDays > 0
                      ? '${response.streakDays} jours consécutifs'
                      : 'Commence aujourd’hui',
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: _MetricBox(
                  icon: '🕘',
                  title: 'Temps d’apprentissage',
                  value: response.learningTime.isEmpty
                      ? 'Cette semaine'
                      : response.learningTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        response.subject.isEmpty
                            ? 'Progression générale'
                            : response.subject,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${response.understanding}%',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: (response.understanding / 100).clamp(0.0, 1.0),
                    backgroundColor: const Color(0xFFE5DBFA),
                  ),
                ),
                const SizedBox(height: 10),
                if (skills.isEmpty)
                  _SkillRow(
                    skill: TutorSkill(
                      id: 'global',
                      label: response.topic.isEmpty
                          ? 'Apprentissage en cours'
                          : response.topic,
                      mastery: response.understanding,
                      status: response.understanding >= 80
                          ? 'mastered'
                          : 'in_progress',
                    ),
                    compact: true,
                  )
                else
                  ...skills.map(
                    (skill) => Column(
                      children: [
                        _SkillRow(skill: skill, compact: true),
                        if (skill != skills.last) const Divider(height: 1),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;

  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _CardTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: AppTheme.lavender,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.accent, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _SkillRow extends StatelessWidget {
  final TutorSkill skill;
  final bool compact;

  const _SkillRow({required this.skill, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final appearance = _statusAppearance(skill.status);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 13),
      child: Row(
        children: [
          Container(
            width: compact ? 31 : 39,
            height: compact ? 31 : 39,
            decoration: BoxDecoration(
              color: appearance.color.withOpacity(.13),
              shape: BoxShape.circle,
            ),
            child: Icon(
              appearance.icon,
              color: appearance.color,
              size: compact ? 19 : 23,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              skill.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: compact ? 13 : 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              appearance.label,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appearance.color,
                fontSize: compact ? 11.5 : 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Icon(appearance.trailingIcon, color: appearance.color, size: 21),
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  final String icon;
  final String title;
  final String value;

  const _MetricBox({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 19)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusAppearance {
  final Color color;
  final IconData icon;
  final IconData trailingIcon;
  final String label;

  const _StatusAppearance({
    required this.color,
    required this.icon,
    required this.trailingIcon,
    required this.label,
  });
}

_StatusAppearance _statusAppearance(String status) {
  switch (status) {
    case 'mastered':
      return const _StatusAppearance(
        color: Color(0xFF20B85A),
        icon: Icons.check_rounded,
        trailingIcon: Icons.check_circle_rounded,
        label: 'Maîtrisé',
      );
    case 'in_progress':
      return const _StatusAppearance(
        color: Color(0xFFFFA800),
        icon: Icons.menu_book_rounded,
        trailingIcon: Icons.circle,
        label: 'En cours',
      );
    case 'reinforce':
      return const _StatusAppearance(
        color: Color(0xFFFF7A00),
        icon: Icons.trending_up_rounded,
        trailingIcon: Icons.arrow_circle_up_rounded,
        label: 'À renforcer',
      );
    default:
      return const _StatusAppearance(
        color: Color(0xFF7B6CA6),
        icon: Icons.calculate_rounded,
        trailingIcon: Icons.lock_rounded,
        label: 'À découvrir',
      );
  }
}
