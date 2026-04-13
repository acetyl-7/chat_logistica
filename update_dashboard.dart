import 'dart:io';

void main() {
  final file = File('lib/screens/dashboard_screen.dart');
  String content = file.readAsStringSync();

  // 1. Tractor controller
  final tractorSearch = '''
                  TextFormField(
                    controller: tractorController,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula do Veículo (Obrigatório)',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) => v == null || v.isEmpty ? 'Campo obrigatório' : null,
                  ),''';
  final tractorReplace = '''
                  TextFormField(
                    controller: tractorController,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula do Veículo (Obrigatório)',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      MaskTextInputFormatter(
                        mask: '##-##-##',
                        filter: {"#": RegExp(r'[a-zA-Z0-9]')},
                        type: MaskAutoCompletionType.lazy,
                      ),
                    ],
                    validator: (v) => v == null || v.isEmpty ? 'Campo obrigatório' : null,
                  ),''';

  // 2. Trailer controller
  final trailerSearch = '''
                  TextFormField(
                    controller: trailerController,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula do Reboque (Opcional)',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),''';
  final trailerReplace = '''
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
                  ),''';

  // 3. Start KMs
  final startKmsSearch = '''
                  TextFormField(
                    controller: startKmsController,
                    decoration: const InputDecoration(
                      labelText: 'Quilómetros Iniciais (Obrigatório)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Campo obrigatório';
                      if (double.tryParse(v) == null) return 'Valor inválido';
                      return null;
                    },
                  ),''';
  final startKmsReplace = '''
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
                  ),''';

  // 4. Update trip form submit
  final submitStartSearch = '''
                              'tractorPlate': tractorController.text.trim().toUpperCase(),
                              'trailerPlate': trailerController.text.trim().toUpperCase(),
                              'startKms': double.parse(startKmsController.text),''';
  final submitStartReplace = '''
                              'tractorPlate': tractorController.text.trim().toUpperCase(),
                              'trailerPlate': trailerController.text.trim().toUpperCase(),
                              'startKms': double.parse(startKmsController.text.replaceAll(',', '')),''';

  final btnSearch1 = '''
                        : const Text('INICIAR DIA', style: TextStyle(fontSize: 18)),''';
  final btnReplace1 = '''
                        : const Text('Iniciar dia de trabalho', style: TextStyle(fontSize: 18)),''';

  // 5. _showEndDayForm fields
  final endFormSearch = '''
              Form(
                key: formKey,
                child: TextFormField(
                  controller: endKmsController,
                  decoration: const InputDecoration(
                    labelText: 'Quilómetros Finais (Obrigatório)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Campo obrigatório';
                    final end = double.tryParse(v);
                    if (end == null) return 'Valor inválido';
                    if (end < startKms) return 'KMs finais inferiores aos iniciais (\$startKms)';
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
                        final endKms = double.parse(endKmsController.text);

                        await tripDoc.reference.update({
                          'endKms': endKms,
                          'endLocation': pos != null ? GeoPoint(pos.latitude, pos.longitude) : null,
                          'endTime': FieldValue.serverTimestamp(),
                          'status': 'completed',
                        });

                        if (context.mounted) {
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Dia Concluído!'),
                              content: Text('Total de KMs percorridos: \${(endKms - startKms).toStringAsFixed(1)} km'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
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
                    : const Text('TERMINAR DIA', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {''';

  final endFormReplace = '''
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
                    if (end < startKms) return 'KMs finais inferiores aos iniciais (\$startKms)';
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
                            debugPrint('Erro ao obter tarefas concluídas: \$e');
                          }
                        }

                        if (context.mounted) {
                          Navigator.pop(context); // close bottom sheet
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
    final durationStr = '\${h}h \${m}m';

    final startTimeStr = startTime != null
        ? '\${startTime.hour.toString().padLeft(2, '0')}:\${startTime.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final endTimeStr = '\${now.hour.toString().padLeft(2, '0')}:\${now.minute.toString().padLeft(2, '0')}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.all(20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Column(
          children: [
            Icon(Icons.check_circle, size: 60, color: Colors.green.shade600),
            const SizedBox(height: 16),
            const Text(
              'Dia Concluído!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('🕒 Início/Fim:'),
                        Text('\$startTimeStr | \$endTimeStr', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('⏳ Tempo Total:'),
                        Text(durationStr, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('🛣️ Distância:'),
                        Text('\${(endKms - startKms).toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('✅ Tarefas Concluídas:'),
                        Text('\${tasks.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              if (tasks.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tarefas de hoje:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final title = tasks[index]['title'] ?? 'Tarefa sem título';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(title)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueGrey.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('FECHAR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {''';


  final bannerSearch = '''
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  colors: isWorkStarted
                                      ? [Colors.orange.shade800, Colors.red.shade700]
                                      : [Colors.green.shade600, Colors.teal.shade700],
                                ),
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
                                          isWorkStarted ? 'TRABALHO EM CURSO' : 'INÍCIO DE DIA',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),''';

  final bannerReplace = '''
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
                                        ),''';

  String clean(String s) => s.replaceAll('\\r\\n', '\\n');

  content = clean(content);

  bool allFound = true;
  if (!content.contains(clean(tractorSearch))) { print("Tractor search not found"); allFound = false; }
  else content = content.replaceFirst(clean(tractorSearch), clean(tractorReplace));

  if (!content.contains(clean(trailerSearch))) { print("Trailer search not found"); allFound = false; }
  else content = content.replaceFirst(clean(trailerSearch), clean(trailerReplace));

  if (!content.contains(clean(startKmsSearch))) { print("StartKms search not found"); allFound = false; }
  else content = content.replaceFirst(clean(startKmsSearch), clean(startKmsReplace));

  if (!content.contains(clean(submitStartSearch))) { print("Submit start search not found"); allFound = false; }
  else content = content.replaceFirst(clean(submitStartSearch), clean(submitStartReplace));

  if (!content.contains(clean(btnSearch1))) { print("btnSearch1 not found"); allFound = false; }
  else content = content.replaceFirst(clean(btnSearch1), clean(btnReplace1));

  if (!content.contains(clean(endFormSearch))) { print("endForm search not found"); allFound = false; }
  else content = content.replaceFirst(clean(endFormSearch), clean(endFormReplace));

  if (!content.contains(clean(bannerSearch))) { print("banner search not found"); allFound = false; }
  else content = content.replaceFirst(clean(bannerSearch), clean(bannerReplace));

  if (allFound) {
    file.writeAsStringSync(content);
    print("Dashboard updated successfully!");
  }
}
