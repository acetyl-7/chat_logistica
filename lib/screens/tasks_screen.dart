import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../main.dart'; // Para controlar a variável isTasksOpen

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  @override
  void initState() {
    super.initState();
    isTasksOpen = true; // Previne notificações repetidas quando no ecrã de tarefas
  }

  @override
  void dispose() {
    isTasksOpen = false; // Volta a permitir notificações
    super.dispose();
  }

  Future<bool> _checkLocationPermissions(BuildContext context) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, ative a localização do dispositivo.'),
        ),
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
        const SnackBar(
          content: Text(
            'Permissão permanentemente recusada. Dê a permissão nas definições da app.',
          ),
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> _startTask(BuildContext context, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Iniciar Tarefa'),
        content: const Text(
          'Tens a certeza que queres iniciar esta tarefa agora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sim, Iniciar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final hasPermission = await _checkLocationPermissions(context);
      if (!hasPermission) return;

      // Guard: o context pode ter sido desmontado enquanto esperava permissão
      if (!context.mounted) return;

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        // Fallback para a última posição conhecida se timeout ou erro
        final lastKnown = await Geolocator.getLastKnownPosition();
        position = lastKnown ??
            Position(
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

      FirebaseFirestore.instance.collection('tasks').doc(docId).update({
        'status': 'in_progress',
        'startedAt': Timestamp.now(),
        'startLocation': GeoPoint(position.latitude, position.longitude),
      }).catchError((e) {
        debugPrint('Erro ao iniciar tarefa (offline/online): $e');
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao iniciar tarefa: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _completeTask(
    BuildContext context,
    String docId,
    Map<String, dynamic> taskData,
  ) async {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController _guiaController = TextEditingController();
    File? _guiaImage;
    File? _operationImage;
    bool _isUploading = false;

    final bool requiresPhotos = taskData['requiresPhotos'] == true;
    final String opType = taskData['operationType']?.toString() ?? 'Carga';
    final bool isCargaDescarga =
        opType == 'Carga' || opType == 'Descarga' || opType.isEmpty;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stfContext, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Comprovativo de Entrega',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 500,
                child: _isUploading
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Fazendo upload do comprovativo...'),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Conclusão de Tarefa',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (isCargaDescarga) ...[
                                TextFormField(
                                  controller: _guiaController,
                                  decoration: const InputDecoration(
                                    labelText: 'Número da Guia',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.receipt),
                                    contentPadding: EdgeInsets.all(12),
                                  ),
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'Campo obrigatório para Carga/Descarga'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final ImagePicker picker = ImagePicker();
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.camera,
                                    );
                                    if (image != null) {
                                      setStateDialog(() {
                                        _guiaImage = File(image.path);
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.photo_camera),
                                  label: const Text('Anexar Foto da Guia'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey.shade100,
                                    foregroundColor: Colors.black,
                                    side: BorderSide(
                                      color: Colors.grey.shade400,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                if (_guiaImage != null) ...[
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      _guiaImage!,
                                      height: 140,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                              ] else ...[
                                TextFormField(
                                  controller: _guiaController,
                                  decoration: const InputDecoration(
                                    labelText: 'Número da Guia (Opcional)',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.receipt),
                                    contentPadding: EdgeInsets.all(12),
                                  ),
                                  textCapitalization:
                                      TextCapitalization.characters,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final ImagePicker picker = ImagePicker();
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.camera,
                                    );
                                    if (image != null) {
                                      setStateDialog(() {
                                        _guiaImage = File(image.path);
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.photo_camera),
                                  label: const Text(
                                    'Anexar Foto da Guia (Opcional)',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey.shade100,
                                    foregroundColor: Colors.black,
                                    side: BorderSide(
                                      color: Colors.grey.shade400,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                if (_guiaImage != null) ...[
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      _guiaImage!,
                                      height: 140,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                              ],

                              if (requiresPhotos) ...[
                                const Divider(),
                                const SizedBox(height: 8),
                                const Text(
                                  'FOTOGRAFIA OBRIGATÓRIA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                                const Text(
                                  'Esta operação requer que registe uma imagem do estado/ocorrência.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final ImagePicker picker = ImagePicker();
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.camera,
                                    );
                                    if (image != null) {
                                      setStateDialog(() {
                                        _operationImage = File(image.path);
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.camera_alt),
                                  label: const Text('Anexar Foto da Operação'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade50,
                                    foregroundColor: Colors.orange.shade800,
                                    side: BorderSide(
                                      color: Colors.orange.shade200,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                if (_operationImage != null) ...[
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      _operationImage!,
                                      height: 140,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
              actions: _isUploading
                  ? []
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancelar'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          if (!_formKey.currentState!.validate()) return;
                          if (isCargaDescarga && _guiaImage == null) {
                            ScaffoldMessenger.of(stfContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Por favor, anexe a foto da Guia.',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          if (requiresPhotos && _operationImage == null) {
                            ScaffoldMessenger.of(stfContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Por favor, anexe a foto obrigatória da operação.',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setStateDialog(() {
                            _isUploading = true;
                          });

                          try {
                            final hasPermission =
                                await _checkLocationPermissions(context);
                            if (!hasPermission) {
                              setStateDialog(() => _isUploading = false);
                              return;
                            }
                            Position position;
                            try {
                              position = await Geolocator.getCurrentPosition(
                                desiredAccuracy: LocationAccuracy.high,
                                timeLimit: const Duration(seconds: 10),
                              );
                            } catch (_) {
                              final lastKnown =
                                  await Geolocator.getLastKnownPosition();
                              position =
                                  lastKnown ??
                                  Position(
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

                            final String? driverId =
                                FirebaseAuth.instance.currentUser?.uid;
                            if (driverId == null)
                              throw Exception('Utilizador não autenticado');

                            final connectivityResult = await Connectivity()
                                .checkConnectivity();
                            final bool isOffline = connectivityResult.contains(
                              ConnectivityResult.none,
                            );

                            String? downloadUrl;
                            String? localImagePath;
                            String? operationImageUrl;
                            String? localOperationImagePath;

                            final Directory appDocDir =
                                await getApplicationDocumentsDirectory();
                            final String safeDirPath =
                                '${appDocDir.path}/offline_images';

                            if (isOffline) {
                              if (_guiaImage != null) {
                                await Directory(
                                  safeDirPath,
                                ).create(recursive: true);
                                final String fileName =
                                    'task_${docId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                localImagePath = '$safeDirPath/$fileName';
                                await _guiaImage!.copy(localImagePath);
                              }
                              if (_operationImage != null) {
                                await Directory(
                                  safeDirPath,
                                ).create(recursive: true);
                                final String fileName =
                                    'task_op_${docId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                localOperationImagePath =
                                    '$safeDirPath/$fileName';
                                await _operationImage!.copy(
                                  localOperationImagePath,
                                );
                              }
                            } else {
                              if (_guiaImage != null) {
                                final String storagePath =
                                    'tasks/$driverId/${docId}_guia.jpg';
                                final Reference ref = FirebaseStorage.instance
                                    .ref()
                                    .child(storagePath);
                                final UploadTask uploadTask = ref.putFile(
                                  _guiaImage!,
                                );
                                final TaskSnapshot snapshot = await uploadTask;
                                downloadUrl = await snapshot.ref
                                    .getDownloadURL();
                              }
                              if (_operationImage != null) {
                                final String storagePath =
                                    'tasks/$driverId/${docId}_operation.jpg';
                                final Reference ref = FirebaseStorage.instance
                                    .ref()
                                    .child(storagePath);
                                final UploadTask uploadTask = ref.putFile(
                                  _operationImage!,
                                );
                                final TaskSnapshot snapshot = await uploadTask;
                                operationImageUrl = await snapshot.ref
                                    .getDownloadURL();
                              }
                            }

                            final Map<String, dynamic> updateData = {
                              'status': 'completed',
                              'completedAt': Timestamp.now(),
                              'completeLocation': GeoPoint(
                                position.latitude,
                                position.longitude,
                              ),
                              'guiaNumber': _guiaController.text
                                  .trim()
                                  .toUpperCase(),
                            };

                            if (downloadUrl != null) {
                              updateData['guiaImageUrl'] = downloadUrl;
                            }
                            if (localImagePath != null) {
                              updateData['localImagePath'] = localImagePath;
                              updateData['needsImageSync'] = true;
                            }
                            if (operationImageUrl != null) {
                              updateData['operationImageUrl'] =
                                  operationImageUrl;
                            }
                            if (localOperationImagePath != null) {
                              updateData['localOperationImagePath'] =
                                  localOperationImagePath;
                              updateData['needsImageSync'] = true;
                            }

                            int imagesAdded = 0;
                            if (downloadUrl != null || localImagePath != null) imagesAdded++;
                            if (operationImageUrl != null || localOperationImagePath != null) imagesAdded++;

                            final userRef = FirebaseFirestore.instance.collection('users').doc(driverId);
                            final Map<String, dynamic> userUpdate = {
                              'unreadTasks': FieldValue.increment(1),
                            };
                            if (imagesAdded > 0) {
                              userUpdate['unreadImages'] = FieldValue.increment(imagesAdded);
                            }

                            if (isOffline) {
                              FirebaseFirestore.instance
                                  .collection('tasks')
                                  .doc(docId)
                                  .update(updateData)
                                  .catchError((e) {
                                    debugPrint('Erro na submissão offline: $e');
                                  });
                              userRef.set(userUpdate, SetOptions(merge: true)).catchError((_) {});
                            } else {
                              await FirebaseFirestore.instance
                                  .collection('tasks')
                                  .doc(docId)
                                  .update(updateData);
                              await userRef.set(userUpdate, SetOptions(merge: true)).catchError((_) {});
                            }

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isOffline
                                        ? 'Guardado offline. As imagens serão enviadas quando houver internet.'
                                        : 'Tarefa concluída com sucesso! 🎉',
                                  ),
                                  backgroundColor: isOffline
                                      ? Colors.orange
                                      : Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            debugPrint('Erro na submissão: $e');
                            if (stfContext.mounted) {
                              ScaffoldMessenger.of(stfContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Erro ao guardar. Tente novamente.',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                            if (stfContext.mounted) {
                              setStateDialog(() {
                                _isUploading = false;
                              });
                            }
                          } finally {
                            // Garante que o loading/dialog fecha, independentemente de erro ou sucesso
                            // Usamos context do dialog para efetuar dismiss à form principal
                            if (Navigator.canPop(dialogContext)) {
                              Navigator.pop(dialogContext);
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Confirmar Conclusão'),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  void _showTaskDetails(BuildContext context, Map<String, dynamic> taskData) {
    final title = taskData['title'] ?? 'Sem título';
    final description = taskData['description'] ?? '';
    final freightId = taskData['freightId']?.toString();
    final operationLocation = taskData['operationLocation']?.toString();
    final operationType = taskData['operationType']?.toString();
    final operationTypeOther = taskData['operationTypeOther']?.toString();
    final opAddress = taskData['operationAddress']?.toString();
    final opRef = taskData['operationReference']?.toString();
    final tractorPlate = taskData['tractorPlate']?.toString();
    final trailerPlate = taskData['trailerPlate']?.toString();
    final requiresPhotos = taskData['requiresPhotos'] == true;

    Widget buildDetailRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 15, color: Colors.black87),
            children: [
              TextSpan(
                text: '$label ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (description.isNotEmpty) ...[
                  const Text(
                    'Descrição:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Detalhes da Operação:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(height: 8),
                if (freightId != null && freightId.isNotEmpty)
                  buildDetailRow('ID Frete:', freightId),
                if (operationLocation != null && operationLocation.isNotEmpty)
                  buildDetailRow('Local:', operationLocation),
                if (operationType != null && operationType.isNotEmpty)
                  buildDetailRow(
                    'Operação:',
                    '${operationType == "Outras" && operationTypeOther != null && operationTypeOther.isNotEmpty ? "$operationType - $operationTypeOther" : operationType}${requiresPhotos ? " (Fotos Obrigatórias)" : ""}',
                  ),
                if (opAddress != null && opAddress.isNotEmpty)
                  buildDetailRow('Morada:', opAddress),
                if (opRef != null && opRef.isNotEmpty)
                  buildDetailRow('Ref:', opRef),
                if (tractorPlate != null && tractorPlate.isNotEmpty)
                  buildDetailRow('Trator:', tractorPlate),
                if (trailerPlate != null && trailerPlate.isNotEmpty)
                  buildDetailRow('Reboque:', trailerPlate),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tarefas')),
        body: const Center(child: Text('Utilizador não autenticado.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tarefas',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('tasks')
              .where('driverId', isEqualTo: currentUser.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Erro ao carregar tarefas:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                ),
              );
            }

            final docs = List<QueryDocumentSnapshot>.from(
              snapshot.data?.docs ?? [],
            );

            // Ordenação local para evitar erro de index em falta no Firestore
            docs.sort((a, b) {
              final aTime =
                  (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
              final bTime =
                  (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(
                aTime,
              ); // Descending (mais recente primeiro)
            });

            // Ocultar tarefas concluídas (com exceção da última mais recente)
            bool foundCompleted = false;
            docs.retainWhere((doc) {
              final status = (doc.data() as Map<String, dynamic>)['status'];
              if (status == 'completed') {
                if (!foundCompleted) {
                  foundCompleted =
                      true; // Mantém a primeira que é a mais recente
                  return true;
                }
                return false; // Remove as restantes concluídas
              }
              return true; // Mantém pending e in_progress
            });

            if (docs.isEmpty) {
              return const Center(
                child: Text(
                  'Nenhuma tarefa atribuída no momento.',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              );
            }

            // Encontrar a primeira tarefa que NÃO está concluída (pending ou in_progress).
            // Como a lista está ordenada pela mais recente, a tarefa "ativa" (que deve ser executada)
            // é a tarefa pendente mais antiga, ou seja, a última da lista de pendentes.
            final firstActiveIndex = docs.lastIndexWhere(
              (doc) =>
                  (doc.data() as Map<String, dynamic>)['status'] != 'completed',
            );

            String? lastDate;
            final List<Widget> listItems = [];

            for (int index = 0; index < docs.length; index++) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = data['timestamp'] as Timestamp?;

              if (timestamp != null) {
                final dt = timestamp.toDate();
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final yesterday = today.subtract(const Duration(days: 1));
                final docDate = DateTime(dt.year, dt.month, dt.day);

                String groupDateStr;
                if (docDate == today) {
                  groupDateStr = 'HOJE';
                } else if (docDate == yesterday) {
                  groupDateStr = 'ONTEM';
                } else {
                  groupDateStr =
                      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
                }

                if (groupDateStr != lastDate) {
                  if (lastDate != null) {
                    listItems.add(
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(thickness: 1, color: Colors.black26),
                      ),
                    );
                  }

                  listItems.add(
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: 12,
                        top: lastDate == null ? 0 : 8,
                      ),
                      child: Text(
                        groupDateStr,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  );
                  lastDate = groupDateStr;
                }
              }

              final status = data['status'] ?? 'pending';
              final isCompleted = status == 'completed';
              final isFirstActive = index == firstActiveIndex;
              final isLocked = !isCompleted && !isFirstActive;

              listItems.add(
                _buildTaskCard(
                  context: context,
                  docId: doc.id,
                  taskData: data,
                  isCompleted: isCompleted,
                  isFirstActive: isFirstActive,
                  isLocked: isLocked,
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: listItems,
            );
          },
        ),
      ),
    );
  }

  Widget _buildTaskCard({
    required BuildContext context,
    required String docId,
    required Map<String, dynamic> taskData,
    required bool isCompleted,
    required bool isFirstActive,
    required bool isLocked,
  }) {
    final status = taskData['status'] ?? 'pending';
    final title = taskData['title'] ?? 'Sem título';
    final freightId = taskData['freightId']?.toString();
    final operationLocation = taskData['operationLocation']?.toString();
    final operationType = taskData['operationType']?.toString();
    final operationTypeOther = taskData['operationTypeOther']?.toString();
    final opAddress = taskData['operationAddress']?.toString();
    final opRef = taskData['operationReference']?.toString();
    final tractorPlate = taskData['tractorPlate']?.toString();
    final trailerPlate = taskData['trailerPlate']?.toString();
    final requiresPhotos = taskData['requiresPhotos'] == true;

    String formattedDate = '';
    if (taskData['timestamp'] != null) {
      final dt = (taskData['timestamp'] as Timestamp).toDate();
      formattedDate =
          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    // Determinar as cores e a opacidade
    final opacity = isLocked ? 0.5 : 1.0;

    Color backgroundColor;
    Color borderColor;

    if (isCompleted) {
      backgroundColor = Colors.white;
      borderColor = Colors.grey.shade300;
    } else if (isFirstActive) {
      if (status == 'in_progress') {
        backgroundColor = Colors.green.shade50;
        borderColor = Colors.green.shade400;
      } else {
        // pending
        backgroundColor = Colors.blue.shade50;
        borderColor = Colors.blue.shade400;
      }
    } else {
      backgroundColor = Colors.white;
      borderColor = Colors.grey.shade300;
    }

    return Opacity(
      opacity: opacity,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        color: backgroundColor,
        elevation: isFirstActive ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: isFirstActive ? 2 : 1),
        ),
        child: InkWell(
          onTap: () => _showTaskDetails(context, taskData),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isLocked
                              ? Colors.grey.shade700
                              : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isCompleted)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 28,
                      )
                    else if (isLocked)
                      Icon(Icons.lock, color: Colors.grey.shade600, size: 28)
                    else if (isFirstActive && status == 'in_progress')
                      const Icon(
                        Icons.play_circle_fill,
                        color: Colors.green,
                        size: 28,
                      )
                    else if (isFirstActive)
                      const Icon(
                        Icons.circle_outlined,
                        color: Colors.blue,
                        size: 28,
                      ),
                  ],
                ),
                if (formattedDate.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: isLocked
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 14,
                          color: isLocked
                              ? Colors.grey.shade500
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Toque para ver os detalhes da tarefa',
                  style: TextStyle(
                    fontSize: 12,
                    color: isLocked
                        ? Colors.grey.shade500
                        : Colors.teal.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),

                if (freightId != null && freightId.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.tag, 'ID Frete:', freightId, isLocked),
                ],
                if (operationLocation != null &&
                    operationLocation.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildInfoRow(
                    Icons.place,
                    'Local:',
                    operationLocation,
                    isLocked,
                  ),
                ],
                if (operationType != null && operationType.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildInfoRow(
                    Icons.work_outline,
                    'Operação:',
                    '${operationType == "Outras" && operationTypeOther != null && operationTypeOther.isNotEmpty ? "$operationType - $operationTypeOther" : operationType}${requiresPhotos ? " (Fotos)" : ""}',
                    isLocked,
                  ),
                ],
                if (opAddress != null && opAddress.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildInfoRow(
                    Icons.home_work_outlined,
                    'Morada:',
                    opAddress,
                    isLocked,
                  ),
                ],
                if (opRef != null && opRef.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildInfoRow(Icons.comment, 'Ref:', opRef, isLocked),
                ],
                if (tractorPlate != null && tractorPlate.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildInfoRow(
                    Icons.local_shipping,
                    'Trator:',
                    tractorPlate,
                    isLocked,
                  ),
                ],
                if (trailerPlate != null && trailerPlate.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildInfoRow(
                    Icons.rv_hookup,
                    'Reboque:',
                    trailerPlate,
                    isLocked,
                  ),
                ],

                if (isFirstActive) ...[
                  const SizedBox(height: 16),
                  if (status == 'pending')
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => _startTask(context, docId),
                        icon: const Icon(Icons.play_arrow, size: 24),
                        label: const Text(
                          'Iniciar Tarefa',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    )
                  else if (status == 'in_progress')
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _completeTask(context, docId, taskData),
                        icon: const Icon(Icons.check, size: 24),
                        label: const Text(
                          'Concluir Tarefa',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    bool isLocked,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: isLocked ? Colors.grey.shade400 : Colors.teal.shade700,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isLocked ? Colors.grey.shade500 : Colors.grey.shade800,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isLocked ? Colors.grey.shade500 : Colors.black87,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
