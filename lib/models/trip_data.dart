/// Modelo de dados da viagem atual.
/// Usado para persistência via shared_preferences e para o ecrã de resumo.
class TripData {
  const TripData({
    required this.tractorPlate,
    required this.trailerPlate,
    this.lastStatus,
    this.loadingTime,
    this.loadingLat,
    this.loadingLng,
    this.deliveredTime,
    this.deliveredLat,
    this.deliveredLng,
  });

  final String tractorPlate;
  final String trailerPlate;

  /// Último estado registado (ex: 'Em Carregamento', 'Em Trânsito', 'Entregue').
  /// Null se ainda não foi clicado nenhum botão de estado.
  final String? lastStatus;

  /// Timestamp do momento em que clicou 'Em Carregamento'.
  final DateTime? loadingTime;
  final double? loadingLat;
  final double? loadingLng;

  /// Timestamp do momento em que clicou 'Entregue'.
  final DateTime? deliveredTime;
  final double? deliveredLat;
  final double? deliveredLng;

  TripData copyWith({
    String? tractorPlate,
    String? trailerPlate,
    String? lastStatus,
    DateTime? loadingTime,
    double? loadingLat,
    double? loadingLng,
    DateTime? deliveredTime,
    double? deliveredLat,
    double? deliveredLng,
  }) {
    return TripData(
      tractorPlate: tractorPlate ?? this.tractorPlate,
      trailerPlate: trailerPlate ?? this.trailerPlate,
      lastStatus: lastStatus ?? this.lastStatus,
      loadingTime: loadingTime ?? this.loadingTime,
      loadingLat: loadingLat ?? this.loadingLat,
      loadingLng: loadingLng ?? this.loadingLng,
      deliveredTime: deliveredTime ?? this.deliveredTime,
      deliveredLat: deliveredLat ?? this.deliveredLat,
      deliveredLng: deliveredLng ?? this.deliveredLng,
    );
  }
}
