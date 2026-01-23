import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DoctorDashboard extends StatelessWidget {
  const DoctorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4, // Risky, Moderate, Fit, Maternal
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Doctor's Portal"),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: "Risky", icon: Icon(Icons.warning)),
              Tab(text: "Moderate", icon: Icon(Icons.info)),
              Tab(text: "Fit", icon: Icon(Icons.check_circle)),
              Tab(text: "Maternal", icon: Icon(Icons.pregnant_woman)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildPatientList("Risky"),
            _buildPatientList("Moderate"),
            _buildPatientList("Fit"),
            _buildMaternalList(), // Special list for pregnant women
          ],
        ),
      ),
    );
  }

  // 1. Standard List for Conditions
  Widget _buildPatientList(String status) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance
          .collection('patients')
          .where('condition', isEqualTo: status)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return Center(child: Text("No $status patients"));

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data = snapshot.data!.docs[index].data();
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text(data['name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Disease: ${data['disease'] ?? 'N/A'}"),
                trailing: Text(status, style: TextStyle(color: _getColor(status), fontWeight: FontWeight.bold)),
              ),
            );
          },
        );
      },
    );
  }

  // 2. Special List for Maternal (Pregnancy)
  Widget _buildMaternalList() {
    return StreamBuilder(
      stream: FirebaseFirestore.instance
          .collection('patients')
          .where('is_pregnant', isEqualTo: true) // <--- THIS IS THE KEY FILTER
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text("No Maternal cases"));

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data = snapshot.data!.docs[index].data();
            return Card(
              color: Colors.purple.shade50,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.pregnant_woman, color: Colors.purple, size: 40),
                title: Text(data['name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Condition: ${data['condition'] ?? 'Unknown'}"),
              ),
            );
          },
        );
      },
    );
  }

  Color _getColor(String status) {
    if (status == 'Risky') return Colors.red;
    if (status == 'Moderate') return Colors.orange;
    return Colors.green;
  }
}