import 'package:flutter/material.dart';

/// Shown when the app starts without Supabase credentials, instead of
/// crashing. Gives clear, copy-pasteable setup instructions.
class SupabaseSetupScreen extends StatelessWidget {
  const SupabaseSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 48, color: Color(0xFFFF4B72)),
                  const SizedBox(height: 16),
                  const Text(
                    'Backend haijaandaliwa',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Supabase is not configured yet. Add your project '
                    'credentials to run the app:',
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  _step(
                    '1',
                    'Create a project at supabase.com',
                  ),
                  _step(
                    '2',
                    'Run supabase_schema.sql in the SQL Editor',
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Then launch the app with:',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'flutter run \\\n'
                      '  --dart-define=SUPABASE_URL=\\\n'
                      '    https://xxxx.supabase.co \\\n'
                      '  --dart-define=SUPABASE_PUBLISHABLE_KEY=\\\n'
                      '    sb_publishable_...',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFF9CDCFE),
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Or paste the credentials directly in '
                    'lib/core/config/app_config.dart',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFFF4B72),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
