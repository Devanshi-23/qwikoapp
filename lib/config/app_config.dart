class AppConfig {
  AppConfig._();

  /// Used for Google Maps and Routes. Pass it when running the app:
  /// flutter run --dart-define=MAPS_API_KEY=your_key
  static const String googleMapsApiKey = String.fromEnvironment('MAPS_API_KEY');

  static bool get hasGoogleMapsKey => googleMapsApiKey.isNotEmpty;

  /// `mock` (default, offline) or `google`.
  /// flutter run --dart-define=MAP_PROVIDER=google --dart-define=MAPS_API_KEY=…
  static const String mapProvider = String.fromEnvironment(
    'MAP_PROVIDER',
    defaultValue: 'mock',
  );

  /// The build runs on seeded demo data with no backend.
  static const bool demoMode = bool.fromEnvironment(
    'DEMO_MODE',
    defaultValue: true,
  );

  static bool get wantsGoogleMaps => mapProvider == 'google';

  /// Google renders only when requested and a key is present.
  static bool get useGoogleMaps => wantsGoogleMaps && hasGoogleMapsKey;
}
