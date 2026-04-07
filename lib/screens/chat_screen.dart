import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';


import '../models/chat_message.dart';
import '../services/chat_service.dart';

import '../main.dart'; // Para controlar a variável isChatOpen

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();


  String get _currentSenderId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  @override
  void initState() {
    super.initState();
    isChatOpen = true; // Previne notificações repetidas quando no chat
  }

  @override
  void dispose() {
    isChatOpen = false; // Volta a permitir notificações

    super.dispose();
  }

  Future<void> _markMessagesAsRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('messages')
          .where('driverId', isEqualTo: uid)
          .where('sender', isEqualTo: 'hq')
          .where('status', whereIn: ['sent', 'delivered'])
          .get();

      if (querySnapshot.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in querySnapshot.docs) {
        batch.update(doc.reference, {'status': 'read'});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Erro ao marcar mensagens como lidas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mensagens',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _chatService.messagesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  final messages = snapshot.data ?? [];

                  // Mark HQ messages as read in real-time
                  if (snapshot.hasData) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _markMessagesAsRead();
                    });
                  }

                  if (messages.isEmpty) {
                    return const Center(
                      child: Text(
                        'Ainda não há mensagens.\nSê o primeiro a falar!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true, // Auto-scroll invertido
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == _currentSenderId;

                      // Ler de fileUrl primariamente com fallback para legacy imageUrl format
                      final derivedImageSourceUrl = message.fileUrl ?? message.imageUrl;

                      return Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Colors.blueGrey.shade800
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                if (message.type == 'image' &&
                                    derivedImageSourceUrl != null &&
                                    derivedImageSourceUrl.isNotEmpty) ...[
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => _FullScreenImagePage(
                                            imageUrl: derivedImageSourceUrl,
                                          ),
                                        ),
                                      );
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        derivedImageSourceUrl,
                                        height: 200,
                                        width: 260,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            height: 200,
                                            width: 260,
                                            alignment: Alignment.center,
                                            child: CircularProgressIndicator(
                                              value: loadingProgress.expectedTotalBytes != null
                                                  ? loadingProgress.cumulativeBytesLoaded /
                                                      loadingProgress.expectedTotalBytes!
                                                  : null,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  if (message.text.isNotEmpty && message.text != 'Documento enviado')
                                    const SizedBox(height: 8),
                                ],
                                if (message.type == 'document' &&
                                    message.fileUrl != null &&
                                    message.fileUrl!.isNotEmpty) ...[
                                  GestureDetector(
                                    onTap: () async {
                                      final Uri url = Uri.parse(message.fileUrl!);
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url, mode: LaunchMode.externalApplication);
                                      } else {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                              'Não foi possível abrir o ficheiro.',
                                              style: TextStyle(fontSize: 16),
                                            ),
                                            backgroundColor: Colors.red.shade700,
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      width: 260,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? Colors.blueGrey.shade700
                                            : Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: isMe
                                                ? Colors.blueGrey.shade600
                                                : Colors.grey.shade400),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.picture_as_pdf,
                                            color: isMe
                                                ? Colors.white
                                                : Colors.red.shade700,
                                            size: 32,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              message.fileName ??
                                                  'Documento Anexo',
                                              style: TextStyle(
                                                color: isMe
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Mesmo para documentos, o fileName vai no corpo da mensagem em si
                                  // Se preferirmos não repetir, podemos não mostrar o text se for igual ao fileName
                                  if (message.text.isNotEmpty &&
                                      message.text != message.fileName)
                                    const SizedBox(height: 8),
                                ],
                                if (message.text.isNotEmpty &&
                                    (message.type == 'text' ||
                                        (message.type == 'document' &&
                                            message.text != message.fileName) ||
                                        (message.type == 'image' && message.text != 'Documento enviado')))
                                Text(
                                  message.text,
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: isMe ? Colors.white : Colors.black,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatTime(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isMe
                                          ? Colors.white70
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                  // Vistos só aparecem nas mensagens enviadas pelo motorista
                                  if (isMe) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      message.isPending
                                          ? Icons.schedule
                                          : (message.status == 'read'
                                              ? Icons.done_all
                                              : Icons.done),
                                      size: 16,
                                      color: message.isPending
                                          ? Colors.white70
                                          : (message.status == 'read'
                                              ? Colors.lightBlueAccent
                                              : Colors.white70),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.grey.shade500,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'O envio de mensagens está desativado. Apenas leitura.',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final hours = dateTime.hour.toString().padLeft(2, '0');
    final minutes = dateTime.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}

class _FullScreenImagePage extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImagePage({
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(imageUrl),
        ),
      ),
    );
  }
}
