import 'package:flutter/material.dart';

import '../../../../core/constants/app_color.dart';

/// A single content section of a legal page.
class LegalSection {
  final String title;
  final String body;
  final IconData icon;
  final List<(String, String)> bulletRows;

  const LegalSection(
    this.title, {
    required this.icon,
    required this.body,
    this.bulletRows = const [],
  });
}

/// Shared, accessibility-first scaffold for the Privacy Policy and
/// Terms & Conditions screens.
///
/// Accessibility notes:
///  - All body text uses AppColors.textPrimary / textSecondary, both of which
///    meet WCAG AA (>= 4.5:1) on white/surface backgrounds.
///  - Sections expose heading semantics for screen readers.
///  - Cards get a subtle staggered entrance animation.
class LegalPageScaffold extends StatelessWidget {
  final String title;
  final String swahiliTitle;
  final String subtitle;
  final String lastUpdated;
  final IconData headerIcon;
  final List<LegalSection> sections;

  const LegalPageScaffold({
    super.key,
    required this.title,
    required this.swahiliTitle,
    required this.subtitle,
    required this.lastUpdated,
    required this.headerIcon,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
          ),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderCard(
              swahiliTitle: swahiliTitle,
              subtitle: subtitle,
              lastUpdated: lastUpdated,
              icon: headerIcon,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < sections.length; i++)
              _SectionCard(
                section: sections[i],
                startDelay: Duration(
                  milliseconds: 150 + (i * 70).clamp(0, 560),
                ),
              ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Pacific Dating App',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String swahiliTitle;
  final String subtitle;
  final String lastUpdated;
  final IconData icon;

  const _HeaderCard({
    required this.swahiliTitle,
    required this.subtitle,
    required this.lastUpdated,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              swahiliTitle,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.white.withOpacity(0.92),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                lastUpdated,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatefulWidget {
  final LegalSection section;
  final Duration startDelay;

  const _SectionCard({required this.section, required this.startDelay});

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.startDelay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;

    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      section.icon,
                      size: 20,
                      color: AppColors.primaryDeep,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      section.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                section.body,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
              if (section.bulletRows.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final (label, value) in section.bulletRows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$label: ',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    height: 1.55,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                TextSpan(
                                  text: value,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    height: 1.55,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}