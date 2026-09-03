import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Privacy Policy",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Sera ya Faragha (Privacy Policy)",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              SizedBox(height: 12),
              Text(
                "Karibu kwenye mfumo wetu. Tunathamini sana faragha na usalama wa taarifa zako binafsi. Sera hii inaeleza jinsi tunavyokusanya, kutumia na kulinda data zako unapotumia app yetu ya uchumba.",
                style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
              ),
              SizedBox(height: 16),
              Text(
                "1. Taarifa Tunazokusanya",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              SizedBox(height: 6),
              Text(
                "Tunakusanya taarifa unazojaza moja kwa moja kama vile jina lako, umri, picha, eneo, na jumbe unazozituma kwa watumiaji wengine.",
                style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
              ),
              SizedBox(height: 16),
              Text(
                "2. Usalama wa Taarifa Zako",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              SizedBox(height: 6),
              Text(
                "Tunatumia teknolojia za kisasa za usimbaji fiche (encryption) kulinda data zako ili zisinaswe au kutumiwa na watu wasiohusika.",
                style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
              ),
              SizedBox(height: 16),
              Text(
                "3. Mawasiliano",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              SizedBox(height: 6),
              Text(
                "Kama una swali lolote kuhusu sera hii ya faragha, unaweza kuwasiliana na timu yetu ya huduma kwa wateja kupitia msaada wetu wa ndani ya app.",
                style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}