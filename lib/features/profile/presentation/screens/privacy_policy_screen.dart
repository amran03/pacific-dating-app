import 'package:flutter/material.dart';

import '../widgets/legal_page_scaffold.dart';

/// Privacy Policy — rewritten to follow DATA MINIMIZATION:
/// we only connect/collect the data the app actually needs, we do NO
/// tracking, and the app contains NO third-party embeds.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const List<LegalSection> _sections = [
    LegalSection(
      '1. Data We Collect (Data Minimization)',
      icon: Icons.folder_shared_rounded,
      body:
          'We follow the principle of DATA MINIMIZATION — we connect/store '
          'only the SMALL amount of data needed for the app to work. We '
          'collect the following, and each item has a specific purpose:',
      bulletRows: [
        (
          'Account',
          'Name, age/date of birth, gender, profile photos, bio and '
              'interests — used to show your profile to matches.',
        ),
        (
          'Contact',
          'Phone number / email — for account security and sign-in only.',
        ),
        (
          'Location (optional)',
          'Your approximate location is collected ONLY when you enable '
              'location. Used only to match you with people nearby.',
        ),
        (
          'Messages',
          'Messages and voice notes you send — stored so your '
              'conversations stay in sync between your phone and the '
              'other person\'s.',
        ),
        (
          'Push token',
          'Notification token (FCM) — to receive match and new-message '
              'notifications.',
        ),
        (
          'Purchases',
          'Your coins balance and VIP badge status — for the coins, '
              'gifts and VIP features inside the app.',
        ),
      ],
    ),
    LegalSection(
      '2. No Tracking or Advertising',
      icon: Icons.do_not_disturb_on_rounded,
      body:
          'This app contains NO tracking tools of any kind. No analytics '
          'SDK, no advertising SDK, and we never use your advertising ID. '
          'We do not monitor your use of other apps, we do not sell or '
          'share your data with data brokers, and we do not build any '
          'advertising profile.',
    ),
    LegalSection(
      '3. No Third-Party Embeds',
      icon: Icons.extension_off_rounded,
      body:
          'Every screen of this app is built with our own code — there '
          'are no webviews, iframes, external videos, social widgets '
          '(e.g. "Like" buttons), or third-party scripts running inside '
          'the app. Because of that, no third party can place trackers '
          'inside our app.',
    ),
    LegalSection(
      '4. Service Providers (Infrastructure Only)',
      icon: Icons.cloud_rounded,
      body:
          'We use Google Firebase purely as the infrastructure to run the '
          'app. These are the only third-party services that touch your '
          'data:',
      bulletRows: [
        ('Firebase Auth', 'Verifies your account when you sign in.'),
        ('Cloud Database', 'Stores your profile, matches and messages.'),
        ('Cloud Storage', 'Stores the photos and voice notes you upload.'),
        ('Push Messaging', 'Delivers match and new-message notifications.'),
      ],
    ),
    LegalSection(
      '5. How We Use Your Data',
      icon: Icons.settings_rounded,
      body:
          'Your data is used FOR THIS APP ONLY: showing you relevant '
          'matches, delivering chats and voice notes, sending you '
          'notifications, managing coins/gifts/VIP, and preventing abuse '
          '(spam, scams, lies). We do not use your data for advertising '
          'or any other unnecessary purpose.',
    ),
    LegalSection(
      '6. Location Data',
      icon: Icons.location_on_outlined,
      body:
          'Location is OPTIONAL. If you enable location in the app, we '
          'store your APPROXIMATE location (coordinates) only to find '
          'matches near you. You can turn it off at any time from your '
          'phone settings, and we do not track where you have been (no '
          'location history).',
    ),
    LegalSection(
      '7. Security',
      icon: Icons.security_rounded,
      body:
          'Your data is stored on secure cloud infrastructure with '
          'encryption in transit. We never store your card details — '
          'when you buy coins or VIP, payments are handled by Google '
          'Play / App Store and we only receive the purchase '
          'confirmation.',
    ),
    LegalSection(
      '8. Retention & Deletion',
      icon: Icons.auto_delete_rounded,
      body:
          'We keep your data only while your account is active. If you '
          'request account deletion (or delete it yourself from '
          'Settings), your profile, photos and messages are removed. '
          'Your notification token is also deleted so you no longer '
          'receive notifications.',
    ),
    LegalSection(
      '9. Your Rights',
      icon: Icons.verified_user_rounded,
      body:
          'You have the right to: see your data (your profile), correct '
          'inaccurate data via Edit Profile, delete your account, turn '
          'off location and notifications from your phone settings, and '
          'ask anything about your data. We do not sell your data and we '
          'do not transfer it to providers other than the infrastructure '
          'described above.',
    ),
    LegalSection(
      '10. Children',
      icon: Icons.child_care_rounded,
      body:
          'This app is for people aged 18+ ONLY. We do not knowingly '
          'collect data from children. If you become aware of an account '
          'belonging to someone under 18, please report it to our team.',
    ),
    LegalSection(
      '11. Contact',
      icon: Icons.support_agent_rounded,
      body:
          'If you have any question about this privacy policy, or you '
          'want your data deleted, contact our customer support team via '
          'the in-app support (Support).',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LegalPageScaffold(
      title: 'Privacy Policy',
      headerTitle: 'Privacy Policy',
      subtitle:
          'We respect your privacy. We collect only the SMALL amount of '
          'data needed, we do no tracking, and there are no third-party '
          'embeds inside the app.',
      lastUpdated: 'Last updated: June 2026',
      headerIcon: Icons.privacy_tip_rounded,
      sections: _sections,
    );
  }
}