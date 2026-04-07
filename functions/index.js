const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

// ─── Helper: obtém o token FCM de um motorista ─────────────────────────────
async function getDriverToken(driverId) {
  if (!driverId) return null;
  try {
    const userDoc = await getFirestore().collection("users").doc(driverId).get();
    if (!userDoc.exists) return null;
    return userDoc.data().fcmToken || null;
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

    // Só notificar se a tarefa estiver pendente
    if (data.status !== "pending") return;

    const driverId = data.driverId;
    const taskTitle = data.title || "Nova Tarefa";

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
