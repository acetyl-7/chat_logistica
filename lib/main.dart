import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


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

  // Criar canais de notificação no Android para que o SO os reconheça em background
  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  
  if (androidPlugin != null) {
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'chat_messages_channel',
      'Mensagens de Chat',
      description: 'Notificações de novas mensagens do chat de suporte',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));

    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'tasks_channel',
      'Tarefas',
      description: 'Notificações de novas tarefas atribuídas',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
  }

  // Registar handler de background FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Inicializar o serviço de sincronização offline
  SyncService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FleetChat - Infofirst',
      builder: (context, child) => child ?? const SizedBox.shrink(),
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



