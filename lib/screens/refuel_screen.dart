import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'new_refuel_screen.dart';

class RefuelScreen extends StatelessWidget {
  const RefuelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String? driverId = FirebaseAuth.instance.currentUser?.uid;

    if (driverId == null) {
      return const Scaffold(body: Center(child: Text('Utilizador não autenticado.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Abastecimentos Pendentes')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('refuels')
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
                'Nenhum abastecimento pendente',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final plate = data['plate'] ?? 'Sem Matrícula';
              final liters = data['liters'] ?? 0.0;
              final timestamp = data['timestamp'] as Timestamp?;
              String dateStr = 'Data desconhecida';
              if (timestamp != null) {
                dateStr = DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate());
              }

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.local_gas_station, color: Colors.orange),
                  title: Text('$plate'),
                  subtitle: Text('$liters L • $dateStr'),
                  trailing: const Icon(Icons.edit, color: Colors.grey, size: 20),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NewRefuelScreen(existingDoc: docs[index]),
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
            MaterialPageRoute(builder: (context) => const NewRefuelScreen()),
          );
        },
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
