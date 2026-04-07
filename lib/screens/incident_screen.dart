import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'new_incident_screen.dart';

class IncidentScreen extends StatelessWidget {
  const IncidentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String? driverId = FirebaseAuth.instance.currentUser?.uid;

    if (driverId == null) {
      return const Scaffold(body: Center(child: Text('Utilizador não autenticado.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Incidências Pendentes')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('incidents')
            .where('driverId', isEqualTo: driverId)
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar dados: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'Nenhuma incidência pendente',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final type = data['type'] ?? 'Desconhecido';
              final plate = data['plate'] ?? 'Sem Matrícula';
              final timestamp = data['incidentDate'] as Timestamp?;
              String dateStr = 'Data desconhecida';
              if (timestamp != null) {
                dateStr = DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate());
              }

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                  title: Text('$type'),
                  subtitle: Text('$plate • $dateStr'),
                  trailing: const Icon(Icons.edit, color: Colors.grey, size: 20),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NewIncidentScreen(existingDoc: docs[index]),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NewIncidentScreen()),
          );
        },
        backgroundColor: Colors.deepOrange.shade600,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
