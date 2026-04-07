import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/trip_data.dart';
import '../screens/dashboard_screen.dart';
import '../services/driver_status_service.dart';
import '../services/location_service.dart';
import '../services/trip_persistence_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TripStatesScreen
// ─────────────────────────────────────────────────────────────────────────────

class TripStatesScreen extends StatefulWidget {
  const TripStatesScreen({
    super.key,
    required this.tractorPlate,
    required this.trailerPlate,
  });

  final String tractorPlate;
  final String trailerPlate;

  @override
  State<TripStatesScreen> createState() => _TripStatesScreenState();
}

class _TripStatesScreenState extends State<TripStatesScreen> {
  final DriverStatusService _statusService = DriverStatusService();
  final LocationService _locationService = LocationService();
  final TripPersistenceService _persistence = TripPersistenceService();

  // Alteração 1: estado local sempre começa vazio — nunca mostra estado anterior
  String _currentStatus = 'A aguardar...';

  // Dados acumulados da viagem para o resumo final
  DateTime? _loadingTime;
  double? _loadingLat;
  double? _loadingLng;
  DateTime? _deliveredTime;
  double? _deliveredLat;
  double? _deliveredLng;

  // ── Temporizador de viagem ─────────────────────────────────────────────────
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  // ── Alteração 3: Mapeamento de status → cor ────────────────────────────────

