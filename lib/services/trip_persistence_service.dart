import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_data.dart';

/// Serviço responsável por guardar e recuperar o estado da viagem ativa
/// usando shared_preferences, permitindo que a viagem sobreviva ao fecho da app.
class TripPersistenceService {
  static const _keyActive = 'trip_active';
  static const _keyTractor = 'trip_tractor_plate';
  static const _keyTrailer = 'trip_trailer_plate';
  static const _keyStatus = 'trip_last_status';
  static const _keyLoadingTime = 'trip_loading_time';
  static const _keyLoadingLat = 'trip_loading_lat';
  static const _keyLoadingLng = 'trip_loading_lng';
  static const _keyDeliveredTime = 'trip_delivered_time';
  static const _keyDeliveredLat = 'trip_delivered_lat';
  static const _keyDeliveredLng = 'trip_delivered_lng';

  /// Inicia uma nova viagem gravando as matrículas e marcando como ativa.
  /// Limpa quaisquer dados de marcos (carregamento/entrega) anteriores.
  Future<void> saveNewTrip({
    required String tractorPlate,
    required String trailerPlate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyActive, true);
    await prefs.setString(_keyTractor, tractorPlate);
    await prefs.setString(_keyTrailer, trailerPlate);
    // Limpar estado e marcos anteriores ao iniciar viagem nova
    await prefs.remove(_keyStatus);
    await prefs.remove(_keyLoadingTime);
    await prefs.remove(_keyLoadingLat);
    await prefs.remove(_keyLoadingLng);
    await prefs.remove(_keyDeliveredTime);
    await prefs.remove(_keyDeliveredLat);
    await prefs.remove(_keyDeliveredLng);
  }

  /// Guarda o estado atual (ex: 'Em Carregamento', 'Entregue') no SharedPreferences
  /// para que o header do TripStatesScreen esteja correto ao retomar.
  Future<void> saveStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStatus, status);
  }

  /// Guarda o timestamp e as coordenadas GPS de um marco da viagem.
  /// [milestone] pode ser 'loading' (Em Carregamento) ou 'delivered' (Entregue).
  Future<void> saveMilestone(
    String milestone,
    DateTime time, {
    double? lat,
    double? lng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (milestone == 'loading') {
      await prefs.setString(_keyLoadingTime, time.toIso8601String());
      if (lat != null) await prefs.setDouble(_keyLoadingLat, lat);
      if (lng != null) await prefs.setDouble(_keyLoadingLng, lng);
    } else if (milestone == 'delivered') {
      await prefs.setString(_keyDeliveredTime, time.toIso8601String());
      if (lat != null) await prefs.setDouble(_keyDeliveredLat, lat);
      if (lng != null) await prefs.setDouble(_keyDeliveredLng, lng);
    }
  }

  /// Retorna os dados da viagem ativa, ou null se não existir viagem ativa.
  Future<TripData?> loadActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final isActive = prefs.getBool(_keyActive) ?? false;
    if (!isActive) return null;

    final tractor = prefs.getString(_keyTractor);
    final trailer = prefs.getString(_keyTrailer);

    // Sem matrículas guardadas → dados corrompidos, limpar tudo
    if (tractor == null || trailer == null) {
      await clearTrip();
      return null;
    }

    final loadingTimeStr = prefs.getString(_keyLoadingTime);
    final deliveredTimeStr = prefs.getString(_keyDeliveredTime);

    return TripData(
      tractorPlate: tractor,
      trailerPlate: trailer,
      lastStatus: prefs.getString(_keyStatus),
      loadingTime: loadingTimeStr != null
          ? DateTime.tryParse(loadingTimeStr)
          : null,
      loadingLat: prefs.getDouble(_keyLoadingLat),
      loadingLng: prefs.getDouble(_keyLoadingLng),
      deliveredTime: deliveredTimeStr != null
          ? DateTime.tryParse(deliveredTimeStr)
          : null,
      deliveredLat: prefs.getDouble(_keyDeliveredLat),
      deliveredLng: prefs.getDouble(_keyDeliveredLng),
    );
  }

  /// Retorna true se houver uma viagem ativa guardada (verificação rápida).
  Future<bool> hasActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyActive) ?? false;
  }

  /// Apaga todos os dados da viagem e marca como inativa.
  Future<void> clearTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyActive);
    await prefs.remove(_keyTractor);
    await prefs.remove(_keyTrailer);
    await prefs.remove(_keyStatus);
    await prefs.remove(_keyLoadingTime);
    await prefs.remove(_keyLoadingLat);
    await prefs.remove(_keyLoadingLng);
    await prefs.remove(_keyDeliveredTime);
    await prefs.remove(_keyDeliveredLat);
    await prefs.remove(_keyDeliveredLng);
  }
}
