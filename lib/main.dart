import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/sync_service.dart';

// Variáveis globais para controlar se os ecrãs estão abertos
bool isChatOpen = false;
bool isTasksOpen = false;

// Instância global do plugin de notificações locais
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ─── Handler de background FCM (top-level obrigatório) ─────────────────────
// Este handler corre mesmo com a app completamente fechada (num isolate separado).
// O Android/FCM mostra a notificação automaticamente nesse caso;
// aqui apenas garantimos que a local_notification aparece se a app estiver em background.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final notification = message.notification;
  if (notification == null) return;

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'tasks_channel',
    'Notificações',
    channelDescription: 'Notificações de tarefas e mensagens',
    importance: Importance.max,
    priority: Priority.high,
  );
  const NotificationDetails platformDetails =
      NotificationDetails(android: androidDetails);

  final isTask = message.data['type'] == 'task';
  
  if (!isTask) {
    final messageId = message.data['messageId'];
    if (messageId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('messages')
            .doc(messageId)
            .update({'status': 'delivered'});
      } catch (e) {
        print('Erro a marcar mensagem como entregue (background): $e');
      }
    }
  }

  await flutterLocalNotificationsPlugin.show(
    id: message.hashCode & 0x7FFFFFFF,
    title: notification.title,
    body: notification.body,
    notificationDetails: platformDetails,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Configuração das Notificações Locais (para foreground)
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/launcher_icon');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  // Registar handler de background FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Inicializar o serviço de sincronização offline
  SyncService().initialize();

  final PackageInfo packageInfo = await PackageInfo.fromPlatform();

  runApp(MyApp(packageInfo: packageInfo));
}

class MyApp extends StatelessWidget {
  final PackageInfo packageInfo;
  const MyApp({super.key, required this.packageInfo});

  bool _isVersionOutdated(String installed, String minRequired) {
    try {
      // Normalizar versões (remover +build)
      final String v1 = installed.split('+')[0];
      final String v2 = minRequired.split('+')[0];

      List<int> parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < parts2.length; i++) {
        int val1 = i < parts1.length ? parts1[i] : 0;
        int val2 = parts2[i];
        if (val1 < val2) return true;
        if (val1 > val2) return false;
      }
    } catch (e) {
      debugPrint('Erro ao comparar versões: $e');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FleetChat - Infofirst',
      builder: (context, child) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('config')
              .doc('app_settings')
              .snapshots(),
          builder: (context, snapshot) {
            bool isLocked = false;
            String pin = '1234';

            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;

              // Se o master lock estiver ativo, bloqueia tudo
              if (data['forceLock'] == true) {
                isLocked = true;
              }

              // Se houver uma versão mínima exigida, comparamos
              final String? minVersion = data['minVersion']?.toString();
              if (minVersion != null && minVersion.isNotEmpty) {
                if (_isVersionOutdated(packageInfo.version, minVersion)) {
                  isLocked = true;
                }
              }

              if (data['unlockPin'] != null) {
                pin = data['unlockPin'].toString();
              }
            }

            return KillSwitchOverlay(
              isLocked: isLocked,
              requiredPin: pin,
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          centerTitle: true,
          elevation: 0.5,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          final user = snapshot.data;

          if (user == null) {
            return const LoginScreen();
          }

          return const DashboardScreen();
        },
      ),
    );
  }
}

class KillSwitchOverlay extends StatefulWidget {
  final Widget child;
  final String requiredPin;
  final bool isLocked;

  const KillSwitchOverlay({
    super.key,
    required this.child,
    required this.requiredPin,
    required this.isLocked,
  });

  @override
  State<KillSwitchOverlay> createState() => _KillSwitchOverlayState();
}

class _KillSwitchOverlayState extends State<KillSwitchOverlay> {
  bool _isBypassed = false;
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Se não estiver bloqueado ou se o utilizador já inseriu o PIN com sucesso
    if (!widget.isLocked || _isBypassed) {
      return widget.child;
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          // Mantemos a app por baixo (congelada)
          widget.child,
          // Ecrã de bloqueio com o seu próprio Overlay para o TextField funcionar
          Positioned.fill(
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => Scaffold(
                    backgroundColor: const Color(0xEF000000),
                    body: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_outline,
                                size: 80, color: Colors.white),
                            const SizedBox(height: 24),
                            const Text(
                              'Aplicação Bloqueada',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Esta versão da aplicação encontra-se bloqueada.\nPor favor, atualize a aplicação ou insira o PIN de acesso de emergência.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16, color: Colors.white70),
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: 200,
                              child: TextField(
                                controller: _pinController,
                                focusNode: _focusNode,
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                obscureText: true,
                                maxLength: 4,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    letterSpacing: 16),
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  hintText: '****',
                                  hintStyle:
                                      const TextStyle(color: Colors.white38),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Colors.white54),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Colors.blueAccent),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  counterText: '',
                                ),
                                onChanged: (value) {
                                  if (value == widget.requiredPin) {
                                    setState(() {
                                      _isBypassed = true;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