  /// Devolve a cor correspondente ao estado atual, igual à do botão.
  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Em Carregamento':
        return Colors.amber.shade700;
      case 'Em Trânsito':
        return Colors.blue.shade600;
      case 'Em Distribuição':
        return Colors.orange.shade700;
      case 'Entregue':
        return Colors.green.shade600;
      default:
        return Colors.blueGrey.shade600;
    }
  }

  // ── Actualização de estado ─────────────────────────────────────────────────

  Future<void> _setStatus(String status) async {
    double? latitude;
    double? longitude;

    try {
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        latitude = position.latitude;
        longitude = position.longitude;
      }

      await _statusService.updateStatus(
        status,
        latitude: latitude,
        longitude: longitude,
        tractorPlate: widget.tractorPlate,
        trailerPlate: widget.trailerPlate,
      );

      // Alteração 4: guardar timestamp e GPS de marcos importantes
      final now = DateTime.now();
      if (status == 'Em Carregamento') {
        _loadingTime = now;
        _loadingLat = latitude;
        _loadingLng = longitude;
        await _persistence.saveMilestone(
          'loading',
          now,
          lat: latitude,
          lng: longitude,
        );
        // Inicia o temporizador a partir do momento do carregamento
        _startTimer(from: now);
      } else if (status == 'Entregue') {
        _deliveredTime = now;
        _deliveredLat = latitude;
        _deliveredLng = longitude;
        await _persistence.saveMilestone(
          'delivered',
          now,
          lat: latitude,
          lng: longitude,
        );
      }

      // Persistência do estado atual para sincronização ao retomar (Bug 1)
      await _persistence.saveStatus(status);

      if (!mounted) return;

      // Alteração 1: actualiza o estado local para o header reflectir a cor certa
      setState(() => _currentStatus = status);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Estado atualizado para: $status',
            style: const TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.black87,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao atualizar estado: ${e.toString()}',
            style: const TextStyle(fontSize: 18),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Carregar marcos persistidos (retoma da viagem) ─────────────────────────

@override
  void initState() {
    super.initState();
    _loadPersistedMilestones();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Inicia o temporizador a partir de [from] (ou agora se nulo).
  /// Actualiza _elapsed a cada segundo via setState.
  void _startTimer({DateTime? from}) {
    _timer?.cancel();
    final start = from ?? DateTime.now();
    // Calcula o tempo já decorrido desde [start] (útil ao retomar viagem)
    _elapsed = DateTime.now().difference(start);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(start);
      });
    });
  }

  /// Formata Duration para HH:MM:SS.
  String _formatElapsed(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Quando a viagem é retomada (após fechar/abrir a app), recupera os marcos
  /// já guardados para que o resumo final possa ser apresentado corretamente.
  /// Se já existia um timestamp de carregamento, reinicia o contagem a partir daí.
  Future<void> _loadPersistedMilestones() async {
    final trip = await _persistence.loadActiveTrip();
    if (trip == null || !mounted) return;
    setState(() {
      // Bug 1: restaura o úiltimo estado guardado para o header não mostrar 'A aguardar...'
      if (trip.lastStatus != null) {
        _currentStatus = trip.lastStatus!;
      }
      _loadingTime = trip.loadingTime;
      _loadingLat = trip.loadingLat;
      _loadingLng = trip.loadingLng;
      _deliveredTime = trip.deliveredTime;
      _deliveredLat = trip.deliveredLat;
      _deliveredLng = trip.deliveredLng;
    });
    // Retoma o temporizador se já havia um registo de carregamento
    if (trip.loadingTime != null) {
      _startTimer(from: trip.loadingTime);
    }
  }

  // ── Terminar viagem ─────────────────────────────────────────────────────────

  /// Alteração 4: mostra o resumo antes de terminar.
  /// Só limpa os dados quando o motorista confirma no dialog.
  Future<void> _endTrip() async {
    // Monta os dados do resumo para passar ao dialog
    final tripData = TripData(
      tractorPlate: widget.tractorPlate,
      trailerPlate: widget.trailerPlate,
      loadingTime: _loadingTime,
      loadingLat: _loadingLat,
      loadingLng: _loadingLng,
      deliveredTime: _deliveredTime,
      deliveredLat: _deliveredLat,
      deliveredLng: _deliveredLng,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TripSummaryDialog(tripData: tripData),
    );

    if (confirmed != true || !mounted) return;

    // Respeita a ordem pedida na instrução 1: limpar os dados COM await antes de limpar a navegação
    await _persistence.clearTrip();

    if (!mounted) return;

    // Navega de volta ao Dashboard forçando recarregamento e limpeza da pilha de navegação
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (route) => false,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Viagem em Curso',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        // Substitui o botão de back pelo pop simples
        // O motorista pode voltar ao Dashboard sem terminar a viagem
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

              // ── Cabeçalho de estado com cor dinâmica ──────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blueGrey.shade200,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  'Estado Atual: $_currentStatus',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(
                      _currentStatus == 'A aguardar...' ? null : _currentStatus,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Temporizador de viagem ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _loadingTime != null
                      ? Colors.blueGrey.shade800
                      : Colors.blueGrey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      color: _loadingTime != null
                          ? Colors.white70
                          : Colors.blueGrey.shade400,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _loadingTime != null
                          ? _formatElapsed(_elapsed)
                          : 'Tempo: aguarda carregamento',
                      style: TextStyle(
                        fontSize: _loadingTime != null ? 26 : 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: _loadingTime != null ? 3 : 0,
                        color: _loadingTime != null
                            ? Colors.white
                            : Colors.blueGrey.shade400,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Matrículas ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Trator: ${widget.tractorPlate} | Carreira: ${widget.trailerPlate}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              _buildStatusButton(
                label: 'Em Carregamento',
                color: Colors.amber,
                onTap: () => _setStatus('Em Carregamento'),
              ),
              const SizedBox(height: 16),
              _buildStatusButton(
                label: 'Em Trânsito',
                color: Colors.blue,
                onTap: () => _setStatus('Em Trânsito'),
              ),
              const SizedBox(height: 16),
              _buildStatusButton(
                label: 'Em Distribuição',
                color: Colors.orange,
                onTap: () => _setStatus('Em Distribuição'),
              ),
              const SizedBox(height: 16),
              _buildStatusButton(
                label: 'Entregue',
                color: Colors.green,
                onTap: () => _setStatus('Entregue'),
              ),

              const Spacer(),

              // ── Botão "Terminar Viagem" ────────────────────────────────────
              SizedBox(
                height: 72,
                child: ElevatedButton.icon(
                  onPressed: _endTrip,
                  icon: const Icon(Icons.stop_circle_outlined, size: 28),
                  label: const Text('Terminar Viagem'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 72,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TripSummaryDialog  (Alteração 4)
// ─────────────────────────────────────────────────────────────────────────────
// TripSummaryDialog (agora Stateful para gerir o estado _isSaving)
// ─────────────────────────────────────────────────────────────────────────────

class TripSummaryDialog extends StatefulWidget {
  const TripSummaryDialog({
    super.key,
    required this.tripData,
  });

  final TripData tripData;

  @override
  State<TripSummaryDialog> createState() => _TripSummaryDialogState();
}

class _TripSummaryDialogState extends State<TripSummaryDialog> {
  bool _isSaving = false;

  /// Formata DateTime para apresentação clara (HH:mm:ss dd/MM/yyyy).
  String _formatTime(DateTime? dt) {
    if (dt == null) return '-';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$h:$m:$s  $d/$mo/${dt.year}';
  }

  /// Formata coordenadas para apresentação.
  String _formatCoords(double? lat, double? lng) {
    if (lat == null || lng == null) return 'GPS não disponível';
    return '${lat.toStringAsFixed(5)}°, ${lng.toStringAsFixed(5)}°';
  }

  /// Calcula duração total entre carregamento e entrega (String formato texto).
  String _calcDuration(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '-';
    final diff = end.difference(start);
    if (diff.isNegative) return '-';
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    if (hours == 0) return '$minutes minutos';
    return '$hours hora${hours != 1 ? 's' : ''} e $minutes minuto${minutes != 1 ? 's' : ''}';
  }

  /// Calcula duração em minutos para guardar numericamente no Firestore
  int? _calcDurationMinutes(DateTime? start, DateTime? end) {
    if (start == null || end == null) return null;
    final diff = end.difference(start);
    if (diff.isNegative) return null;
    return diff.inMinutes;
  }

  /// Grava o resumo completo da viagem no Firestore.
  Future<void> _saveTripSummaryToFirestore() async {
    setState(() => _isSaving = true);

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;

      final summaryData = <String, dynamic>{
        'driverId': userId,
        'tractorPlate': widget.tripData.tractorPlate,
        'trailerPlate': widget.tripData.trailerPlate,
        'loadingTime': widget.tripData.loadingTime, // Data/Hora início
        'loadingLat': widget.tripData.loadingLat, // GPS início (Lat)
        'loadingLng': widget.tripData.loadingLng, // GPS início (Lng)
        'deliveredTime': widget.tripData.deliveredTime, // Data/Hora fim
        'deliveredLat': widget.tripData.deliveredLat, // GPS fim (Lat)
        'deliveredLng': widget.tripData.deliveredLng, // GPS fim (Lng)
        'durationText': _calcDuration(
            widget.tripData.loadingTime, widget.tripData.deliveredTime), // Duração Total (Texto)
        'durationMinutes': _calcDurationMinutes(
            widget.tripData.loadingTime, widget.tripData.deliveredTime),
        'savedAt': Timestamp.now(),
      };

      await FirebaseFirestore.instance
          .collection('completed_trips')
          .add(summaryData);

      if (!mounted) return;
      // Regressa true (confirmação válida) para o método que abriu o dialog (_endTrip)
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao guardar resumo: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loadingOk = widget.tripData.loadingTime != null;
    final deliveredOk = widget.tripData.deliveredTime != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: Row(
        children: [
          Icon(Icons.summarize_outlined, color: Colors.blueGrey.shade700),
          const SizedBox(width: 10),
          const Text(
            'Resumo da Viagem',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Matrículas ────────────────────────────────────────────────────
            _SummaryRow(
              icon: Icons.local_shipping_outlined,
              iconColor: Colors.blueGrey,
              label: 'Trator',
              value: widget.tripData.tractorPlate,
            ),
            _SummaryRow(
              icon: Icons.rv_hookup_outlined,
              iconColor: Colors.blueGrey,
              label: 'Carreira',
              value: widget.tripData.trailerPlate,
            ),
            const Divider(height: 24),

            // ── Início: Carregamento ──────────────────────────────────────────
            _SectionHeader(
              label: 'Início (Carregamento)',
              color: Colors.amber.shade700,
              icon: Icons.login_outlined,
            ),
            const SizedBox(height: 6),
            if (!loadingOk)
              const _NotRecorded()
            else ...[
              _SummaryRow(
                icon: Icons.access_time,
                iconColor: Colors.amber.shade700,
                label: 'Hora',
                value: _formatTime(widget.tripData.loadingTime),
              ),
              _SummaryRow(
                icon: Icons.location_on_outlined,
                iconColor: Colors.amber.shade700,
                label: 'GPS',
                value: _formatCoords(
                    widget.tripData.loadingLat, widget.tripData.loadingLng),
              ),
            ],
            const Divider(height: 24),

            // ── Fim: Entrega ──────────────────────────────────────────────────
            _SectionHeader(
              label: 'Fim (Entrega)',
              color: Colors.green.shade600,
              icon: Icons.logout_outlined,
            ),
            const SizedBox(height: 6),
            if (!deliveredOk)
              const _NotRecorded()
            else ...[
              _SummaryRow(
                icon: Icons.access_time,
                iconColor: Colors.green.shade600,
                label: 'Hora',
                value: _formatTime(widget.tripData.deliveredTime),
              ),
              _SummaryRow(
                icon: Icons.location_on_outlined,
                iconColor: Colors.green.shade600,
                label: 'GPS',
                value: _formatCoords(
                    widget.tripData.deliveredLat, widget.tripData.deliveredLng),
              ),
            ],
            const Divider(height: 24),

            // ── Duração total ─────────────────────────────────────────────────
            _SectionHeader(
              label: 'Duração Total',
              color: Colors.blueGrey.shade700,
              icon: Icons.timer_outlined,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _calcDuration(
                    widget.tripData.loadingTime, widget.tripData.deliveredTime),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey.shade800,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveTripSummaryToFirestore,
            icon: _isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_isSaving ? 'A gravar...' : 'Confirmar e Fechar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 0,
              disabledBackgroundColor: Colors.red.shade300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Widgets auxiliares do Dialog ──────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotRecorded extends StatelessWidget {
  const _NotRecorded();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 24, bottom: 4),
      child: Text(
        'Não registado nesta viagem',
        style: TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: Colors.black45,
        ),
      ),
    );
  }
}
