import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/user_profile_service.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _matriculaController = TextEditingController();
  final TextEditingController _empresaController = TextEditingController();
  bool _isSaving = false;

  final UserProfileService _profileService = UserProfileService();

  @override
  void dispose() {
    _nomeController.dispose();
    _matriculaController.dispose();
    _empresaController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sessão perdida. Faz login novamente.',
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final profile = UserProfile(
      uid: user.uid,
      nome: _nomeController.text.trim(),
      matricula: _matriculaController.text.trim(),
      empresa: _empresaController.text.trim(),
    );

    try {
      await _profileService.saveUserProfile(profile);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Erro ao guardar dados. Tenta outra vez.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Dados do Motorista',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Preenche os teus dados para o apoio saber quem está a falar.',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nomeController,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    labelText: 'Nome',
                    labelStyle: const TextStyle(fontSize: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Introduz o teu nome';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _matriculaController,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    labelText: 'Matrícula',
                    labelStyle: const TextStyle(fontSize: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Introduz a matrícula';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _empresaController,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    labelText: 'Empresa',
                    labelStyle: const TextStyle(fontSize: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Introduz a empresa';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 64,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade800,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          )
                        : const Text('Guardar e continuar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

