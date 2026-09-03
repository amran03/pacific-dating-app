class GiftModel {
  final String id;
  final String name;
  final String emoji;
  final int coinPrice;

  GiftModel({
    required this.id,
    required this.name,
    required this.emoji,
    required this.coinPrice,
  });
}

// Sample Gifts za Pasific
final List<GiftModel> pasificGifts = [
  GiftModel(id: 'g1', name: 'Rose', emoji: '🌹', coinPrice: 10),
  GiftModel(id: 'g2', name: 'Coffee', emoji: '☕', coinPrice: 20),
  GiftModel(id: 'g3', name: 'Chocolate', emoji: '🍫', coinPrice: 35),
  GiftModel(id: 'g4', name: 'Teddy Bear', emoji: '🧸', coinPrice: 50),
  GiftModel(id: 'g5', name: 'Crown', emoji: '👑', coinPrice: 100),
  GiftModel(id: 'g6', name: 'Diamond Ring', emoji: '💎', coinPrice: 200),
];