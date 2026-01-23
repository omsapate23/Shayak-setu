import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'login_screen.dart';       // Existing ASHA Login
import 'doctor_dashboard.dart';   // New Doctor Page

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  runApp(const SahayakApp());
}

class SahayakApp extends StatelessWidget {
  const SahayakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sahayak Setu',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const RoleSelectionPage(), // Start with Role Selection
    );
  }
}

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
           gradient: LinearGradient(
             colors: [Colors.teal, Colors.tealAccent],
             begin: Alignment.topLeft,
             end: Alignment.bottomRight,
           ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.health_and_safety, size: 100, color: Colors.white),
              const SizedBox(height: 20),
              const Text("SAHAYAK SETU", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 50),
              
              // ASHA BUTTON
              ElevatedButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text("I AM AN ASHA WORKER"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
              ),
              
              const SizedBox(height: 20),
              
              // DOCTOR BUTTON
              ElevatedButton.icon(
                icon: const Icon(Icons.medical_services),
                label: const Text("I AM A DOCTOR"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DoctorDashboard())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}