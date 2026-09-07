import 'package:flutter/material.dart';

/// Tiers za zawadi — hutumika kwenye Gift Tray kuweka styling tofauti:
///  - basic   : zawadi za kawaida (card laini)
///  - premium : gradient card yenye glow ya rangi yake
///  - luxury  : glow inayopulsa (animated) + border ya mwanga
class GiftModel {
  final String id;
  final String name;
  final String emoji;
  final int coinPrice;
  final String tier;
  final Color glowColor;

  const GiftModel({
    required this.id,
    required this.name,
    required this.emoji,
    required this.coinPrice,
    required this.glowColor,
    this.tier = 'basic',
  });

  bool get isLuxury => tier == 'luxury';
  bool get isPremium => tier == 'premium';
}

// Zawadi za Pacific — zimepangwa kwa tiers ili tray ionekane impressive:
// bei inapanda, glow na styling zinapanda pia (TikTok-style).
const List<GiftModel> pasificGifts = [
  GiftModel(id: 'g1', name: 'Rose', emoji: '🌹', coinPrice: 10, tier: 'basic', glowColor: Color(0xFFFF4B6E)),
  GiftModel(id: 'g2', name: 'Coffee', emoji: '☕', coinPrice: 20, tier: 'basic', glowColor: Color(0xFFB07B4F)),
  GiftModel(id: 'g3', name: 'Chocolate', emoji: '🍫', coinPrice: 35, tier: 'premium', glowColor: Color(0xFF8B5A2B)),
  GiftModel(id: 'g4', name: 'Teddy Bear', emoji: '🧸', coinPrice: 50, tier: 'premium', glowColor: Color(0xFFE8A857)),
  GiftModel(id: 'g5', name: 'Perfume', emoji: '🌸', coinPrice: 75, tier: 'premium', glowColor: Color(0xFFC77DFF)),
  GiftModel(id: 'g6', name: 'Crown', emoji: '👑', coinPrice: 100, tier: 'luxury', glowColor: Color(0xFFFFB800)),
  GiftModel(id: 'g7', name: 'Diamond Ring', emoji: '💎', coinPrice: 200, tier: 'luxury', glowColor: Color(0xFF66D9FF)),
  GiftModel(id: 'g8', name: 'Sports Car', emoji: '🏎️', coinPrice: 350, tier: 'luxury', glowColor: Color(0xFFFF5252)),
  GiftModel(id: 'g9', name: 'Island', emoji: '🏝️', coinPrice: 500, tier: 'luxury', glowColor: Color(0xFF00C9A7)),
];