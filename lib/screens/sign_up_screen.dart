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
  final TextEditingController _companyPhoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _selectedCompany;
  bool _isLoading = false;
  static const String _apiBaseUrl = 'http://192.168.1.215:5000';

  static const List<String> _companies = [
    'Patinter',
    'Cisterpor',
    'António Frade',
    'PCDA',
  ];

  @override
  void dispose() {
    _companyPhoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Valida o telemóvel e devolve os dados do motorista (alcunha, id)
  Future<Map<String, dynamic>?> _validateCompanyPhone(String phone) async {
    try {
      final normalized = phone.replaceAll(RegExp(r'[\s\-]'), '');
      final uri = Uri.parse('$_apiBaseUrl/api/validate-phone?phone=$normalized');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('[REGISTO] Erro ao validar telemóvel: $e');
      return null;
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final companyPhone = _companyPhoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      // ─── PASSO 1: Validar telemóvel e obter dados do motorista ───────
      debugPrint('[REGISTO] Passo 1: A validar telemóvel...');
      final motoristaData = await _validateCompanyPhone(companyPhone);
      if (motoristaData == null) {
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
        setState(() => _isLoading = false);
        return;
      }

      final alcunha = motoristaData['alcunha'] as String? ?? '';
      debugPrint('[REGISTO] Passo 1: Motorista encontrado: $alcunha');

      // ─── PASSO 2: Criar conta Firebase ───────────────────────────────
      debugPrint('[REGISTO] Passo 2: A criar conta Firebase...');
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw Exception('Timeout ao criar conta. Verifica a ligação à internet.'),
          );
      debugPrint('[REGISTO] Passo 2: Conta criada: ${userCredential.user?.uid}');

      final user = userCredential.user;
      if (user != null) {
        // Guardar no Firestore com dados vindos da BD
        debugPrint('[REGISTO] Passo 2b: A guardar no Firestore...');
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'nickname': alcunha,
          'name': alcunha,
          'email': email,
          'phone': companyPhone,
          'company': _selectedCompany ?? '',
          'role': 'Driver',
          'isAuthorized': false,
          'createdAt': FieldValue.serverTimestamp(),
        }).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('Timeout ao guardar dados. Tenta outra vez.'),
        );
        debugPrint('[REGISTO] Passo 2b: Dados guardados no Firestore!');

        // ─── PASSO 3: Registar na tabela dbo.driver ──────────────────
        debugPrint('[REGISTO] Passo 3: A registar na BD SQL...');
        try {
          final registerUri = Uri.parse('$_apiBaseUrl/api/drivers/register');
          final response = await http.post(
            registerUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'firebaseUid': user.uid,
              'email': email,
              'phoneNumber': companyPhone,
            }),
          ).timeout(const Duration(seconds: 10));
          debugPrint('[REGISTO] Passo 3: BD respondeu com status ${response.statusCode}');
        } catch (e) {
          debugPrint('[REGISTO] Passo 3 (aviso): Falha ao registar na BD: $e');
        }

        debugPrint('[REGISTO] Registo concluído com sucesso!');
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[REGISTO] Erro Firebase Auth: ${e.code} - ${e.message}');
      if (!mounted) return;
      String mensagem = e.message ?? 'Erro ao criar conta';
      if (e.code == 'email-already-in-use') {
        mensagem = 'Este email já está registado. Usa outro email ou faz login.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem, style: const TextStyle(fontSize: 18)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      debugPrint('[REGISTO] Erro inesperado: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('Timeout') ? e.toString() : 'Erro inesperado ao registar. Tenta outra vez.',
            style: const TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Criar Conta',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                    'Preenche os teus dados para criar a conta.',
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // ── Telemóvel de Empresa ──────────────────────────────
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Introduz o telemóvel de empresa';
                      }
                      final digits = value.replaceAll(RegExp(r'[\s\-]'), '');
                      if (digits.length < 9) return 'Número inválido (mínimo 9 dígitos)';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // ── Empresa (Dropdown) ────────────────────────────────
                  DropdownButtonFormField<String>(
                    value: _selectedCompany,
                    decoration: InputDecoration(
                      labelText: 'Empresa',
                      labelStyle: const TextStyle(fontSize: 18),
                      prefixIcon: const Icon(Icons.local_shipping, size: 24),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    ),
                    style: const TextStyle(fontSize: 18, color: Colors.black87),
                    items: _companies
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedCompany = value),
                    validator: (value) =>
                        value == null ? 'Seleciona a tua empresa' : null,
                  ),
                  const SizedBox(height: 20),

                  // ── Email ─────────────────────────────────────────────
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: const TextStyle(fontSize: 18),
                      prefixIcon: const Icon(Icons.email_outlined, size: 24),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Introduz o email';
                      if (!value.contains('@')) return 'Email inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // ── Password ──────────────────────────────────────────
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(fontSize: 18),
                      prefixIcon: const Icon(Icons.lock_outline, size: 24),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Introduz a password';
                      if (value.trim().length < 6) return 'Mínimo 6 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // ── Botão Registar ────────────────────────────────────
                  SizedBox(
                    height: 64,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade800,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
