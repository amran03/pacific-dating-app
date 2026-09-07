import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';

/// Hubadilisha namba ya simu kuwa "email ya kubuni" (synthetic email).
/// Firebase Auth haina njia ya moja kwa moja ya phone+password, hivyo
/// hii ndiyo njia salama ya kuruhusu mtumiaji ku-login baadaye kwa
/// namba yake ya simu pamoja na password aliyochagua.
///
/// MUHIMU: function hii inatumika sehemu mbili (hapa na login_screen.dart)
/// - lazima ibaki sawa kabisa sehemu zote mbili, la sivyo login itashindwa.
String phoneToSyntheticEmail(String phoneNumberOrDigits) {
  String digits = phoneNumberOrDigits.replaceAll(RegExp(r'[^0-9]'), '');

  // Sanifisha: ondoa '0' ya mwanzo, hakikisha ina country code ya Tanzania (255)
  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (!digits.startsWith('255')) {
    digits = '255$digits';
  }

  return "$digits@pacificdatingapp.com";
}

/// Skrini hii sasa inaitwa MWISHONI mwa mchakato wa usajili (kabla ya
/// "Start Swiping" kwenye SetupAccountScreen), sio mwanzoni. Kwa sababu
/// hiyo, HAITEGEMEI tena currentUser awepo kutoka phone-verification -
/// badala yake inatengeneza akaunti mpya ya Firebase moja kwa moja.
///
/// Skrini hii inatarajiwa kufunguliwa kwa Navigator.push (sio
/// pushAndRemoveUntil) ili baada ya kufanikiwa iweze kufanya
/// Navigator.pop(context, true) kurudi kwenye SetupAccountScreen na
/// kuendelea kuhifadhi profile kamili.
class CreatePasswordScreen extends StatefulWidget {
  final String phoneNumber;

  const CreatePasswordScreen({super.key, required this.phoneNumber});

  @override
  State<CreatePasswordScreen> createState() => _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends State<CreatePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _isPasswordHidden = true;
  bool _isConfirmHidden = true;
  bool _isLoading = false;

  Future<void> _createPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final String syntheticEmail = phoneToSyntheticEmail(widget.phoneNumber);
    final String password = _passwordController.text.trim();

    try {
      // 1. Tengeneza akaunti mpya ya Firebase Auth moja kwa moja, ikitumia
      //    email ya kubuni (iliyotokana na namba ya simu) + password
      //    aliyochagua mtumiaji. Hakuna phone verification inayohitajika.
      final UserCredential credential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: syntheticEmail,
        password: password,
      );

      final String uid = credential.user!.uid;

      // 2. Hifadhi taarifa za awali kwenye Firestore. isProfileComplete
      //    inabaki false hadi SetupAccountScreen ikamilishe kuhifadhi
      //    profile kamili (jina, umri, picha n.k.) mara baada ya hapa.
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'phoneNumber': widget.phoneNumber,
        'authEmail': syntheticEmail,
        'coins': 100, // Zawadi ya kukaribisha kwa mtumiaji mpya
        'isProfileComplete': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      _showMessage("Password imewekwa kikamilifu! 🎉", Colors.green);

      // Rudi kwenye SetupAccountScreen (uliyemtoka) ukiwa na matokeo
      // 'true' ili aendelee kuhifadhi profile na kuelekea Dashboard.
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      String message = "Imeshindikana kuweka password.";
      if (e.code == 'email-already-in-use') {
        message = "Namba hii ya simu tayari ina akaunti. Tafadhali tumia Log In.";
      } else if (e.code == 'weak-password') {
        message = "Password ni dhaifu sana, chagua nyingine.";
      }
      _showMessage("$message (${e.code})", Colors.redAccent);
    } catch (e) {
      _showMessage("Kosa: ${e.toString()}", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.lock_person_rounded, size: 36, color: AppColors.primary),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Weka Password Yako 🔒",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  "Hatua ya mwisho! Weka password ambayo utaitumia pamoja na ${widget.phoneNumber} kila utakapoingia (login).",
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 32),

                const Text("Password", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _isPasswordHidden,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                    suffixIcon: IconButton(
                      icon: Icon(_isPasswordHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _isPasswordHidden = !_isPasswordHidden),
                    ),
                    hintText: "Angalau herufi/tarakimu 6",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return "Password lazima iwe angalau herufi 6";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                const Text("Thibitisha Password", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _isConfirmHidden,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                    suffixIcon: IconButton(
                      icon: Icon(_isConfirmHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _isConfirmHidden = !_isConfirmHidden),
                    ),
                    hintText: "Rudia password",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return "Password hazifanani";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      "Kamilisha & Endelea",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}