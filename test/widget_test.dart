// Smoke tests za Pacific Dating App.
//
// Hatupump app nzima kwenye test (inahitaji Supabase + network), tunatest
// logic safi ya auth: kubadilisha namba ya simu kuwa synthetic email
// inayotumika kusajili/kuingia user kwenye Supabase Auth.

import 'package:flutter_test/flutter_test.dart';

import 'package:pacific_dating_app/features/auth/presentation/create_password_screen.dart';

void main() {
  group('phoneToSyntheticEmail', () {
    test('hubadilisha 0712345678 kuwa synthetic email sahihi', () {
      expect(
        phoneToSyntheticEmail('0712345678'),
        '255712345678@pacificdatingapp.com',
      );
    });

    test('hubadilisha 712345678 (bila 0 mwanzoni) sahihi', () {
      expect(
        phoneToSyntheticEmail('712345678'),
        '255712345678@pacificdatingapp.com',
      );
    });

    test('hubadilisha +255712345678 (E.164) sahihi', () {
      expect(
        phoneToSyntheticEmail('+255712345678'),
        '255712345678@pacificdatingapp.com',
      );
    });

    test('hubadilisha +255 071 234 5678 (na nafasi/mabano) sahihi', () {
      expect(
        phoneToSyntheticEmail('+255 (0) 712-345-678'),
        '255712345678@pacificdatingapp.com',
      );
    });
  });
}
