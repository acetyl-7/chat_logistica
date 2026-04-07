import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/profile_photo_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfilePhotoService _photoService = ProfilePhotoService();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isSavingProfile = false;
  bool _isChangingPassword = false;
  bool _isUploadingPhoto = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _companyController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSavingProfile = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'phone': _phoneController.text.trim(),
        'company': _companyController.text.trim(),
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Perfil atualizado.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Erro ao atualizar perfil.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingProfile = false;
        });
      }
    }
  }

  Future<void> _changePassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Preenche a nova password.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (newPassword != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'As passwords não coincidem.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'A nova password deve ter pelo menos 6 caracteres.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isChangingPassword = true;
    });

    try {
      await user.updatePassword(newPassword);
      if (!mounted) return;
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Password atualizada.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? 'Erro ao alterar password.',
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
            'Erro inesperado ao alterar password.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Future<void> _pickProfilePhoto(String currentUid) async {
    try {
      setState(() {
        _isUploadingPhoto = true;
      });

      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (picked == null) return;

      final file = File(picked.path);
      final url = await _photoService.uploadProfilePhoto(file);

      await FirebaseFirestore.instance.collection('users').doc(currentUid).update({'photoUrl': url});

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Foto de perfil atualizada.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Erro ao carregar foto de perfil.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Perfil do Motorista')),
        body: const Center(child: Text('Não autenticado')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Perfil do Motorista',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(child: Text('Erro ao carregar os dados.'));
            }

            final data = snapshot.data?.data() as Map<String, dynamic>?;
            if (data == null) {
              return const Center(child: Text('A carregar...'));
            }

            final String name = data['name']?.toString() ?? data['nome']?.toString() ?? '';
            final String email = data['email']?.toString() ?? user.email ?? '-';
            final String phone = data['phone']?.toString() ?? data['telefone']?.toString() ?? '';
            final String company = data['company']?.toString() ?? data['empresa']?.toString() ?? '';
            final String photoUrl = data['photoUrl']?.toString() ?? '';
            final bool isAuthorized = data['isAuthorized'] == true;

            // Only update controllers if they haven't been manually edited, to avoid cursor jumping
            if (!_isSavingProfile) {
              _nameController.text = name;
              if (phone.isNotEmpty && _phoneController.text.isEmpty) _phoneController.text = phone;
              if (company.isNotEmpty && _companyController.text.isEmpty) _companyController.text = company;
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: Colors.blueGrey.shade100,
                          backgroundImage: photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 48,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _isUploadingPhoto ? null : () => _pickProfilePhoto(user.uid),
                          child: _isUploadingPhoto
                              ? const CircularProgressIndicator()
                              : const Text(
                                  'Atualizar foto de perfil',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Nome (Read-only on this screen)
                  const Text(
                    'Nome',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: name,
                    readOnly: true,
                    style: const TextStyle(fontSize: 20, color: Colors.grey),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Email (Read-only)
                  const Text(
                    'Email',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: email,
                    readOnly: true,
                    style: const TextStyle(fontSize: 20, color: Colors.grey),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Telefone (Editable ONLY IF !isAuthorized)
                  const Text(
                    'Telefone',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    readOnly: isAuthorized,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(fontSize: 20, color: isAuthorized ? Colors.grey : Colors.black),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      filled: isAuthorized,
                      fillColor: isAuthorized ? Colors.grey.shade100 : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Empresa (Editable ONLY IF !isAuthorized)
                  const Text(
                    'Empresa',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _companyController,
                    readOnly: isAuthorized,
                    style: TextStyle(fontSize: 20, color: isAuthorized ? Colors.grey : Colors.black),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      filled: isAuthorized,
                      fillColor: isAuthorized ? Colors.grey.shade100 : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (isAuthorized)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade400),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified_user, color: Colors.green.shade800),
                          const SizedBox(width: 8),
                          Text(
                            'Perfil Autorizado',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSavingProfile ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey.shade800,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSavingProfile
                            ? const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              )
                            : const Text('Guardar Alterações'),
                      ),
                    ),

                  const SizedBox(height: 48),
                  const Text(
                    'Alterar Password',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: 'Nova password',
                      labelStyle: const TextStyle(fontSize: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: 'Confirmar password',
                      labelStyle: const TextStyle(fontSize: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isChangingPassword ? null : _changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isChangingPassword
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            )
                          : const Text('Mudar Password'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
