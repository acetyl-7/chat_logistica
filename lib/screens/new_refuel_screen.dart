import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
// Extracted from dashboard_screen.dart (or shared)
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

class NewRefuelScreen extends StatefulWidget {
  final DocumentSnapshot? existingDoc;
  const NewRefuelScreen({super.key, this.existingDoc});

  @override
  State<NewRefuelScreen> createState() => _NewRefuelScreenState();
}

class _NewRefuelScreenState extends State<NewRefuelScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _trailerPlateController = TextEditingController();
  final TextEditingController _litersController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  File? _receiptImage;

  String? _selectedFuelType;
  bool _isFullTank = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingDoc != null) {
      final data = widget.existingDoc!.data() as Map<String, dynamic>;
      _plateController.text = data['plate'] ?? '';
      _trailerPlateController.text = data['trailerPlate'] ?? '';
      _litersController.text = data['liters']?.toString() ?? '';
      _notesController.text = data['notes'] ?? '';
      _selectedFuelType = data['fuelType'];
      _isFullTank = data['fullTank'] ?? false;
    }
  }

  final List<String> _fuelTypes = [
    'Gasóleo Simples',
    'Gasóleo Aditivado',
    'AdBlue',
  ];

  @override
  void dispose() {
    _plateController.dispose();
    _trailerPlateController.dispose();
    _litersController.dispose();
    _notesController.dispose();
    super.dispose();
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

  Future<void> _pickReceiptImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (image != null) {
      setState(() {
        _receiptImage = File(image.path);
      });
    }
  }

  Future<void> _submitRefuel() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedFuelType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o tipo de combustível')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Abastecimento'),
        content: const Text('Tem a certeza que deseja registar este abastecimento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final hasPermission = await _checkLocationPermissions(context);
      if (!hasPermission) return;

      final String? driverId = FirebaseAuth.instance.currentUser?.uid;
      
      if (driverId == null) {
        throw Exception('Utilizador não autenticado');
      }

      final double liters = double.tryParse(_litersController.text.replaceAll(',', '.')) ?? 0.0;

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

      final List<ConnectivityResult> connectivityResult = await Connectivity().checkConnectivity();
      final bool isOnline = connectivityResult.contains(ConnectivityResult.mobile) || 
                           connectivityResult.contains(ConnectivityResult.wifi) ||
                           connectivityResult.contains(ConnectivityResult.ethernet);

      String? receiptUrl;
      String? localImagePath;

      if (_receiptImage != null) {
        if (isOnline) {
          final String timestampStr = DateTime.now().millisecondsSinceEpoch.toString();
          final String storagePath = 'refuels/$driverId/$timestampStr.jpg';
          final Reference ref = FirebaseStorage.instance.ref().child(storagePath);
          final UploadTask uploadTask = ref.putFile(_receiptImage!);
          final TaskSnapshot snapshot = await uploadTask;
          receiptUrl = await snapshot.ref.getDownloadURL();
        } else {
          final Directory appDocDir = await getApplicationDocumentsDirectory();
          final String safeDirPath = '${appDocDir.path}/offline_images';
          await Directory(safeDirPath).create(recursive: true);
          final String fileName = 'refuel_${driverId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          localImagePath = '$safeDirPath/$fileName';
          await _receiptImage!.copy(localImagePath);
        }
      }

      final Map<String, dynamic> refuelData = {
        'driverId': driverId,
        'plate': _plateController.text.trim().toUpperCase(),
        'trailerPlate': _trailerPlateController.text.trim().toUpperCase(),
        'location': location,
        'fuelType': _selectedFuelType,
        'liters': liters,
        'fullTank': _isFullTank,
        'notes': _notesController.text.trim(),
        'timestamp': Timestamp.now(),
        'status': 'pending',
      };

      if (receiptUrl != null) {
        refuelData['receiptUrl'] = receiptUrl;
      } else if (localImagePath != null) {
        refuelData['localImagePath'] = localImagePath;
        refuelData['needsImageSync'] = true;
      } else if (widget.existingDoc != null) {
        refuelData['receiptUrl'] = (widget.existingDoc?.data() as Map<String, dynamic>?)?['receiptUrl'];
      }

      if (widget.existingDoc == null) {
        final docRef = FirebaseFirestore.instance.collection('refuels').doc();
        final userRef = FirebaseFirestore.instance.collection('users').doc(driverId);
        final Map<String, dynamic> userUpdate = {
          'unreadRefuels': FieldValue.increment(1),
        };
        if (receiptUrl != null || localImagePath != null) {
          userUpdate['unreadImages'] = FieldValue.increment(1);
        }

        if (isOnline) {
          await docRef.set(refuelData);
          await userRef.set(userUpdate, SetOptions(merge: true)).catchError((_){});
        } else {
          docRef.set(refuelData); // Não aguarda offline para evitar travamentos
          userRef.set(userUpdate, SetOptions(merge: true)).catchError((_){});
        }
      } else {
        if (isOnline) {
          await widget.existingDoc!.reference.update(refuelData);
        } else {
          widget.existingDoc!.reference.update(refuelData);
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOnline 
            ? (widget.existingDoc == null ? 'Abastecimento registado com sucesso!' : 'Abastecimento atualizado com sucesso!')
            : 'Guardado offline. As imagens serão enviadas quando houver internet.'),
          backgroundColor: isOnline ? Colors.green : Colors.orange,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao registar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? existingUrl = (widget.existingDoc?.data() as Map<String, dynamic>?)?['receiptUrl'];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingDoc == null ? 'Registo de Abastecimento' : 'Editar Abastecimento'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _plateController,
                  decoration: const InputDecoration(
                    labelText: 'Matrícula do Veículo',
                    hintText: 'Ex: XX-XX-XX',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.directions_car),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    MaskTextInputFormatter(
                      mask: 'XX-XX-XX',
                      filter: {"X": RegExp(r'[a-zA-Z0-9]')},
                      type: MaskAutoCompletionType.lazy,
                    ),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor, insira a matrícula';
                    }
                    final regex = RegExp(
                      r'^[A-Z0-9]{2}-[A-Z0-9]{2}-[A-Z0-9]{2}$',
                      caseSensitive: false,
                    );
                    if (!regex.hasMatch(value.trim())) {
                      return 'Formato inválido. Use XX-XX-XX';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _trailerPlateController,
                  decoration: const InputDecoration(
                    labelText: 'Matrícula do Reboque (Opcional)',
                    hintText: 'Ex: L-143567, VI-145326',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.directions_car),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
                  ],
                  validator: (value) {
                    // No validation required for trailer plate format
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Combustível',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.local_gas_station),
                  ),
                  value: _selectedFuelType,
                  items: _fuelTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedFuelType = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Por favor, selecione o tipo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _litersController,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade de Litros',
                    hintText: 'Ex: 50.5',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.water_drop),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor, insira a quantidade';
                    }
                    final number = double.tryParse(value.replaceAll(',', '.'));
                    if (number == null || number <= 0) {
                      return 'Valor inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: BorderSide(color: Colors.grey.shade400),
                  ),
                  child: SwitchListTile(
                    title: const Text('Atestou o depósito?'),
                    subtitle: const Text('Selecione caso tenha enchido o depósito completamente'),
                    value: _isFullTank,
                    onChanged: (value) {
                      setState(() {
                        _isFullTank = value;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Observações (Opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _pickReceiptImage,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Anexar Talão'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                if (_receiptImage != null || ((widget.existingDoc?.data() as Map<String, dynamic>?)?['receiptUrl'] != null && (widget.existingDoc!.data() as Map<String, dynamic>)['receiptUrl'].toString().isNotEmpty)) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _receiptImage != null
                              ? Image.file(_receiptImage!, width: 120, height: 120, fit: BoxFit.cover)
                              : Image.network((widget.existingDoc!.data() as Map<String, dynamic>)['receiptUrl'].toString(), width: 120, height: 120, fit: BoxFit.cover),
                        ),
                        if (_receiptImage != null)
                          GestureDetector(
                            onTap: () => setState(() => _receiptImage = null),
                            child: Container(
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(Icons.close, color: Colors.white, size: 20),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRefuel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(widget.existingDoc == null ? 'Registar Abastecimento' : 'Guardar Alterações'),
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
