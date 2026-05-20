const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

// ─── Helper: obtém o token FCM de um motorista ─────────────────────────────
async function getDriverToken(driverId) {
  if (!driverId) return null;
  try {
    // 1. Tentar procurar pelo campo driverId (caso seja o ID numérico do SQL)
    const usersSnapshot = await getFirestore()
      .collection("users")
      .where("driverId", "==", driverId.toString())
      .limit(1)
      .get();
      
    if (!usersSnapshot.empty) {
      return usersSnapshot.docs[0].data().fcmToken || null;
    }

    // 2. Fallback: tentar procurar diretamente pelo ID de documento (caso seja o Firebase UID)
    const userDoc = await getFirestore().collection("users").doc(driverId.get ? driverId : driverId.toString()).get();
    if (userDoc.exists) {
      return userDoc.data().fcmToken || null;
    }
    
    return null;
  } catch (err) {
    console.error("Erro ao obter token do motorista:", err);
    return null;
  }
}

// ─── Helper: envia uma notificação FCM ────────────────────────────────────
async function sendFCM(token, title, body, data = {}) {
  if (!token) {
    console.warn("sendFCM: token em falta, notificação não enviada.");
    return;
  }
  try {
    const response = await getMessaging().send({
      token,
      notification: { title, body },
      data,                         // payload extra para o handler Dart
      android: {
        priority: "high",
        notification: {
          channelId: data.type === "task" ? "tasks_channel" : "chat_messages_channel",
          priority: "max",
          defaultSound: true,
        },
      },
    });
    console.log("FCM enviado:", response);
  } catch (err) {
    console.error("Erro ao enviar FCM:", err);
  }
}

// ─── Trigger: nova tarefa criada ──────────────────────────────────────────
exports.onTaskCreated = onDocumentCreated(
  { document: "tasks/{taskId}", region: "europe-west1" },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    // Só notificar se a tarefa estiver pendente ou vinda de SQL (por_enviar / enviada)
    if (data.status !== "pending" && data.status !== "por_enviar" && data.status !== "enviada") return;

    const driverId = data.driverId;
    const taskTitle = data.title || data.taskTypeName || "Nova Tarefa";

    const token = await getDriverToken(driverId);
    await sendFCM(
      token,
      "Nova Tarefa (Logística)",
      taskTitle,
      { type: "task", taskId: event.params.taskId }
    );
  }
);

// ─── Trigger: nova mensagem da Sede ──────────────────────────────────────
exports.onMessageCreated = onDocumentCreated(
  { document: "messages/{messageId}", region: "europe-west1" },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    // Só notificar mensagens enviadas pela Sede
    if (data.sender !== "hq") return;

    const driverId = data.driverId;
    const msgType = data.type || "text";

    let body = data.text || "Nova mensagem";
    if (msgType === "image") body = "Recebeu uma nova imagem da Sede";
    if (msgType === "document") body = "Recebeu um novo documento da Sede";

    const token = await getDriverToken(driverId);
    await sendFCM(
      token,
      "Sede (Logística)",
      body,
      { type: "message", messageId: event.params.messageId }
    );
  }
);

// ─── Callable: devolve a hora actual do servidor ───────────────────────────
exports.getServerTime = onCall(
  { region: "europe-west1" },
  async (_request) => {
    return { timestamp: Date.now() };
  }
);
