import 'package:flutter/material.dart';

import '../widgets/legal_page_scaffold.dart';

/// Terms & Conditions for Pacific Dating App.
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  static const List<LegalSection> _sections = [
    LegalSection(
      '1. Makubaliano • Acceptance of Terms',
      icon: Icons.handshake_rounded,
      body:
          'Kwa kutumia Pacific Dating App unakubali Masharti haya ya '
          'Huduma (Terms & Conditions) na Sera yetu ya Faragha. Usitumie '
          'app hii ukiwa hujakubali masharti haya. Masharti haya yana '
          'nguvu kisheria kama mkataba kati yako na sisi.',
    ),
    LegalSection(
      '2. Ustahiki • Eligibility (18+)',
      icon: Icons.event_available_rounded,
      body:
          'Lazima uwe na umri wa MIAKA 18 AU ZAIDI kutumia app hii. Kwa '
          'kufungua akaunti unathibitisha kuwa umri wako ni wa kweli na '
          'unaniruhusu kuingia mkataba. Akaunti moja kwa mtu mmoja tu — '
          'hairuhusiwi kufungua akaunti za bandia au kuigiza kuwa wewe ni '
          'mtu mwingine.',
    ),
    LegalSection(
      '3. Taarifa za Akaunti • Your Account',
      icon: Icons.account_circle_rounded,
      body:
          'Ni wajibu wao kulinda password yako na usalama wa simu yako. '
          'Taarifa za profile zako (jina, umri, picha) lazima ziwe za '
          'KWELI. Kuweka taarifa za uongo ni kukiolera masharti haya na '
          'kunaweza pelekea akaunti yako kufutwa.',
    ),
    LegalSection(
      '4. Maadili • Community Conduct',
      icon: Icons.diversity_3_rounded,
      body:
          'Ili Pacific iwe salama kwa wote, hairuhusiwi: kukosea wengine '
          'heshima, unyanyasaji (harassment), maneno ya chuki, picha '
          'za uchi au za ngono, udanganyifu/scams, spam, kuomba pesa, '
          'kuwinda watu (stalking), au vitendo vyovyote vya kinyume na '
          'sheria. Unaweza kuripoti na kuzuia mtumiaji yeyote kutoka '
          'profile au chat yake, na tunaweza kufuta akaunti inayokiuka.',
    ),
    LegalSection(
      '5. Maudhui Yako • Your Content',
      icon: Icons.photo_camera_rounded,
      body:
          'Unamiliki maudhui unayopakia (picha, bio, voice notes). Kwa '
          'kuyapakia, unatupa lesi ndogo ya kuyahifadhi na kuyapeleka '
          'kwa watumiaji wanaokushirikiana nayo ndani ya app tu — hatuuzi '
          'maudhui yako wala hatuyatumii nje ya app. Usipakie maudhui '
          'ya watu wengine bila ruhusa yao. Tunaweza kuondoa maudhui '
          'yakiwa yamekiuka masharti haya.',
    ),
    LegalSection(
      '6. Coins, Gifts na VIP • Virtual Items & Purchases',
      icon: Icons.diamond_rounded,
      body:
          'Coins, gifts na VIP badges ni vitu pepe (virtual) vya app hii '
          'tu — havina thamani ya pesa halisi na haziwezi kubadilishwa '
          'kuwa pesa au kutolewa nje ya app. Vipengele hivi hazirudishwi '
          '(non-refundable) isipokuwa pale sheria inavyolazimu. Malipo '
          'yanashughulikiwa na Google Play / App Store; maswali ya '
          'malipo yafuate sheria zao. Bei zinaweza kubadilishwa kwa '
          'taarifa.',
    ),
    LegalSection(
      '7. Simu na Video Calls • Voice & Video Calls',
      icon: Icons.videocam_rounded,
      body:
          'Simu za sauti na video ndani ya app hufanya kazi kupitia '
          'internet (data) — gharama za data ni za mtoa huduma wako wa '
          'mtandao. Calls hazitumiwi kwa dharura; kwa dharura tumia '
          'namba za dharura za nchi yako. Kurekodi call bila idhini ya '
          'mwenzako kunaweza kuwa kukiolera sheria na masharti haya.',
    ),
    LegalSection(
      '8. Usalama wa Miadi • Safety',
      icon: Icons.health_and_safety_rounded,
      body:
          'Hatuthibitishi kikamilifu utambulisho wa kila mtumiaji. Tuweke '
          'tahadhari: kutana na mtu mpya mahali pa hadhara, mjulishe '
          'rafiki au ndugu, na usitumie taarifa za kifedha na watu '
          'uliowaonja mtandaoni. Ripoti tabia yoyote ya kupendeza '
          'kupitia vitufe vya report/block.',
    ),
    LegalSection(
      '9. Upatikanaji na Kusimamisha Huduma • Availability & Termination',
      icon: Icons.power_settings_new_rounded,
      body:
          'Tunajitahidi app ifanye kazi bila kukoma, lakini hatuahidi '
          'kuwa itapatikana bila makosa au kusimama. Tunaweza kusimamisha '
          'au kufuta akaunti inayokiuka masharti haya. Wewe pia unaweza '
          'kuacha kutumia app wakati wowote — ukitaka data yako ifutwe '
          'kabisa, fuata taratibu za Sera ya Faragha.',
    ),
    LegalSection(
      '10. Dhana za Kisheria • Disclaimers',
      icon: Icons.gavel_rounded,
      body:
          'App inatolewa "KAMA ILIVYO" (AS IS). Hatutoi dhamana ya '
          'matokeo ya mahusiano au matches, na hatubebeki kwa hatia kwa '
          'matumizi yasiyofaa ya app, maudhui ya watumiaji wengine, au '
          'matukio yaliyotokea nje ya app. Kwa kiwango kinachoruhusiwa '
          'na sheria, uwajibikaji wetu kwa ujumle umepunguzwa hadi '
          'kiwango ulicholipa kwa kutumia app (ambacho kwa kawaida ni '
          'bure).',
    ),
    LegalSection(
      '11. Mabadiliko ya Masharti • Changes to These Terms',
      icon: Icons.update_rounded,
      body:
          'Tunaweza kusasisha masharti haya kwa muda mwingine. '
          'Mabadiliko yatachapishwa ndani ya app; ukiendelea kutumia app '
          'baada ya mabadiliko, inamaanisha umekubali toleo jipya.',
    ),
    LegalSection(
      '12. Mawasiliano • Contact',
      icon: Icons.support_agent_rounded,
      body:
          'Maswali kuhusu masharti haya yatumwe kwa timu ya huduma kwa '
          'wateja kupitia msaada wa ndani ya app (Support).',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LegalPageScaffold(
      title: 'Terms & Conditions',
      swahiliTitle: 'Masharti ya Huduma',
      subtitle:
          'Karibu Pacific! Masharti haya yanaeleza kanuni za kutumia app '
          'kwa usalama wa wote — tafadhali yasome kwa makini.',
      lastUpdated: 'Imesasishwa • Last updated: June 2026',
      headerIcon: Icons.description_rounded,
      sections: _sections,
    );
  }
}