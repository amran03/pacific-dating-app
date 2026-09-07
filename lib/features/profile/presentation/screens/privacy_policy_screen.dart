import 'package:flutter/material.dart';

import '../widgets/legal_page_scaffold.dart';

/// Privacy Policy — rewritten to follow DATA MINIMIZATION:
/// we only connect/collect the data the app actually needs, we do NO
/// tracking, and the app contains NO third-party embeds.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const List<LegalSection> _sections = [
    LegalSection(
      '1. Taarifa Tunazokusanya • Data We Collect (Data Minimization)',
      icon: Icons.folder_shared_rounded,
      body:
          'Tunafuata kanuni ya DATA MINIMIZATION — tunaunganisha/kuhifadhi '
          'taarifa CHACHE TU zinazohitajika ili app ifanye kazi. Tunakusanya '
          'yafuatayo, na kila kipengele kina sababu yake maalum:',
      bulletRows: [
        (
          'Account',
          'Jina, umri/tarehe ya kuzaliwa, jinsia, picha za profile, bio na '
              'interests — hutumika kuonyesha profile yako kwa matches.',
        ),
        (
          'Contact',
          'Namba ya simu / barua pepe — kwa usalama wa akaunti na kuingia tu.',
        ),
        (
          'Location (hiari)',
          'Eneo lako la takribani LINAKUSANYWA TU ukiwasha location. '
              'Hutumika kwa matching ya watu walio karibu nawe pekee.',
        ),
        (
          'Messages',
          'Jumbe na voice notes unazotuma — huhifadhiwa ili mazungumzo '
              'yako yawe sawa kwenye simu yako na ya mwenzako.',
        ),
        (
          'Push token',
          'Token ya noti (FCM) — ili kupokea noti za match na jumbe mpya.',
        ),
        (
          'Purchases',
          'Hali ya coins na VIP badge yako — kwa ajili ya vitufe vya coins, '
              'gifts na VIP ndani ya app.',
        ),
      ],
    ),
    LegalSection(
      '2. Hatufanyi Tracking • No Tracking or Advertising',
      icon: Icons.do_not_disturb_on_rounded,
      body:
          'App hii HAINA vifaa vyovyote vya kufuatilia (tracking). Hakuna '
          'analytics SDK, hakuna advertising SDK, hakuna matumizi ya '
          'advertising ID yako. Hatufuatilii matumizi yako ya app nyingine, '
          'hatuuzi au kushiriki data zako na data brokers, na hatengenezi '
          'profile yoyote ya matangazo.',
    ),
    LegalSection(
      '3. Hakuna Embeds za Watu Wengine • No Third-Party Embeds',
      icon: Icons.extension_off_rounded,
      body:
          'Kila screen ya app hii imejengwa kwa code yetu wenyewe — hakuna '
          'webviews, iframes, video za nje, social widgets (mfano "Like" '
          'buttons), au scripts za watu wengine zinazoendesha ndani ya app. '
          'Kwa sababu hiyo, hakuna mtu wa tatu anayeweza kuweka trackers '
          'ndani ya app yetu.',
    ),
    LegalSection(
      '4. Huduma za Msingi • Service Providers (Infrastructure Only)',
      icon: Icons.cloud_rounded,
      body:
          'Tunatumia Google Firebase kama miundombinu tu ya kuendesha app. '
          'Hii ndiyo huduma pekee za mtu wa tatu zinazogusa data zako:',
      bulletRows: [
        ('Firebase Auth', 'Kuthibitisha akaunti yako unapoingia.'),
        ('Cloud Firestore', 'Kuhifadhi profile, matches na jumbe zako.'),
        ('Firebase Storage', 'Kuhifadhi picha na voice notes unazopakia.'),
        ('Firebase Messaging', 'Kutuma noti za match na jumbe mpya.'),
      ],
    ),
    LegalSection(
      '5. Jinsi Tunavyotumia Data Zako • How We Use Your Data',
      icon: Icons.settings_rounded,
      body:
          'Data zako zinatumika KWA APP HII PEKEE: kukuonyesha matches '
          'zinazofaa, kufanya chat na voice notes zifike, kukutumia noti, '
          'kudhibiti coins/gifts/VIP, na kuzuia matumizi mabaya (spam, '
          'scams, uwongo). Hatutumii data zako kwa ajili ya matangazo wala '
          'kwa madhumuni mengine yasiyo na lazima.',
    ),
    LegalSection(
      '6. Eneo (Location) • Location Data',
      icon: Icons.location_on_outlined,
      body:
          'Location ni HIARI. Ukiwasha location kwenye app, tunahifadhi '
          'eneo lako la TAKRIBANI (coordinates) kwa ajili ya kukupatia '
          'matches walio karibu nawe tu. Unaweza kuizima wakati wowote '
          'kutoka kwenye settings za simu yako, na hatufuatilii mahali '
          'ulipokwenda (hakuna location history).',
    ),
    LegalSection(
      '7. Usalama • Security',
      icon: Icons.security_rounded,
      body:
          'Data zako huhifadhiwa kwenye miundombinu ya Firebase (Google '
          'Cloud) yenye usimbaji fiche wa data inayosafiri (encryption in '
          'transit). Hatuhifadhi taarifa za kadi yako — unaponunua coins au '
          'VIP, malipo yanashughulikiwa na Google Play / App Store, sisi '
          'tunapokea uthibitisho wa ununulio tu.',
    ),
    LegalSection(
      '8. Kuhifadhi na Kufuta Data • Retention & Deletion',
      icon: Icons.auto_delete_rounded,
      body:
          'Tunahifadhi data zako tu alivyo hai akaunti yako. Ukiomba '
          'kufuta akaunti yako (au unafuta mwenyewe kutoka Settings), '
          'profile yako, picha zako na jumbe zako zinaondolewa. Noti token '
          'yako inafutwa pia ili usipokee noti tena.',
    ),
    LegalSection(
      '9. Haki Zako • Your Rights',
      icon: Icons.verified_user_rounded,
      body:
          'Una haki ya: kuona data zako (profile yako), kurekebisha data '
          'zisizo sahihi kupitia Edit Profile, kufuta akaunti yako, '
          'kuzima location na noti kutoka settings za simu, na kuuliza '
          'chochote kuhusu data zako. Hatuuzi data zako na hatuhamishi '
          'kwa watoa huduma isipokuwa Firebase iliyoelezwa hapo juu.',
    ),
    LegalSection(
      '10. Watoto • Children',
      icon: Icons.child_care_rounded,
      body:
          'App hii ni kwa watu wenye umri wa miaka 18+ TU. Hatukusanyi '
          'kwa makusudi taarifa za watoto. Ukitambua akaunti ya mtu chini '
          'ya miaka 18, tafadhali ripoti kwa timu yetu.',
    ),
    LegalSection(
      '11. Mawasiliano • Contact',
      icon: Icons.support_agent_rounded,
      body:
          'Kama una swali lolote kuhusu sera hii ya faragha, au unataka '
          'data yako ifutwe, wasiliana na timu yetu ya huduma kwa wateja '
          'kupitia msaada wa ndani ya app (Support).',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LegalPageScaffold(
      title: 'Privacy Policy',
      swahiliTitle: 'Sera ya Faragha',
      subtitle:
          'Tunathamini faragha yako. Tunaunganisha data CHACHE TU '
          'zinazohitajika, hatufanyi tracking, na hakuna embeds za watu '
          'wengine ndani ya app.',
      lastUpdated: 'Imesasishwa • Last updated: June 2026',
      headerIcon: Icons.privacy_tip_rounded,
      sections: _sections,
    );
  }
}