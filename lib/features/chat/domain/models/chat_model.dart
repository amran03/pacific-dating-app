class ChatModel {
  final String id;
  final String name;
  final String avatarUrl;
  final String lastMessage;
  final String timeSent;
  final bool isLocked;
  final int remainingSeconds; // Timer ya dakika 30 (k.m. 1800 sec)
  final int unlockCostCoins;

  ChatModel({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.lastMessage,
    required this.timeSent,
    this.isLocked = false,
    this.remainingSeconds = 1800,
    this.unlockCostCoins = 50,
  });
}