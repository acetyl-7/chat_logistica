import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:pattern_formatter/pattern_formatter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

import '../main.dart'; // Para aceder a flutterLocalNotificationsPlugin e isChatOpen

import '../models/trip_data.dart';
import '../screens/chat_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/refuel_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/trip_states_screen.dart';
import '../services/trip_persistence_service.dart';
import '../screens/incident_screen.dart';

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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _driverPhotoUrl;
  String? _driverDisplayName;
  bool _appBarImageError = false;

  StreamSubscription<QuerySnapshot>? _messageSubscription;
  StreamSubscription<QuerySnapshot>? _taskSubscription;
  StreamSubscription<RemoteMessage>? _fcmSubscription;
  // Usado para ignorar mensagens/tarefas históricas no arranque do listener
  late final DateTime _listenerStartTime;

  @override
  void initState() {
    super.initState();
    _listenerStartTime = DateTime.now();
    _requestPermissions();
    _loadDriverProfile();
    _setupMessageListener();
    _setupTaskListener();
    _initFCM();
  }

  Future<void> _loadDriverProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final uid = user.uid;
    final authDisplayName = user.displayName;
    
    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final doc = await docRef.get();
      
      if (doc.exists) {
        final data = doc.data()!;
        
        // --- Auto-reparação de dados (Integridade) ---
        bool needsUpdate = false;
        final Map<String, dynamic> updates = {};
        
        final firestoreEmail = data['email'] as String?;
        if ((firestoreEmail == null || firestoreEmail.trim().isEmpty) && 
            user.email != null && user.email!.isNotEmpty) {
          needsUpdate = true;
          updates['email'] = user.email;
        }

        final firestorePhone = data['phone'] as String? ?? data['telefone'] as String?;
        if ((firestorePhone == null || firestorePhone.trim().isEmpty) && 
            user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
          needsUpdate = true;
          updates['phone'] = user.phoneNumber;
        }
        
        if (needsUpdate) {
          // Atualiza em background de forma silenciosa
          docRef.update(updates).catchError((e) => debugPrint('Erro na auto-reparação: $e'));
        }
        // ---------------------------------------------
        
        if (mounted) {
          setState(() {
            _driverPhotoUrl = data['photoUrl'] as String?;
            _driverDisplayName = data['name'] as String? ?? data['displayName'] as String? ?? authDisplayName;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar perfil: $e');
    }
  }

  void _setupMessageListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      print('LISTENER: UID é null, utilizador não autenticado!');
      return;
    }
    print('LISTENER: A iniciar listener para UID=$uid');

    _messageSubscription = FirebaseFirestore.instance
        .collection('messages')
        .where('driverId', isEqualTo: uid)
        .where('sender', isEqualTo: 'hq')
        .where('status', isEqualTo: 'sent')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>?;
          if (data == null) continue;

          // Verifica se a mensagem é nova (posterior ao arranque da app)
          final ts = data['timestamp'];
          DateTime? msgTime;
          if (ts != null && ts is Timestamp) {
            msgTime = ts.toDate();
          }
          final isNew = msgTime == null || msgTime.isAfter(_listenerStartTime);

          print('LISTENER: doc=${change.doc.id} isNew=$isNew msgTime=$msgTime isChatOpen=$isChatOpen');

          if (isNew && !isChatOpen) {
            print('=== NOVA MENSAGEM DA SEDE DETETADA ===');
            _showNotification(data);
          }
        }
      }
    }, onError: (e) {
      print('LISTENER ERRO: $e');
    });
  }

  Future<void> _showNotification(Map<String, dynamic> data) async {
    final String type = data['type'] ?? 'text';
    String body = data['text'] ?? 'Nova mensagem';

    if (type == 'image') {
      body = 'Recebeu uma nova imagem da Sede';
    } else if (type == 'document') {
      body = 'Recebeu um novo documento da Sede';
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_messages_channel',
      'Mensagens de Chat',
      channelDescription: 'Notificações de novas mensagens do chat de suporte',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Nova mensagem',
    );

    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    try {
      await flutterLocalNotificationsPlugin.show(
        id: data.hashCode & 0x7FFFFFFF, // int32 positivo
        title: 'Sede (Logística)',
        body: body,
        notificationDetails: platformDetails,
      );
    } catch (e) {
      print('ERRO NOTIFICAÇÃO: $e');
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _taskSubscription?.cancel();
    _fcmSubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.notification.request();
    print('Permissão de Notificação: $status');
  }

  void _setupTaskListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    print('TASK LISTENER: A iniciar listener para UID=$uid');

    _taskSubscription = FirebaseFirestore.instance
        .collection('tasks')
        .where('driverId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>?;
          if (data == null) continue;

          final ts = data['timestamp'];
          DateTime? taskTime;
          if (ts != null && ts is Timestamp) {
            taskTime = ts.toDate();
          }
          final isNew = taskTime == null || taskTime.isAfter(_listenerStartTime);

          print('TASK LISTENER: doc=${change.doc.id} isNew=$isNew taskTime=$taskTime isTasksOpen=$isTasksOpen');

          if (isNew && !isTasksOpen) {
            print('=== NOVA TAREFA ATRIBUÍDA DETETADA ===');
            _showTaskNotification(data);
          }
        }
      }
    }, onError: (e) {
      print('TASK LISTENER ERRO: $e');
    });
  }

  Future<void> _showTaskNotification(Map<String, dynamic> data) async {
    final String title = data['title'] ?? 'Nova Tarefa';

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'tasks_channel',
      'Tarefas',
      channelDescription: 'Notificações de novas tarefas atribuídas',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Nova tarefa',
    );

    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    try {
      await flutterLocalNotificationsPlugin.show(
        id: (data.hashCode & 0x7FFFFFFF) | 0x40000000, // ID distinto das mensagens
        title: 'Nova Tarefa (Logística)',
        body: title,
        notificationDetails: platformDetails,
      );
    } catch (e) {
      print('ERRO NOTIFICAÇÃO TAREFA: $e');
    }
  }

  /// Inicializa o Firebase Cloud Messaging:
  /// guarda o token FCM no Firestore e ativa o listener de foreground.
  Future<void> _initFCM() async {
    final messaging = FirebaseMessaging.instance;

    // Pedir autorização (obrigatório em iOS, boa prática em Android 13+)
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Obter o token FCM e guardá-lo no Firestore
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final token = await messaging.getToken();
        if (token != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({'fcmToken': token});
          print('FCM TOKEN guardado: $token');
        }
      } catch (e) {
        print('ERRO ao guardar token FCM: $e');
      }

      // Atualizar o token automaticamente se mudar
      messaging.onTokenRefresh.listen((newToken) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'fcmToken': newToken})
            .catchError((e) => print('ERRO refresh token: $e'));
      });
    }

    // Listener de foreground: quando a app está aberta e chega uma notificação FCM,
    // o Android não a mostra automaticamente --- temos de a mostrar nós via local_notifications.
    _fcmSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;

      final isTask = message.data['type'] == 'task';

      if (!isTask) {
        final messageId = message.data['messageId'];
        if (messageId != null) {
          FirebaseFirestore.instance
              .collection('messages')
              .doc(messageId)
              .update({'status': 'delivered'})
              .catchError((e) => print('Erro a marcar como entregue: $e'));
        }
      }

      // Suprimir se o utilizador já está no ecrã correto
      if (isTask && isTasksOpen) return;
      if (!isTask && isChatOpen) return;

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        isTask ? 'tasks_channel' : 'chat_messages_channel',
        isTask ? 'Tarefas' : 'Mensagens de Chat',
        importance: Importance.max,
        priority: Priority.high,
      );

      flutterLocalNotificationsPlugin.show(
        id: message.hashCode & 0x7FFFFFFF,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(android: androidDetails),
      );
    });
  }

  Future<Position?> _getPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (e) {
        debugPrint('Erro ao obter localização: $e');
        return null;
      }
    }
  }

  /// Obtém a hora real do momento do clique:
  /// 1. Cloud Function getServerTime (se online)
  /// 2. Timestamp do GPS (se disponível)
  /// 3. DateTime.now() como fallback
  Future<DateTime> _getRealTime(Position? gpsPosition) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
        'getServerTime',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 5)),
      );
      final result = await callable.call();
      final ts = result.data['timestamp'];
      if (ts != null) {
        return DateTime.fromMillisecondsSinceEpoch((ts as num).toInt());
      }
    } catch (e) {
      debugPrint('Cloud Function getServerTime falhou: $e');
    }
    // Fallback: timestamp GPS
    if (gpsPosition != null) {
      return gpsPosition.timestamp;
    }
    // Fallback final
    return DateTime.now();
  }

  void _showStartDayForm() {
    final formKey = GlobalKey<FormState>();
    final tractorController = TextEditingController();
    final trailerController = TextEditingController();
    final startKmsController = TextEditingController();
    bool isSubmitting = false;
    DateTime selectedStartTime = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Iniciar Dia de Trabalho',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: tractorController,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula do Veículo (Obrigatório)',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
                    ],
                    validator: (v) => v == null || v.isEmpty ? 'Campo obrigatório' : null,
                  ),

                  const SizedBox(height: 12),
                  TextFormField(
                    controller: trailerController,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula do Reboque (Opcional)',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
                    ],
                  ),

                  const SizedBox(height: 12),
                  TextFormField(
                    controller: startKmsController,
                    decoration: const InputDecoration(
                      labelText: 'Quilómetros Iniciais (Obrigatório)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsFormatter()],
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Campo obrigatório';
                      if (double.tryParse(v.replaceAll(',', '')) == null) return 'Valor inválido';
                      return null;
                    },
                  ),

                  const SizedBox(height: 12),
                  // ── Selector de hora de início ──────────────────────────
                  ListTile(
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    leading: const Icon(Icons.access_time),
                    title: const Text('Hora de Início'),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(selectedStartTime),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.edit, size: 20),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: selectedStartTime,
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now(),
                      );
                      if (pickedDate == null) return;
                      if (!context.mounted) return;
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(selectedStartTime),
                      );
                      if (pickedTime == null) return;
                      setModalState(() {
                        selectedStartTime = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                      });
                    },
                  ),

                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setModalState(() => isSubmitting = true);

                            final pos = await _getPosition();
                            final actualTime = await _getRealTime(pos);
                            final uid = FirebaseAuth.instance.currentUser?.uid;

                            await FirebaseFirestore.instance.collection('trips').add({
                              'driverId': uid,
                              'tractorPlate': tractorController.text.trim().toUpperCase(),
                              'trailerPlate': trailerController.text.trim().toUpperCase(),
                              'startKms': double.parse(startKmsController.text.replaceAll(',', '')),
                              'startLocation': pos != null ? GeoPoint(pos.latitude, pos.longitude) : null,
                              // Hora escolhida pelo motorista
                              'startTime': Timestamp.fromDate(selectedStartTime),
                              // Hora real do clique (server time ou GPS)
                              'actualStartTime': Timestamp.fromDate(actualTime),
                              'status': 'active',
                            });

                            if (context.mounted) Navigator.pop(context);
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Iniciar dia de trabalho', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEndDayForm(DocumentSnapshot tripDoc) {
    final formKey = GlobalKey<FormState>();
    final endKmsController = TextEditingController();
    bool isSubmitting = false;
    final startKms = (tripDoc.data() as Map<String, dynamic>)['startKms'] ?? 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Terminar Dia de Trabalho',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Form(
                key: formKey,
                child: TextFormField(
                  controller: endKmsController,
                  decoration: const InputDecoration(
                    labelText: 'Quilómetros Finais (Obrigatório)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsFormatter()],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Campo obrigatório';
                    final end = double.tryParse(v.replaceAll(',', ''));
                    if (end == null) return 'Valor inválido';
                    if (end < startKms) return 'KMs finais inferiores aos iniciais ($startKms)';
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setModalState(() => isSubmitting = true);

                        final pos = await _getPosition();
                        final endKms = double.parse(endKmsController.text.replaceAll(',', ''));

                        final tripData = tripDoc.data() as Map<String, dynamic>;
                        final startTime = tripData['startTime'] as Timestamp?;
                        final uid = FirebaseAuth.instance.currentUser?.uid;

                        await tripDoc.reference.update({
                          'endKms': endKms,
                          'endLocation': pos != null ? GeoPoint(pos.latitude, pos.longitude) : null,
                          'endTime': FieldValue.serverTimestamp(),
                          'status': 'completed',
                        });

                        List<Map<String, dynamic>> completedTasks = [];
                        if (uid != null && startTime != null) {
                          try {
                            final tasksSnapshot = await FirebaseFirestore.instance
                                .collection('tasks')
                                .where('driverId', isEqualTo: uid)
                                .where('status', isEqualTo: 'completed')
                                .get();
                            
                            completedTasks = tasksSnapshot.docs
                                .map((doc) => doc.data())
                                .where((data) {
                                  if (data['completedAt'] == null) return false;
                                  final completedAt = (data['completedAt'] as Timestamp).toDate();
                                  return completedAt.isAfter(startTime.toDate()) || completedAt.isAtSameMomentAs(startTime.toDate());
                                })
                                .toList();
                          } catch (e) {
                            debugPrint('Erro ao obter tarefas concluídas: $e');
                          }
                        }

                        if (context.mounted) {
                          Navigator.pop(context);
                          _showEndOfDayReportDialog(
                            startKms: startKms,
                            endKms: endKms,
                            startTime: startTime?.toDate(),
                            tasks: completedTasks,
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                child: isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Terminar dia de trabalho', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showEndOfDayReportDialog({
    required double startKms,
    required double endKms,
    required DateTime? startTime,
    required List<Map<String, dynamic>> tasks,
  }) {
    final now = DateTime.now();
    final duration = startTime != null ? now.difference(startTime) : Duration.zero;
    
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final durationStr = '${h}h ${m}m';

    final startTimeStr = startTime != null
        ? '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final endTimeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 24, left: 24, right: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 60, color: Colors.green.shade600),
            const SizedBox(height: 16),
            const Text(
              'Dia Concluído!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('🕒 Início / Fim'),
                      Text('$startTimeStr | $endTimeStr', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('⏳ Tempo Total'),
                      Text(durationStr, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('🛣️ Distância Percorrida'),
                      Text('${(endKms - startKms).toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('✅ Tarefas Concluídas'),
                      Text('${tasks.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ],
                  ),
                ],
              ),
            ),
            if (tasks.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Resumo de Tarefas:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(tasks[index]['title'] ?? 'Tarefa')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blueGrey.shade800,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('FECHAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/fleetChatLOGOsmall.png',
          height: 40,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(),
                ),
              );
            },
            icon: () {
                final photoUrl = _driverPhotoUrl;
                final displayName = _driverDisplayName ?? FirebaseAuth.instance.currentUser?.displayName;
                final initial = displayName != null && displayName.isNotEmpty
                    ? displayName[0].toUpperCase()
                    : 'M';

                return (photoUrl != null && photoUrl.isNotEmpty && !_appBarImageError)
                    ? CircleAvatar(
                        radius: 16,
                        backgroundImage: NetworkImage(photoUrl),
                        onBackgroundImageError: (exception, stackTrace) {
                          if (mounted) {
                            setState(() {
                              _appBarImageError = true;
                            });
                          }
                        },
                      )
                    : CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.blue.shade100,
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      );
              }(),
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser?.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
            final bool isAuthorized = userData?['isAuthorized'] == true;

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('trips')
                  .where('driverId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                  .where('status', isEqualTo: 'active')
                  .limit(1)
                  .snapshots(),
              builder: (context, tripSnapshot) {
                final tripDocs = tripSnapshot.data?.docs ?? [];
                final bool isWorkStarted = tripDocs.isNotEmpty;
                final tripDoc = isWorkStarted ? tripDocs.first : null;
                final tripData = tripDoc?.data() as Map<String, dynamic>?;

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── Logo centrado ──────────────────────────────────────────────
                      Center(
                        child: Image.asset(
                          'assets/fleetChatLOGOsmall.png',
                          width: double.infinity,
                          height: 100, // Reduzido ligeiramente
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (!isAuthorized)
                        Expanded(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.amber.shade400, width: 2),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.pending_actions, size: 64, color: Colors.amber.shade800),
                                  const SizedBox(height: 16),
                                  Text(
                                    'A aguardar autorização da Sede',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Podes completar os teus dados clicando no ícone do Perfil no topo direito.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.amber.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => const ProfileScreen(),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.person),
                                        label: const Text('Perfil', style: TextStyle(fontSize: 16)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueGrey.shade700,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      OutlinedButton.icon(
                                        onPressed: _logout,
                                        icon: const Icon(Icons.logout),
                                        label: const Text('Sair', style: TextStyle(fontSize: 16)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red.shade700,
                                          side: BorderSide(color: Colors.red.shade700),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else ...[
                        // ── SMART BANNER (Início/Fim de Dia) ──────────────
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: InkWell(
                            onTap: () {
                              if (isWorkStarted && tripDoc != null) {
                                _showEndDayForm(tripDoc);
                              } else {
                                _showStartDayForm();
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: Colors.blueGrey.shade900,
                              ),
                              child: Row(
                                children: [
                                  if (isWorkStarted)
                                    const _PulseIcon(icon: Icons.fiber_manual_record, color: Colors.white)
                                  else
                                    const Icon(Icons.play_circle_fill, size: 40, color: Colors.white),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isWorkStarted ? 'Terminar dia de trabalho' : 'Iniciar dia de trabalho',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                        if (isWorkStarted)
                                          Text(
                                            '${tripData?['tractorPlate'] ?? '---'} • ${tripData?['trailerPlate'] ?? '---'}',
                                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Grelha de Botões ──────────────
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                // TAREFAS
                                Opacity(
                                  opacity: isWorkStarted ? 1.0 : 0.4,
                                  child: IgnorePointer(
                                    ignoring: !isWorkStarted,
                                    child: _buildDashboardButton(
                                      context: context,
                                      label: 'Tarefas',
                                      icon: Icons.checklist,
                                      color: Colors.teal.shade700,
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TasksScreen())),
                                      badgeCountStream: FirebaseFirestore.instance
                                          .collection('tasks')
                                          .where('driverId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                                          .snapshots()
                                          .map((s) => s.docs.where((d) => (d.data() as Map<String, dynamic>)['status'] != 'completed').length),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // MENSAGENS
                                Opacity(
                                  opacity: isWorkStarted ? 1.0 : 0.4,
                                  child: IgnorePointer(
                                    ignoring: !isWorkStarted,
                                    child: _buildDashboardButton(
                                      context: context,
                                      label: 'Mensagens',
                                      icon: Icons.chat_bubble_outline,
                                      color: Colors.blue.shade800,
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())),
                                      badgeCountStream: FirebaseFirestore.instance
                                          .collection('messages')
                                          .where('driverId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                                          .where('sender', isEqualTo: 'hq')
                                          .where('status', whereIn: ['sent', 'delivered'])
                                          .snapshots()
                                          .map((s) => s.docs.length),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // ABASTECIMENTOS
                                Opacity(
                                  opacity: isWorkStarted ? 1.0 : 0.4,
                                  child: IgnorePointer(
                                    ignoring: !isWorkStarted,
                                    child: _buildDashboardButton(
                                      context: context,
                                      label: 'Abastecimentos',
                                      icon: Icons.local_gas_station,
                                      color: Colors.orange.shade700,
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RefuelScreen())),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // INCIDENTES (Sempre ativo)
                                _buildDashboardButton(
                                  context: context,
                                  label: 'Incidentes',
                                  icon: Icons.warning_amber_rounded,
                                  color: Colors.deepOrange.shade600,
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IncidentScreen())),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildDashboardButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Stream<int>? badgeCountStream,
  }) {
    return SizedBox(
      height: 80,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 28),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            if (badgeCountStream != null)
              StreamBuilder<int>(
                stream: badgeCountStream,
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(left: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      count > 99 ? '99+' : count.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _PulseIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  const _PulseIcon({required this.icon, required this.color});

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Icon(widget.icon, size: 40, color: widget.color),
    );
  }
}