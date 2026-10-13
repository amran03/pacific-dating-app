import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';
import 'package:pacific_dating_app/core/services/user_prefs.dart';
import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';

/// Settings inayojitegemea.
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() =>
      _AppSettingsScreenState();
}

class _AppSettingsScreenState
    extends State<AppSettingsScreen> {
  bool _notif = false;
  bool _vib = true;
  bool _sound = true;
  bool _receipts = true;
  bool _typing = true;
  bool _online = true;
  bool _discover = true;
  bool _location = false;
  int _price = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('notifications_enabled, vibration_enabled, '
              'sound_enabled, read_receipts_enabled, '
              'typing_indicator_enabled, '
              'show_online_status_enabled, discoverable, '
              'location_enabled, chat_unlock_price')
          .eq('uid', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _notif = row['notifications_enabled'] != true
              ? false
              : true;
          _vib = row['vibration_enabled'] != false;
          _sound = row['sound_enabled'] != false;
          _receipts =
              row['read_receipts_enabled'] != false;
          _typing =
              row['typing_indicator_enabled'] != false;
          _online =
              row['show_online_status_enabled'] != false;
          _discover = row['discoverable'] != false;
          _location = row['location_enabled'] == true;
          _price =
              (row['chat_unlock_price'] as num?)?.toInt() ??
                  0;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String column, bool value) async {
    UserPrefs.instance.set(column, value);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('users').update({
        column: value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', user.id);
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed: $e',
            color: Colors.redAccent);
      }
    }
  }



  Future<void> _priceDialog(int current) async {
    int sel = current.clamp(0, 500);
    await showDialog(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc2, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: AppRadius.card),
          title: const Text('Chat Unlock Price',
              style:
                  TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Coins others must pay to unlock chat.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Text('$sel Coins',
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppColors.coinGoldDark)),
              Slider(
                value: sel.toDouble(),
                min: 0,
                max: 500,
                divisions: 25,
                activeColor: AppColors.primary,
                label: '$sel',
                onChanged: (x) =>
                    setD(() => sel = x.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dc2),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => confirmPrice(dc2, sel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
              ),
              child: const Text('Save',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> confirmPrice(BuildContext dc, int sel) async {
    Navigator.pop(dc);
    setState(() => _price = sel);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('users').update({
        'chat_unlock_price': sel,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', user.id);
      if (mounted) {
        showAppNotification(
          context,
          sel == 0
              ? 'Your chat is now FREE'
              : 'Price set to $sel Coins',
          color: Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed: $e',
            color: Colors.redAccent);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings',
            style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w800,
                fontSize: 20)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _cat(
                  Icons.notifications_rounded,
                  Colors.teal,
                  'Notifications',
                  'Matches, messages na gifts',
                  [
                    _sw(
                        Icons.notifications_active_rounded,
                        Colors.teal,
                        'Arifa',
                        'Pokaa arifa zote',
                        _notif, (v) {
                      setState(() => _notif = v);
                      _save('notifications_enabled', v);
                    }),
                    _sw(Icons.vibration_rounded,
                        Colors.deepOrange, 'Vibration',
                        'Simu iteteme', _vib, (v) {
                      setState(() => _vib = v);
                      _save('vibration_enabled', v);
                    }),
                    _sw(Icons.volume_up_rounded, Colors.pink,
                        'Sauti', 'Sauti ya arifa',
                        _sound, (v) {
                      setState(() => _sound = v);
                      _save('sound_enabled', v);
                    }),
                  ],
                ),
                const SizedBox(height: 14),
                _cat(
                  Icons.chat_bubble_rounded,
                  Colors.blue,
                  'Chat Preferences',
                  'Read receipts na typing',
                  [
                    _sw(Icons.done_all_rounded, Colors.green,
                        'Read Receipts', 'Seen ticks',
                        _receipts, (v) {
                      setState(() => _receipts = v);
                      _save('read_receipts_enabled', v);
                    }),
                    _sw(Icons.keyboard_alt_outlined,
                        Colors.blueGrey, 'Typing',
                        'Anaandika...', _typing, (v) {
                      setState(() => _typing = v);
                      _save('typing_indicator_enabled', v);
                    }),
                  ],
                ),
                const SizedBox(height: 14),
                _cat(
                  Icons.lock_rounded,
                  AppColors.coinGoldDark,
                  'Chat Lock',
                  'Funga chat kwa Coins',
                  [
                    _sw(Icons.lock_rounded, AppColors.coinGold,
                        'Lock Chat',
                        _price > 0
                            ? 'Locked — $_price Coins'
                            : 'FREE for everyone',
                        _price > 0, (v) {
                      _priceDialog(v ? _price : 0);
                    }),
                    ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.coinGold
                              .withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(11),
                        ),
                        child: const Icon(
                            Icons.monetization_on_rounded,
                            color: AppColors.coinGold,
                            size: 19),
                      ),
                      title: const Text('Change Price',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      subtitle: Text(
                          _price > 0
                              ? 'Current: $_price Coins'
                              : 'Set coin price',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600)),
                      trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey),
                      onTap: () => _priceDialog(_price),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _cat(
                  Icons.privacy_tip_rounded,
                  Colors.deepPurple,
                  'Privacy & Visibility',
                  'Nani akuone',
                  [
                    _sw(Icons.visibility_rounded,
                        Colors.deepPurple, 'Online Status',
                        'Others see online', _online, (v) {
                      setState(() => _online = v);
                      _save(
                          'show_online_status_enabled', v);
                    }),
                    _sw(Icons.explore_rounded, Colors.orange,
                        'Show in Discover', 'Swipe cards',
                        _discover, (v) {
                      setState(() => _discover = v);
                      _save('discoverable', v);
                    }),
                    _sw(Icons.location_on_rounded,
                        Colors.indigo, 'Show Distance',
                        'Nearby people', _location, (v) {
                      setState(() => _location = v);
                      _save('location_enabled', v);
                    }),
                  ],
                ),
                const SizedBox(height: 28),
              ],
            ),
    );
  }


  Widget _cat(IconData icon, Color c, String t, String s,
      List<Widget> kids) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: c, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(t,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      Text(s,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 8),
          ...kids,
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _sw(IconData icon, Color c, String t, String s,
      bool v, ValueChanged<bool> fn) {
    return SwitchListTile(
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: c, size: 19),
      ),
      title: Text(t,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(s,
          style: TextStyle(
              fontSize: 12, color: Colors.grey.shade600)),
      value: v,
      activeThumbColor: AppColors.primary,
      onChanged: fn,
    );
  }
}
