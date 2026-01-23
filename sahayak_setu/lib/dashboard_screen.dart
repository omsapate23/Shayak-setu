import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http; // HTTP Package
import 'dart:convert';
import 'profile_screen.dart'; 
import 'api_key.dart'; // Ensure this file exists

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
  bool _isPregnant = false; // Add this line

  // Form Controllers
  final _nameController = TextEditingController();
  final _diseaseController = TextEditingController();
  
  // Dropdown Logic
  String? _selectedCondition; 
  final List<String> _conditionOptions = ['Fit', 'Moderate', 'Risky'];

  // API Key 
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
              
              // Pass the dialog's state setter to the AI
              _extractDataWithGemini(_voiceText, setDialogState); 
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

  // --- 3. DIRECT API EXTRACTION (With English Translation) ---
  Future<void> _extractDataWithGemini(String spokenText, StateSetter setDialogState) async {
    if (spokenText.trim().isEmpty) return;

    setDialogState(() {
      _isAiProcessing = true;
      _diseaseController.text = "Translating..."; // Feedback to user
    });

    try {
      // Using the model that worked for you
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey');

      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        "contents": [{
          "parts": [{
            "text": '''
              Act as a medical data parser. Input: "$spokenText".
              
              Rules:
              1. Extract the fields below.
              2. TRANSLATE ALL VALUES TO ENGLISH if the input is in Hindi or mixed language.
              3. Return strictly valid JSON.
              
              JSON Format:
              {
                "name": "Patient Name (or Unknown)",
                "disease": "Symptoms or Disease mentioned (In English)",
                "condition": "Fit", "Moderate", or "Risky" (Choose based on severity)
              }
              
              Do not add markdown. Return ONLY the JSON object.
            '''
          }]
        }]
      });

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        String text = jsonResponse['candidates'][0]['content']['parts'][0]['text'];
        
        // Clean markdown
        text = text.replaceAll('```json', '').replaceAll('```', '').trim();
        int start = text.indexOf('{');
        int end = text.lastIndexOf('}');
        if (start != -1 && end != -1) text = text.substring(start, end + 1);

        final data = jsonDecode(text);

        // Update Popup UI
        setDialogState(() {
          _nameController.text = data['name'] ?? "";
          _diseaseController.text = data['disease'] ?? "";
          
          String aiCondition = data['condition'] ?? "Moderate";
          aiCondition = aiCondition[0].toUpperCase() + aiCondition.substring(1).toLowerCase();
          
          if (_conditionOptions.contains(aiCondition)) {
            _selectedCondition = aiCondition;
          } else {
            _selectedCondition = "Moderate";
          }
          _isAiProcessing = false; 
        });

      } else {
        throw Exception("API Error: ${response.statusCode}");
      }
    } catch (e) {
      print("Extraction Error: $e");
      setDialogState(() {
         _diseaseController.text = "Error: $e";
         _isAiProcessing = false;
      });
    }
  }

  // --- 4. DIRECT API RISK ANALYSIS ---
  Future<void> _analyzeRiskAndSave(String name, String disease, String condition, bool isPregnant) async {
  // 1. Save to Firestore with the new 'is_pregnant' field
  await FirebaseFirestore.instance.collection('patients').add({
    'name': name,
    'disease': disease,
    'condition': condition,
    'is_pregnant': isPregnant, // <--- SAVING THE FLAG
    'timestamp': FieldValue.serverTimestamp(),
  });

  if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    // 2. Ask Gemini for Advice
    try {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey');

      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        "contents": [{
          "parts": [{
            "text": '''
              Patient: $name. Problem: $disease. Severity: $condition.
              Provide short medical advice in English and Hindi.
              Return JSON: {"advice_en": "...", "advice_hi": "..."}
              Do not add markdown.
            '''
          }]
        }]
      });

      final response = await http.post(url, headers: headers, body: body);
      Navigator.pop(context); // Close loading

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        String text = jsonResponse['candidates'][0]['content']['parts'][0]['text'];
        
        text = text.replaceAll('```json', '').replaceAll('```', '').trim();
        int start = text.indexOf('{');
        int end = text.lastIndexOf('}');
        if (start != -1 && end != -1) text = text.substring(start, end + 1);

        final data = jsonDecode(text);

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
                  Text(data['advice_en'] ?? "No advice"),
                  const Divider(),
                  Text(data['advice_hi'] ?? "No advice", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                ],
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
            ),
          );
        }
      } 
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      print("Analysis Error: $e");
    }
  }

  // --- 5. UI: ADD PATIENT DIALOG ---
  void _showAddPatientDialog() {
    _nameController.clear();
    _diseaseController.clear();
    _selectedCondition = null;
    _voiceText = "";
    _isAiProcessing = false;
    
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
                    Text(_isListening ? "Listening..." : (_isAiProcessing ? "AI Thinking..." : "Tap Mic to Speak")),
                    
                    const Divider(height: 20),
                    
                    // MANUAL TEST BOX
                    TextField(
                      controller: debugInputController,
                      decoration: InputDecoration(
                        labelText: "Or type to test AI",
                        hintText: "e.g., 'Raju has high fever'",
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.send, color: Colors.teal),
                          onPressed: () {
                             if(debugInputController.text.isNotEmpty) {
                               FocusScope.of(context).unfocus();
                               // CALL AI WITH DIALOG STATE
                               _extractDataWithGemini(debugInputController.text, setDialogState);
                             }
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),

                    const Divider(height: 20),

                    // FIELDS
                    TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Name", border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    
                    TextField(controller: _diseaseController, decoration: const InputDecoration(labelText: "Disease", border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    
                    DropdownButtonFormField<String>(
                      value: _selectedCondition,
                      decoration: const InputDecoration(labelText: "Condition", border: OutlineInputBorder()),
                      items: _conditionOptions.map((String value) {
                        return DropdownMenuItem<String>(value: value, child: Text(value));
                      }).toList(),
                      onChanged: (newValue) => setDialogState(() => _selectedCondition = newValue),
                    ),
                    const SizedBox(height: 10),

// ADD THIS SWITCH
SwitchListTile(
  title: const Text("Is Patient Pregnant?"),
  value: _isPregnant,
  activeColor: Colors.purple,
  onChanged: (val) {
    setDialogState(() {
      _isPregnant = val;
    });
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
    // Pass _isPregnant here
    _analyzeRiskAndSave(_nameController.text, _diseaseController.text, _selectedCondition!, _isPregnant);
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
              String condition = data['condition'] ?? "Moderate";
              
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