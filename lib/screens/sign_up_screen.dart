import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _companyPhoneController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  // TODO: Alterar para o IP/porta de produção quando disponível
  static const String _apiBaseUrl = 'http://10.0.2.2:5000'; // 10.0.2.2 = localhost no emulador Android

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _companyPhoneController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Valida o telemóvel de empresa contra a BD via FleetSyncService
  Future<bool> _validateCompanyPhone(String phone) async {
    try {
      // Normalizar: remover espaços e traços
      final normalized = phone.replaceAll(RegExp(r'[\s\-]'), '');
      
      final uri = Uri.parse('$_apiBaseUrl/api/validate-phone?phone=$normalized');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Erro ao validar telemóvel: $e');
      return false;
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final name = _nameController.text.trim();
    final nickname = _nicknameController.text.trim();
    final companyPhone = _companyPhoneController.text.trim();
    final company = _companyController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      // ─── PASSO 1: Validar telemóvel de empresa ───────────────────────
      final isPhoneValid = await _validateCompanyPhone(companyPhone);
      if (!isPhoneValid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Telemóvel de empresa não encontrado.\nContacta o teu gestor de frota.',
              style: TextStyle(fontSize: 18),
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // ─── PASSO 2: Criar conta Firebase (telemóvel válido) ────────────
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user;
      if (user != null) {
        // Guardar no Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'name': name,
          'nickname': nickname,
          'email': email,
          'phone': companyPhone,
          'company': company,
          'role': 'Driver',
          'isAuthorized': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // ─── PASSO 3: Registar na tabela dbo.driver ────────────────────
        try {
          final registerUri = Uri.parse('$_apiBaseUrl/api/drivers/register');
          await http.post(
            registerUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'firebaseUid': user.uid,
              'email': email,
              'phoneNumber': companyPhone,
            }),
          ).timeout(const Duration(seconds: 10));
          debugPrint('Driver registado na BD com sucesso: ${user.uid}');
        } catch (e) {
          // Não bloquear o registo se falhar a inserção na BD
          // O Worker pode reconciliar mais tarde
          debugPrint('Aviso: Falha ao registar driver na BD: $e');
        }

        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? 'Erro ao criar conta',
            style: const TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Erro inesperado ao registar. Tenta outra vez.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Criar Conta',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Preenche os detalhes para criar a tua conta.',
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
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
                    controller: _nicknameController,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: 'Alcunha (Obrigatório)',
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
                        return 'Introduz a tua alcunha';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _companyPhoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: 'Telemóvel de Empresa',
                      hintText: 'Ex: 912345678',
                      labelStyle: const TextStyle(fontSize: 18),
                      hintStyle: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                      prefixIcon: const Icon(Icons.business, size: 24),
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
                        return 'Introduz o telemóvel de empresa';
                      }
                      final digits = value.replaceAll(RegExp(r'[\s\-]'), '');
                      if (digits.length < 9) {
                        return 'Número inválido (mínimo 9 dígitos)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _companyController,
                    textCapitalization: TextCapitalization.words,
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
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: 'Email',
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
                        return 'Introduz o email';
                      }
                      if (!value.contains('@')) {
                        return 'Email inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: 'Password',
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
                        return 'Introduz a password';
                      }
                      if (value.trim().length < 6) {
                        return 'Mínimo 6 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 64,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
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
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            )
                          : const Text('Registar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
