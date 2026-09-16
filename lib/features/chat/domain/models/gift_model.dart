import 'package:flutter/material.dart';

/// Tiers za zawadi — hutumika kwenye Gift Tray kuweka styling tofauti:
///  - basic   : zawadi za kawaida (card laini)
///  - premium : gradient card yenye glow ya rangi yake
///  - luxury  : glow inayopulsa (animated) + border ya mwanga
class GiftModel {
  final String id;
  final String name;
  final String? emoji;
  final String? imageUrl;
  final int coinPrice;
  final String tier;
  final Color glowColor;

  const GiftModel({
    required this.id,
    required this.name,
    this.emoji,
    this.imageUrl,
    required this.coinPrice,
    required this.glowColor,
    this.tier = 'basic',
  });

  bool get isLuxury => tier == 'luxury';
  bool get isPremium => tier == 'premium';

  factory GiftModel.fromMap(Map<String, dynamic> map) {
    return GiftModel(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      emoji: map['emoji']?.toString(),
      imageUrl: map['image_url']?.toString(),
      coinPrice: _parsePrice(map['coin_price']),
      tier: (map['tier'] ?? 'basic').toString(),
      glowColor: _parseColor(map['glow_color']),
    );
  }

  static int _parsePrice(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static Color _parseColor(dynamic v) {
    const fallback = Color(0xFFFF4B6E);
    if (v == null) return fallback;
    if (v is int) return Color(v);
    if (v is num) return Color(v.toInt());
    String s = v.toString().trim();
    if (s.isEmpty) return fallback;
    try {
      // Ruhusu miundo: "0xFFFF4B6E", "#FF4B6E", "#FFFF4B6E", "4294907246"
      if (s.startsWith('#')) {
        s = s.substring(1);
        if (s.length == 6) s = 'FF$s';
        return Color(int.parse(s, radix: 16));
      }
      if (s.startsWith('0x') || s.startsWith('0X')) {
        return Color(int.parse(s.substring(2), radix: 16));
      }
      // Decimal string kutoka Supabase
      final dec = int.tryParse(s);
      if (dec != null) return Color(dec);
      return Color(int.parse(s, radix: 16));
    } catch (_) {
      return fallback;
    }
  }
}

// Gifts za Pacific — zimepangwa to tiers ili tray ionekane impressive:
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