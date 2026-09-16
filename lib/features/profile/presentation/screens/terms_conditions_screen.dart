import 'package:flutter/material.dart';

import '../widgets/legal_page_scaffold.dart';

/// Terms & Conditions for Pacific Dating App.
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  static const List<LegalSection> _sections = [
    LegalSection(
      '1. Acceptance of Terms',
      icon: Icons.handshake_rounded,
      body:
          'By using Pacific Dating App you agree to these Terms & '
          'Conditions and our Privacy Policy. Do not use this app unless '
          'you accept these terms. These terms are legally binding as a '
          'contract between you and us.',
    ),
    LegalSection(
      '2. Eligibility (18+)',
      icon: Icons.event_available_rounded,
      body:
          'You must be 18 YEARS OR OLDER to use this app. By creating an '
          'account you confirm that your age is real and that you are '
          'allowed to enter into a contract. One account per person only — '
          'fake accounts or impersonating someone else is not allowed.',
    ),
    LegalSection(
      '3. Your Account',
      icon: Icons.account_circle_rounded,
      body:
          'You are responsible for protecting your password and the '
          'security of your phone. Your profile details (name, age, '
          'photos) must be TRUE. Providing false information is a breach '
          'of these terms and may lead to your account being deleted.',
    ),
    LegalSection(
      '4. Community Conduct',
      icon: Icons.diversity_3_rounded,
      body:
          'To keep Pacific safe for everyone, the following are not '
          'allowed: disrespecting others, harassment, hate speech, nude '
          'or sexual images, fraud/scams, spam, asking for money, '
          'stalking, or any unlawful behavior. You can report and block '
          'any user from their profile or chat, and we may delete '
          'accounts that break the rules.',
    ),
    LegalSection(
      '5. Your Content',
      icon: Icons.photo_camera_rounded,
      body:
          'You own the content you upload (photos, bio, voice notes). By '
          'uploading, you grant us a limited license to store and deliver '
          'it to users you interact with inside the app only — we do not '
          'sell or use your content outside the app. Do not upload other '
          'people\'s content without their permission. We may remove '
          'content that breaches these terms.',
    ),
    LegalSection(
      '6. Coins, Gifts & VIP • Virtual Items & Purchases',
      icon: Icons.diamond_rounded,
      body:
          'Coins, gifts and VIP badges are virtual items of this app only '
          '— they have no real-money value and cannot be exchanged for '
          'cash or withdrawn from the app. These purchases are '
          'non-refundable except where required by law. Payments are '
          'handled by Google Play / App Store; billing questions follow '
          'their policies. Prices may change at any time.',
    ),
    LegalSection(
      '7. Voice & Video Calls',
      icon: Icons.videocam_rounded,
      body:
          'Voice and video calls inside the app work over the internet '
          '(data) — data charges are from your mobile network provider. '
          'Calls must not be used for emergencies; in an emergency use '
          'your country\'s emergency numbers. Recording a call without '
          'the other person\'s consent may be unlawful and breaches '
          'these terms.',
    ),
    LegalSection(
      '8. Safety',
      icon: Icons.health_and_safety_rounded,
      body:
          'We do not fully verify every user\'s identity. Please be '
          'careful: meet new people in public places, tell a friend or '
          'relative, and never share financial details with people you '
          'have only met online. Report any inappropriate behavior via '
          'the report/block buttons.',
    ),
    LegalSection(
      '9. Availability & Termination',
      icon: Icons.power_settings_new_rounded,
      body:
          'We strive to keep the app running without interruption, but we '
          'do not guarantee it will always be available without errors or '
          'downtime. We may suspend or delete accounts that breach these '
          'terms. You may also stop using the app at any time — if you '
          'want your data fully deleted, follow the steps in the Privacy '
          'Policy.',
    ),
    LegalSection(
      '10. Disclaimers',
      icon: Icons.gavel_rounded,
      body:
          'The app is provided "AS IS". We make no promises about the '
          'outcome of relationships or matches, and we are not liable for '
          'misuse of the app, other users\' content, or events that happen '
          'outside the app. To the maximum extent permitted by law, our '
          'total liability is limited to the amount you paid to use the '
          'app (which is normally free).',
    ),
    LegalSection(
      '11. Changes to These Terms',
      icon: Icons.update_rounded,
      body:
          'We may update these terms from time to time. Changes will be '
          'published inside the app; if you keep using the app after '
          'changes take effect, that means you accept the new version.',
    ),
    LegalSection(
      '12. Contact',
      icon: Icons.support_agent_rounded,
      body:
          'Questions about these terms should be sent to our customer '
          'support team via the in-app support (Support).',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LegalPageScaffold(
      title: 'Terms & Conditions',
      headerTitle: 'Terms & Conditions',
      subtitle:
          'Welcome to Pacific! These terms explain the rules for using the '
          'app safely for everyone — please read them carefully.',
      lastUpdated: 'Last updated: June 2026',
      headerIcon: Icons.description_rounded,
      sections: _sections,
    );
  }
}