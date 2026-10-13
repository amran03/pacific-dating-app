import 'package:flutter/material.dart';

/// ============================================================
/// APP RADIUS — the Pacific rounded design system.
/// ============================================================
///
/// ONE place for every corner radius used in the app. Never hardcode
/// `BorderRadius.circular(N)` in a screen — use one of these constants so
/// the whole app stays consistently rounded and is easy to retune.
///
///   AppRadius.sm   (12) — chips, small badges, small inputs
///   AppRadius.md   (16) — buttons, inputs, list tiles, tooltips
///   AppRadius.card (20) — cards, sheets, dialogs, the overlay notification
///   AppRadius.xl   (28) — hero cards, large sheets, modals
///   AppRadius.pill (999) — pill buttons, avatars, circular elements
abstract final class AppRadius {
  /// Small elements: chips, tags, small buttons.
  static const double smValue = 12;
  static const BorderRadius sm = BorderRadius.all(Radius.circular(smValue));

  /// Default: inputs, buttons, tiles, menus.
  static const double mdValue = 16;
  static const BorderRadius md = BorderRadius.all(Radius.circular(mdValue));

  /// Cards, bottom sheets, dialogs.
  static const double cardValue = 20;
  static const BorderRadius card = BorderRadius.all(Radius.circular(cardValue));

  /// Large surfaces: hero cards, big modals.
  static const double xlValue = 28;
  static const BorderRadius xl = BorderRadius.all(Radius.circular(xlValue));

  /// Fully-rounded pill (buttons, avatars, badges).
  static const double pillValue = 999;
  static const BorderRadius pill = BorderRadius.all(Radius.circular(pillValue));

  /// Top-rounded only (bottom sheets are dragged up).
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(cardValue),
  );

  /// Only rounded on the bottom (top sheets).
  static const BorderRadius bottom = BorderRadius.vertical(
    bottom: Radius.circular(cardValue),
  );
}
