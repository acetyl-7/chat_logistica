import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:permission_handler/permission_handler.dart';

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
  final TripPersistenceService _persistence = TripPersistenceService();

  // Estado local: indica se há viagem ativa (controla o botão condicional)
  bool _hasActiveTrip = false;
  TripData? _activeTrip;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkActiveTrip());
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

  /// Verifica no SharedPreferences se há viagem ativa e actualiza o botão.
  /// NJão navega automaticamente — apenas muda o estado da UI.
  Future<void> _checkActiveTrip() async {
    final active = await _persistence.loadActiveTrip();
    if (!mounted) return;
    setState(() {
      _hasActiveTrip = active != null;
      _activeTrip = active;
    });
  }

  /// Navega para o TripStatesScreen da viagem ativa e re-verifica ao voltar.
  void _returnToActiveTrip() {
    if (_activeTrip == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TripStatesScreen(
              tractorPlate: _activeTrip!.tractorPlate,
              trailerPlate: _activeTrip!.trailerPlate,
            ),
          ),
        )
        .then((_) => _checkActiveTrip());
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _openTripDialog() async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final tractorController = TextEditingController();
    final trailerController = TextEditingController();

    // Captura o navigator ANTES de qualquer await (inclui o showDialog)
    final navigator = Navigator.of(context);

    // Garante que os campos estão sempre vazios ao abrir o formulário
    tractorController.clear();
    trailerController.clear();

    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Iniciar Nova Viagem / Engatar Carreira'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: tractorController,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula do Trator (XX-XX-XX)',
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
                        return 'Preenchimento obrigatório';
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
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: trailerController,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula da Carreira',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      MaskTextInputFormatter(
                        mask: 'A-########',
                        filter: {
                          "A": RegExp(r'[a-zA-Z]'),
                          "#": RegExp(r'[0-9]')
                        },
                        type: MaskAutoCompletionType.lazy,
                      ),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Preenchimento obrigatório';
                      }
                      final regex = RegExp(r'^[A-Z]', caseSensitive: false);
                      if (!regex.hasMatch(value.trimLeft())) {
                        return 'Tem de começar por uma letra';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final tractor =
                      tractorController.text.trim().toUpperCase();
                  var trailer = trailerController.text.trimLeft();
                  if (trailer.isNotEmpty) {
                    trailer =
                        trailer[0].toUpperCase() + trailer.substring(1);
                  }
                  Navigator.of(context).pop({
                    'tractor': tractor,
                    'trailer': trailer,
                  });
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    tractorController.dispose();
    trailerController.dispose();

    if (result != null) {
      final tractor = result['tractor']!;
      final trailer = result['trailer']!;

      // Guarda a nova viagem em shared_preferences ANTES de navegar
      await _persistence.saveNewTrip(
        tractorPlate: tractor,
        trailerPlate: trailer,
      );

      // Aguarda que o dialog seja completamente destruído antes de push
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;
      navigator
          .push(
            MaterialPageRoute(
              builder: (_) => TripStatesScreen(
                tractorPlate: tractor,
                trailerPlate: trailer,
              ),
            ),
          )
          // Re-verifica o estado ao voltar para actualizar o botão condicional
          .then((_) => _checkActiveTrip());
    }
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
          builder: (context, snapshot) {
            final data = snapshot.data?.data() as Map<String, dynamic>?;
            final bool isAuthorized = data?['isAuthorized'] == true;

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
                      height: 120, // Reduzido ligeiramente para dar espaço à foto
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 32),

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
                            ],
                          ),
                        ),
                      ),
                    )
                  else ...[
              // ── Botão condicional: Iniciar Viagem vs Voltar à Viagem ────────
              // Envolto em Visibility(visible: false) a pedido do cliente
              Visibility(
                visible: false,
                child: SizedBox(
                  height: 80,
                  child: _hasActiveTrip
                      ? ElevatedButton.icon(
                          onPressed: _returnToActiveTrip,
                          icon: const Icon(Icons.directions_car, size: 26),
                          label: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Voltar à Viagem'),
                              if (_activeTrip != null)
                                Text(
                                  '${_activeTrip!.tractorPlate} • ${_activeTrip!.trailerPlate}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                            ],
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: _openTripDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey.shade800,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Iniciar Viagem'),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('tasks')
                    .where('driverId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                    .snapshots(),
                builder: (context, taskSnapshot) {
                  final taskDocs = taskSnapshot.data?.docs ?? [];
                  final taskCount = taskDocs.where((doc) {
                    final s = (doc.data() as Map<String, dynamic>)['status'];
                    return s != 'completed';
                  }).length;

                  return SizedBox(
                    height: 80,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TasksScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.checklist, size: 28),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Tarefas'),
                          if (taskCount > 0) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                taskCount > 99 ? '99+' : taskCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('messages')
                    .where('driverId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                    .where('sender', isEqualTo: 'hq')
                    .where('status', whereIn: ['sent', 'delivered'])
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    print('BADGE ERROR: \${snapshot.error}');
                    return const SizedBox(height: 80);
                  }

                  final docs = snapshot.data?.docs;
                  final unreadCount = docs?.length ?? 0;
                  print('BADGE DOCS: $unreadCount (connectionState=${snapshot.connectionState})');

                  return SizedBox(
                    height: 80,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ChatScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 28),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Mensagens'),
                          if (unreadCount > 0) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 80,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RefuelScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.local_gas_station, size: 28),
                  label: const Text('Abastecimentos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 80,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const IncidentScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.warning_amber_rounded, size: 28),
                  label: const Text('Incidentes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange.shade600,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
