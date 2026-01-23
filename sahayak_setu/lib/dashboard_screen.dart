import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'profile_screen.dart'; 
import 'api_key.dart'; // Ensure you have your API key here

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // --- 1. SETUP VARIABLES ---
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _voiceText = "";
  bool _isAiProcessing = false;

  // Form Controllers
  final _nameController = TextEditingController();
  final _diseaseController = TextEditingController(); // NEW: Disease Field
  
  // Dropdown Logic
  String? _selectedCondition; // NEW: Holds "Fit", "Moderate", or "Risky"
  final List<String> _conditionOptions = ['Fit', 'Moderate', 'Risky'];

  // API Key (From api_key.dart or hardcoded)
  final String _apiKey = geminiApiKey; 

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  // --- 2. VOICE LISTENER ---
  void _listenAndAutoFill(StateSetter setDialogState) async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) => print('Status: $status'),
        onError: (errorNotification) => print('Error: $errorNotification'),
      );

      if (available) {
        setDialogState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setDialogState(() {
              _voiceText = val.recognizedWords;
            });
            
            if (val.finalResult) {
              setDialogState(() {
                _isListening = false;
                _isAiProcessing = true;
              });
              _stopListening();
              _extractDataWithGemini(_voiceText); // Trigger AI
            }
          },
          localeId: "hi_IN", 
        );
      }
    } else {
      setDialogState(() => _isListening = false);
      _stopListening();
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  // --- 3. AI EXTRACTION (Voice -> Name, Disease, Condition Dropdown) ---
  Future<void> _extractDataWithGemini(String spokenText) async {
    if (spokenText.trim().isEmpty) return;

    final model = GenerativeModel(model: 'gemini-pro', apiKey: _apiKey);
    
    // UPDATED PROMPT: Asks AI to map the condition to the 3 options
    final prompt = '''
      Extract patient details from this voice input: "$spokenText".
      
      Rules:
      1. 'disease': The specific illness (e.g., Fever, Cold).
      2. 'condition': Map strictly to one of these three: "Fit", "Moderate", or "Risky".
         - If symptom is mild -> "Fit"
         - If symptom is bad -> "Moderate"
         - If symptom is severe/emergency -> "Risky"
      
      Return ONLY JSON: {"name": "...", "disease": "...", "condition": "..."}
    ''';

    try {
      final response = await model.generateContent([Content.text(prompt)]);
      print("AI Response: ${response.text}");

      String cleanJson = response.text!.replaceAll('```json', '').replaceAll('```', '');
      final data = jsonDecode(cleanJson);

      setState(() {
        _nameController.text = data['name'] ?? "";
        _diseaseController.text = data['disease'] ?? ""; // Fill Disease
        
        // Auto-select Dropdown (Ensure it matches one of our options)
        String aiCondition = data['condition'] ?? "Moderate";
        if (_conditionOptions.contains(aiCondition)) {
          _selectedCondition = aiCondition;
        } else {
          _selectedCondition = "Moderate"; // Fallback
        }
        
        _isAiProcessing = false;
      });
    } catch (e) {
      print("AI Error: $e");
      setState(() {
        _diseaseController.text = "Error extracting";
        _isAiProcessing = false;
      });
    }
  }

  // --- 4. AI ADVISOR (Analyzes Disease + Condition Level) ---
  Future<void> _analyzeRiskAndSave(String name, String disease, String condition) async {
    // 1. Save to Firestore
    await FirebaseFirestore.instance.collection('patients').add({
      'name': name,
      'disease': disease,
      'condition': condition, // Saved as "Fit", "Moderate", etc.
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    // 2. Ask Gemini for Advice
    final model = GenerativeModel(model: 'gemini-pro', apiKey: _apiKey);
    final prompt = '''
      Patient: $name. 
      Problem: $disease.
      Severity Status: $condition.
      
      Provide medical advice. Return ONLY JSON:
      {
        "advice_en": "Short advice in English",
        "advice_hi": "Short advice in Hindi"
      }
    ''';

    try {
      final response = await model.generateContent([Content.text(prompt)]);
      Navigator.pop(context); 

      String cleanJson = response.text!.replaceAll('```json', '').replaceAll('```', '');
      final data = jsonDecode(cleanJson);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                // Icon changes based on the Dropdown selection
                Icon(
                  condition == "Risky" ? Icons.warning : (condition == "Moderate" ? Icons.info : Icons.check_circle), 
                  color: condition == "Risky" ? Colors.red : (condition == "Moderate" ? Colors.orange : Colors.green)
                ),
                const SizedBox(width: 8),
                Text("Status: $condition"),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Disease: $disease", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(data['advice_en']),
                const Divider(),
                Text(data['advice_hi'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      print("Analysis Error: $e");
    }
  }

  // --- 5. UI: ADD PATIENT DIALOG ---
  void _showAddPatientDialog() {
    _nameController.clear();
    _diseaseController.clear();
    _selectedCondition = null; // Reset Dropdown
    _voiceText = "";
    _isAiProcessing = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Add Patient"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // MIC BUTTON
                    GestureDetector(
                      onTap: () => _listenAndAutoFill(setDialogState),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: _isListening ? Colors.red : Colors.teal,
                        child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 30),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(_isListening ? "Listening..." : (_isAiProcessing ? "AI Selecting..." : "Tap Mic to Speak")),
                    if (_voiceText.isNotEmpty) 
                      Padding(padding: const EdgeInsets.all(8.0), child: Text("Heard: \"$_voiceText\"", style: const TextStyle(fontSize: 12, color: Colors.grey))),
                    
                    const SizedBox(height: 15),
                    
                    // FIELD 1: NAME
                    TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Name", border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    
                    // FIELD 2: DISEASE
                    TextField(controller: _diseaseController, decoration: const InputDecoration(labelText: "Disease / Symptoms", border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    
                    // FIELD 3: CONDITION DROPDOWN
                    DropdownButtonFormField<String>(
                      value: _selectedCondition,
                      decoration: const InputDecoration(labelText: "Condition", border: OutlineInputBorder()),
                      items: _conditionOptions.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        setDialogState(() => _selectedCondition = newValue);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () {
                    if (_nameController.text.isNotEmpty && _selectedCondition != null) {
                      Navigator.pop(context); 
                      _analyzeRiskAndSave(_nameController.text, _diseaseController.text, _selectedCondition!);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  child: const Text("Save & Analyze"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- 6. HELPER: COLOR FOR CHIPS ---
  Color _getStatusColor(String condition) {
    switch (condition) {
      case 'Risky': return Colors.red;
      case 'Moderate': return Colors.orange;
      case 'Fit': return Colors.green;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ASHA Dashboard"), 
        backgroundColor: Colors.teal, 
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          )
        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('patients').orderBy('timestamp', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (ctx, index) {
              var data = snapshot.data!.docs[index].data();
              String condition = data['condition'] ?? "Moderate"; // Default fallback
              
              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal[50], 
                    child: Text(data['name'][0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  ),
                  title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Disease: ${data['disease'] ?? 'Unknown'}"),
                  trailing: Chip(
                    label: Text(condition, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    backgroundColor: _getStatusColor(condition),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: _showAddPatientDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}