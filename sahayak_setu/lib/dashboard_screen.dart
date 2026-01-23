import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'profile_screen.dart'; 
import 'api_key.dart';

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
  final _diseaseController = TextEditingController();
  
  // Dropdown Logic
  String? _selectedCondition; 
  final List<String> _conditionOptions = ['Fit', 'Moderate', 'Risky'];

  // ⚠️ PASTE YOUR KEY DIRECTLY HERE FOR TESTING
  // Once it works, we can move it back to api_key.dart
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
        onStatus: (status) => print('Mic Status: $status'),
        onError: (error) => print('Mic Error: $error'),
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
              print("Voice captured: $_voiceText"); // DEBUG PRINT
              _extractDataWithGemini(_voiceText); 
            }
          },
          localeId: "hi_IN", 
        );
      } else {
        print("Mic denied or not available");
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

  // --- 3. ON-SCREEN DEBUGGING VERSION ---
  Future<void> _extractDataWithGemini(String spokenText) async {
    if (spokenText.trim().isEmpty) return;

    // 1. Show "Thinking" Popup immediately
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("AI is thinking...")]),
      ),
    );

    final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
    
    // Explicit Prompt
    final prompt = '''
      Act as a JSON parser. 
      Input: "$spokenText"
      Output JSON ONLY: {"name": "...", "disease": "...", "condition": "Fit" or "Moderate" or "Risky"}
    ''';

    try {
      final response = await model.generateContent([Content.text(prompt)]);
      
      // Close the "Thinking" Popup
      Navigator.pop(context); 

      // 2. SHOW THE RAW AI ANSWER (To see if it works)
      // If you see this popup, the API Key works!
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("🔍 AI Debug Info"),
          content: SingleChildScrollView(child: Text("Raw AI said:\n\n${response.text}")),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Continue"))],
        ),
      );

      // --- PARSING LOGIC ---
      final String rawText = response.text!;
      final int startIndex = rawText.indexOf('{');
      final int endIndex = rawText.lastIndexOf('}');

      if (startIndex == -1) throw Exception("No JSON brackets found!");

      final String jsonString = rawText.substring(startIndex, endIndex + 1);
      final Map<String, dynamic> data = jsonDecode(jsonString);

      setState(() {
        _nameController.text = data['name'] ?? "";
        _diseaseController.text = data['disease'] ?? ""; 
        
        // Smart Dropdown
        String aiCondition = data['condition'] ?? "Moderate";
        aiCondition = aiCondition[0].toUpperCase() + aiCondition.substring(1).toLowerCase();
        
        if (_conditionOptions.contains(aiCondition)) {
          _selectedCondition = aiCondition;
        } else {
          _selectedCondition = "Moderate"; 
        }
        _isAiProcessing = false;
      });

    } catch (e) {
      // Close the loading popup if open
      Navigator.pop(context);
      
      // 3. SHOW THE ERROR POPUP (To see why it failed)
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("❌ Error"),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
        ),
      );
      
      setState(() {
        _diseaseController.text = "Error: $e";
        _isAiProcessing = false;
      });
    }
  }

  // --- 4. AI ADVISOR ---
  Future<void> _analyzeRiskAndSave(String name, String disease, String condition) async {
    // 1. Save to Firestore
    await FirebaseFirestore.instance.collection('patients').add({
      'name': name,
      'disease': disease,
      'condition': condition,
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
    final prompt = 'Patient: $name. Problem: $disease. Severity: $condition. Provide short medical advice in English and Hindi. Return JSON: {"advice_en": "...", "advice_hi": "..."}';

    try {
      final response = await model.generateContent([Content.text(prompt)]);
      Navigator.pop(context); 

      // Clean JSON again
      String rawText = response.text!;
      int start = rawText.indexOf('{');
      int end = rawText.lastIndexOf('}');
      String cleanJson = rawText.substring(start, end + 1);
      
      final data = jsonDecode(cleanJson);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
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

 // --- 5. UI: ADD PATIENT DIALOG (With Manual Debug) ---
  void _showAddPatientDialog() {
    _nameController.clear();
    _diseaseController.clear();
    _selectedCondition = null;
    _voiceText = "";
    _isAiProcessing = false;
    
    // Controller for the manual debug box
    final TextEditingController debugInputController = TextEditingController();

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
                    // --- 1. MIC BUTTON ---
                    GestureDetector(
                      onTap: () => _listenAndAutoFill(setDialogState),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: _isListening ? Colors.red : Colors.teal,
                        child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 30),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(_isListening ? "Listening..." : "Tap Mic to Speak"),
                    
                    const Divider(height: 30),
                    
                    // --- 2. MANUAL DEBUG INPUT (The Fix) ---
                    // Use this if Mic fails
                    TextField(
                      controller: debugInputController,
                      decoration: InputDecoration(
                        labelText: "Or type here to test AI",
                        hintText: "e.g., 'Raju has severe fever'",
                        filled: true,
                        fillColor: Colors.grey[100],
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.send, color: Colors.teal),
                          onPressed: () {
                            // Force trigger the AI function manually
                            if (debugInputController.text.isNotEmpty) {
                              // Close the keyboard
                              FocusScope.of(context).unfocus();
                              // Call the AI function
                              _extractDataWithGemini(debugInputController.text);
                            }
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    
                    const Divider(height: 30),

                    // --- 3. FORM FIELDS (Auto-filled by AI) ---
                    TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Name", border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    
                    TextField(controller: _diseaseController, decoration: const InputDecoration(labelText: "Disease / Symptoms", border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCondition,
                      decoration: const InputDecoration(labelText: "Condition", border: OutlineInputBorder()),
                      items: _conditionOptions.map((String value) {
                        return DropdownMenuItem<String>(value: value, child: Text(value));
                      }).toList(),
                      onChanged: (newValue) => setDialogState(() => _selectedCondition = newValue),
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