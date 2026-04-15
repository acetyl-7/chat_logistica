import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

class NewIncidentScreen extends StatefulWidget {
  final DocumentSnapshot? existingDoc;
  const NewIncidentScreen({super.key, this.existingDoc});

  @override
  State<NewIncidentScreen> createState() => _NewIncidentScreenState();
}

class _NewIncidentScreenState extends State<NewIncidentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _plateController = TextEditingController();
  final _kmsController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _customReasonController = TextEditingController();

  String? _selectedType;
  final List<String> _incidentTypes = [
    'Acidente',
    'Material Danificado',
    'Outro'
  ];

  DateTime _selectedDate = DateTime.now();

  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedImages = [];

  bool _isLoading = false;
  List<String> _existingImageUrls = [];

  @override
  void initState() {
    super.initState();
    if (widget.existingDoc != null) {
      final data = widget.existingDoc!.data() as Map<String, dynamic>;
      _plateController.text = data['plate'] ?? '';
      _kmsController.text = data['kms']?.toString() ?? '';
      _descriptionController.text = data['description'] ?? '';
      _selectedType = data['type'];
      if (data['incidentDate'] != null) {
        _selectedDate = (data['incidentDate'] as Timestamp).toDate();
      }
      _existingImageUrls = List<String>.from(data['imageUrls'] ?? []);
    }
  }

  Future<bool> _checkLocationPermissions(BuildContext context) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ative a localização do dispositivo.')),
      );
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de localização recusada.')),
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissão permanentemente recusada. Dê a permissão nas definições da app.')),
      );
      return false;
    }

    return true;
  }

  Future<void> _pickDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
      );
      if (pickedTime != null) {
        setState(() {
          _selectedDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  Future<void> _pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage(
      imageQuality: 90,
    );
    if (images.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(images);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecione o tipo de incidente')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final hasPermission = await _checkLocationPermissions(context);
      if (!hasPermission) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Utilizador não autenticado');
      }
      final String driverId = user.uid;
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      
      List<String> imageUrls = List<String>.from(_existingImageUrls);
      
      final List<ConnectivityResult> connectivityResult = await Connectivity().checkConnectivity();
      final bool isOnline = connectivityResult.contains(ConnectivityResult.mobile) || 
                           connectivityResult.contains(ConnectivityResult.wifi) ||
                           connectivityResult.contains(ConnectivityResult.ethernet);

      List<String> localImagePaths = [];

      if (isOnline) {
        // Upload das Imagens em Loop
        for (int i = 0; i < _selectedImages.length; i++) {
          final File file = File(_selectedImages[i].path);
          final String storagePath = 'incidents/$driverId/${timestamp}_$i.jpg';
          final Reference ref = FirebaseStorage.instance.ref().child(storagePath);
          
          final UploadTask uploadTask = ref.putFile(file);
          final TaskSnapshot snapshot = await uploadTask;
          final String downloadUrl = await snapshot.ref.getDownloadURL();
          imageUrls.add(downloadUrl);
        }
      } else {
        // Guardar Localmente
        final Directory appDocDir = await getApplicationDocumentsDirectory();
        final String safeDirPath = '${appDocDir.path}/offline_images';
        await Directory(safeDirPath).create(recursive: true);

        for (int i = 0; i < _selectedImages.length; i++) {
          final File file = File(_selectedImages[i].path);
          final String fileName = 'incident_${driverId}_${timestamp}_$i.jpg';
          final String localPath = '$safeDirPath/$fileName';
          await file.copy(localPath);
          localImagePaths.add(localPath);
        }
      }

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        position = lastKnown ?? Position(
          latitude: 0.0,
          longitude: 0.0,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }
      GeoPoint location = GeoPoint(position.latitude, position.longitude);

      final Map<String, dynamic> incidentData = {
        'driverId': driverId,
        'type': _selectedType,
        'customReason': _selectedType == 'Outro' ? _customReasonController.text : null,
        'plate': _plateController.text.trim().toUpperCase(),
        'kms': _kmsController.text.trim(),
        'description': _descriptionController.text.trim(),
        'incidentDate': Timestamp.fromDate(_selectedDate),
        'timestamp': Timestamp.now(),
        'location': location,
        'status': 'pending',
      };

      if (isOnline) {
        incidentData['imageUrls'] = imageUrls;
      } else {
        incidentData['imageUrls'] = imageUrls; // Mantém existentes
        if (localImagePaths.isNotEmpty) {
          incidentData['localImagePaths'] = localImagePaths;
          incidentData['needsImageSync'] = true;
        }
      }

      if (widget.existingDoc == null) {
        final docRef = FirebaseFirestore.instance.collection('incidents').doc();
        final userRef = FirebaseFirestore.instance.collection('users').doc(driverId);
        int imageCount = imageUrls.length + localImagePaths.length;
        final Map<String, dynamic> userUpdate = {
          'unreadIncidents': FieldValue.increment(1),
        };
        if (imageCount > 0) {
          userUpdate['unreadImages'] = FieldValue.increment(imageCount);
        }

        if (isOnline) {
          await docRef.set(incidentData);
          await userRef.set(userUpdate, SetOptions(merge: true)).catchError((_){});
        } else {
          docRef.set(incidentData); // Não aguarda offline para evitar travamentos
          userRef.set(userUpdate, SetOptions(merge: true)).catchError((_){});
        }
      } else {
        if (isOnline) {
          await widget.existingDoc!.reference.update(incidentData);
        } else {
          widget.existingDoc!.reference.update(incidentData);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOnline 
            ? (widget.existingDoc == null ? 'Incidente registado com sucesso!' : 'Incidente atualizado com sucesso!')
            : 'Guardado offline. As imagens serão enviadas quando houver internet.'),
          backgroundColor: isOnline ? Colors.green : Colors.orange,
        ),
      );
      Navigator.of(context).pop();

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao registar o incidente: $e')),
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
  void dispose() {
    _plateController.dispose();
    _kmsController.dispose();
    _descriptionController.dispose();
    _customReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingDoc == null ? 'Registar Incidente' : 'Editar Incidente'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Incidente',
                        border: OutlineInputBorder(),
                      ),
                      value: _selectedType,
                      items: _incidentTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedType = value;
                        });
                      },
                      validator: (value) => value == null ? 'Obrigatório selecionar o Tipo' : null,
                    ),
                    const SizedBox(height: 16),
                    if (_selectedType == 'Outro') ...[
                      TextFormField(
                        controller: _customReasonController,
                        decoration: const InputDecoration(
                          labelText: 'Motivo Customizado',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if ((value == null || value.trim().isEmpty) &&
                              _selectedType == 'Outro') {
                            return 'Obrigatório preencher o motivo customizado';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _plateController,
                      decoration: const InputDecoration(
                        labelText: 'Matrícula do Veículo (Obrigatório)',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
                      ],
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'A Matrícula é obrigatória' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _kmsController,
                      decoration: const InputDecoration(
                        labelText: 'Quilómetros (KMs)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descrição detalhada do que aconteceu',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      title: const Text('Data/Hora do Incidente'),
                      subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(_selectedDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: _pickDateTime,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (context) => SafeArea(
                            child: Wrap(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.camera_alt),
                                  title: const Text('Tirar Foto'),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
                                    if (image != null) {
                                      setState(() {
                                        _selectedImages.add(image);
                                      });
                                    }
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.photo_library),
                                  title: const Text('Escolher da Galeria'),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final List<XFile> images = await _picker.pickMultiImage(imageQuality: 90);
                                    if (images.isNotEmpty) {
                                      setState(() {
                                        _selectedImages.addAll(images);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Anexar Fotografias'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    if (_existingImageUrls.isNotEmpty || _selectedImages.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ..._existingImageUrls.map((url) => ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  url,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                                ),
                              )),
                          ..._selectedImages.asMap().entries.map((entry) {
                            int idx = entry.key;
                            XFile image = entry.value;
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(image.path),
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () => _removeImage(idx),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange.shade600,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(widget.existingDoc == null ? 'Registar Incidente' : 'Guardar Alterações'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
