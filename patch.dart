import 'dart:io';

void main() {
  final file = File('lib/screens/dashboard_screen.dart');
  final lines = file.readAsLinesSync();

  // Helper to find index by substring
  int findIdx(String text, [int start = 0]) => lines.indexWhere((l) => l.contains(text), start);

  // --- REPLACE BOTTOM TO TOP ---

  // 1. Text buttons in banner
  int b1 = findIdx("isWorkStarted ? 'TRABALHO EM CURSO' : 'INÍCIO DE DIA'");
  if (b1 != -1) {
    lines[b1] = "                                          isWorkStarted ? 'Terminar dia de trabalho' : 'Iniciar dia de trabalho',";
  }

  // 2. Gradient in banner
  int b2 = findIdx("gradient: LinearGradient(");
  if (b2 != -1) {
    lines.replaceRange(b2, b2 + 5, [
      "                                color: Colors.blueGrey.shade900,",
    ]);
  }

  // 3. _showEndOfDayReportDialog integration and end form
  int evEnd = findIdx("ElevatedButton(", findIdx("TextFormField(", findIdx("void _showEndDayForm(")));
  if (evEnd != -1) {
     int pAfter = findIdx("style: ElevatedButton.styleFrom(", evEnd);
     lines.replaceRange(evEnd, pAfter, [
        "              ElevatedButton(",
        "                onPressed: isSubmitting",
        "                    ? null",
        "                    : () async {",
        "                        if (!formKey.currentState!.validate()) return;",
        "                        setModalState(() => isSubmitting = true);",
        "",
        "                        final pos = await _getPosition();",
        "                        final endKms = double.parse(endKmsController.text.replaceAll(',', ''));",
        "",
        "                        final tripData = tripDoc.data() as Map<String, dynamic>;",
        "                        final startTime = tripData['startTime'] as Timestamp?;",
        "                        final uid = FirebaseAuth.instance.currentUser?.uid;",
        "",
        "                        await tripDoc.reference.update({",
        "                          'endKms': endKms,",
        "                          'endLocation': pos != null ? GeoPoint(pos.latitude, pos.longitude) : null,",
        "                          'endTime': FieldValue.serverTimestamp(),",
        "                          'status': 'completed',",
        "                        });",
        "",
        "                        List<Map<String, dynamic>> completedTasks = [];",
        "                        if (uid != null && startTime != null) {",
        "                          try {",
        "                            final tasksSnapshot = await FirebaseFirestore.instance",
        "                                .collection('tasks')",
        "                                .where('driverId', isEqualTo: uid)",
        "                                .where('status', isEqualTo: 'completed')",
        "                                .get();",
        "                            ",
        "                            completedTasks = tasksSnapshot.docs",
        "                                .map((doc) => doc.data())",
        "                                .where((data) {",
        "                                  if (data['completedAt'] == null) return false;",
        "                                  final completedAt = (data['completedAt'] as Timestamp).toDate();",
        "                                  return completedAt.isAfter(startTime.toDate()) || completedAt.isAtSameMomentAs(startTime.toDate());",
        "                                })",
        "                                .toList();",
        "                          } catch (e) {",
        "                            debugPrint('Erro ao obter tarefas concluídas: \$e');",
        "                          }",
        "                        }",
        "",
        "                        if (context.mounted) {",
        "                          Navigator.pop(context);",
        "                          _showEndOfDayReportDialog(",
        "                            startKms: startKms,",
        "                            endKms: endKms,",
        "                            startTime: startTime?.toDate(),",
        "                            tasks: completedTasks,",
        "                          );",
        "                        }",
        "                      },",
     ]);
  }

  int endBtnText = findIdx("const Text('TERMINAR DIA', style: TextStyle(");
  if (endBtnText != -1) {
    lines[endBtnText] = "                    : const Text('Terminar dia de trabalho', style: TextStyle(fontSize: 18)),";
  }

  // Inject _showEndOfDayReportDialog before Future<void> _logout()
  int logoutIdx = findIdx("Future<void> _logout() async {");
  if (logoutIdx != -1) {
     lines.insertAll(logoutIdx, [
        "  void _showEndOfDayReportDialog({",
        "    required double startKms,",
        "    required double endKms,",
        "    required DateTime? startTime,",
        "    required List<Map<String, dynamic>> tasks,",
        "  }) {",
        "    final now = DateTime.now();",
        "    final duration = startTime != null ? now.difference(startTime) : Duration.zero;",
        "    ",
        "    final h = duration.inHours;",
        "    final m = duration.inMinutes.remainder(60);",
        "    final durationStr = '\${h}h \${m}m';",
        "",
        "    final startTimeStr = startTime != null",
        "        ? '\${startTime.hour.toString().padLeft(2, '0')}:\${startTime.minute.toString().padLeft(2, '0')}'",
        "        : '--:--';",
        "    final endTimeStr = '\${now.hour.toString().padLeft(2, '0')}:\${now.minute.toString().padLeft(2, '0')}';",
        "",
        "    showModalBottomSheet(",
        "      context: context,",
        "      isScrollControlled: true,",
        "      backgroundColor: Colors.transparent,",
        "      builder: (context) => Container(",
        "        decoration: const BoxDecoration(",
        "          color: Colors.white,",
        "          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),",
        "        ),",
        "        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 24, left: 24, right: 24),",
        "        child: Column(",
        "          mainAxisSize: MainAxisSize.min,",
        "          children: [",
        "            Icon(Icons.check_circle, size: 60, color: Colors.green.shade600),",
        "            const SizedBox(height: 16),",
        "            const Text(",
        "              'Dia Concluído!',",
        "              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),",
        "            ),",
        "            const SizedBox(height: 24),",
        "            Container(",
        "              padding: const EdgeInsets.all(16),",
        "              decoration: BoxDecoration(",
        "                color: Colors.grey.shade50,",
        "                borderRadius: BorderRadius.circular(16),",
        "                border: Border.all(color: Colors.grey.shade200),",
        "              ),",
        "              child: Column(",
        "                children: [",
        "                  Row(",
        "                    mainAxisAlignment: MainAxisAlignment.spaceBetween,",
        "                    children: [",
        "                      const Text('🕒 Início / Fim'),",
        "                      Text('\$startTimeStr | \$endTimeStr', style: const TextStyle(fontWeight: FontWeight.bold)),",
        "                    ],",
        "                  ),",
        "                  const Divider(height: 20),",
        "                  Row(",
        "                    mainAxisAlignment: MainAxisAlignment.spaceBetween,",
        "                    children: [",
        "                      const Text('⏳ Tempo Total'),",
        "                      Text(durationStr, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),",
        "                    ],",
        "                  ),",
        "                  const Divider(height: 20),",
        "                  Row(",
        "                    mainAxisAlignment: MainAxisAlignment.spaceBetween,",
        "                    children: [",
        "                      const Text('🛣️ Distância Percorrida'),",
        "                      Text('\${(endKms - startKms).toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),",
        "                    ],",
        "                  ),",
        "                  const Divider(height: 20),",
        "                  Row(",
        "                    mainAxisAlignment: MainAxisAlignment.spaceBetween,",
        "                    children: [",
        "                      const Text('✅ Tarefas Concluídas'),",
        "                      Text('\${tasks.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),",
        "                    ],",
        "                  ),",
        "                ],",
        "              ),",
        "            ),",
        "            if (tasks.isNotEmpty) ...[",
        "              const SizedBox(height: 20),",
        "              const Align(",
        "                alignment: Alignment.centerLeft,",
        "                child: Text('Resumo de Tarefas:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),",
        "              ),",
        "              const SizedBox(height: 8),",
        "              ConstrainedBox(",
        "                constraints: const BoxConstraints(maxHeight: 180),",
        "                child: ListView.builder(",
        "                  shrinkWrap: true,",
        "                  itemCount: tasks.length,",
        "                  itemBuilder: (context, index) {",
        "                    return Padding(",
        "                      padding: const EdgeInsets.symmetric(vertical: 6),",
        "                      child: Row(",
        "                        children: [",
        "                          const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),",
        "                          const SizedBox(width: 10),",
        "                          Expanded(child: Text(tasks[index]['title'] ?? 'Tarefa')),",
        "                        ],",
        "                      ),",
        "                    );",
        "                  },",
        "                ),",
        "              ),",
        "            ],",
        "            const SizedBox(height: 24),",
        "            SizedBox(",
        "              width: double.infinity,",
        "              child: ElevatedButton(",
        "                onPressed: () => Navigator.pop(context),",
        "                style: ElevatedButton.styleFrom(",
        "                  padding: const EdgeInsets.symmetric(vertical: 16),",
        "                  backgroundColor: Colors.blueGrey.shade800,",
        "                  foregroundColor: Colors.white,",
        "                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),",
        "                ),",
        "                child: const Text('FECHAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),",
        "              ),",
        "            ),",
        "            const SizedBox(height: 20),",
        "          ],",
        "        ),",
        "      ),",
        "    );",
        "  }",
        "",
     ]);
  }

  // Start Form formatters Kms
  int kStart = findIdx("keyboardType: TextInputType.number,", findIdx("controller: startKmsController"));
  if (kStart != -1) {
     int kpEnd = findIdx("},", kStart) + 1;
     lines.replaceRange(kStart, kpEnd + 1, [
        "                    keyboardType: TextInputType.number,",
        "                    inputFormatters: [ThousandsFormatter()],",
        "                    validator: (v) {",
        "                      if (v == null || v.isEmpty) return 'Campo obrigatório';",
        "                      if (double.tryParse(v.replaceAll(',', '')) == null) return 'Valor inválido';",
        "                      return null;",
        "                    },",
        "                  ),",
     ]);
  }

  // End Form formatters Kms
  int kEnd = findIdx("keyboardType: TextInputType.number,", findIdx("controller: endKmsController"));
  if (kEnd != -1) {
     int kpEnd2 = findIdx("},", kEnd) + 1;
     lines.replaceRange(kEnd, kpEnd2 + 1, [
        "                  keyboardType: TextInputType.number,",
        "                  inputFormatters: [ThousandsFormatter()],",
        "                  validator: (v) {",
        "                    if (v == null || v.isEmpty) return 'Campo obrigatório';",
        "                    final end = double.tryParse(v.replaceAll(',', ''));",
        "                    if (end == null) return 'Valor inválido';",
        "                    if (end < startKms) return 'KMs finais inferiores aos iniciais (\$startKms)';",
        "                    return null;",
        "                  },",
        "                ),",
     ]);
  }

  int subStartKms = findIdx("'startKms': double.parse(startKmsController.text),");
  if (subStartKms != -1) {
     lines[subStartKms] = "                              'startKms': double.parse(startKmsController.text.replaceAll(',', '')),";
  }

  int stBtnText = findIdx("const Text('INICIAR DIA', style: TextStyle(");
  if (stBtnText != -1) {
    lines[stBtnText] = "                        : const Text('Iniciar dia de trabalho', style: TextStyle(fontSize: 18)),";
  }

  // Tractor target
  int trac = findIdx("controller: tractorController,");
  if (trac != -1) {
     int tracEnd = findIdx("),", trac);
     lines.replaceRange(trac - 1, tracEnd + 2, [
        "                  TextFormField(",
        "                    controller: tractorController,",
        "                    decoration: const InputDecoration(",
        "                      labelText: 'Matrícula do Veículo (Obrigatório)',",
        "                      border: OutlineInputBorder(),",
        "                    ),",
        "                    textCapitalization: TextCapitalization.characters,",
        "                    inputFormatters: [",
        "                      UpperCaseTextFormatter(),",
        "                      MaskTextInputFormatter(mask: '##-##-##', filter: {'#': RegExp(r'[a-zA-Z0-9]')}),",
        "                    ],",
        "                    validator: (v) => v == null || v.isEmpty ? 'Campo obrigatório' : null,",
        "                  ),",
     ]);
  }

  int trail = findIdx("controller: trailerController,");
  if (trail != -1) {
     int trailEnd = findIdx("),", trail);
     lines.replaceRange(trail - 1, trailEnd + 2, [
        "                  TextFormField(",
        "                    controller: trailerController,",
        "                    decoration: const InputDecoration(",
        "                      labelText: 'Matrícula do Reboque (Opcional)',",
        "                      border: OutlineInputBorder(),",
        "                    ),",
        "                    textCapitalization: TextCapitalization.characters,",
        "                    inputFormatters: [",
        "                      UpperCaseTextFormatter(),",
        "                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),",
        "                    ],",
        "                  ),",
     ]);
  }

  file.writeAsStringSync(lines.join('\\n'));
}
