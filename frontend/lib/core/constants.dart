class VastraConstants {
  VastraConstants._();

  // ── Backend ────────────────────────────────────────────────────────────────
  // Change to your machine's IP when running on a physical Android device.
  // Use http://10.0.2.2:8000 for Android emulator.
  // Use http://localhost:8000 for iOS simulator or desktop.
  static const String baseUrl = 'http://192.168.1.10:8000';
  static const String uploadEndpoint     = '/api/upload';
  static const String interactEndpoint   = '/api/interact';
  static const String renderEndpoint     = '/api/render';
  static const String healthEndpoint     = '/health';

  // ── Animation Durations ───────────────────────────────────────────────────
  static const Duration animationFast = Duration(milliseconds: 180);
  static const Duration animationNormal = Duration(milliseconds: 350);
  static const Duration animationSlow = Duration(milliseconds: 600);
  static const Duration animationVerySlow = Duration(milliseconds: 900);

  // ── Layout ─────────────────────────────────────────────────────────────────
  static const double pagePadding = 24.0;
  static const double pageHPadding = 24.0;
  static const double cardBorderRadius = 24.0;
  static const double buttonBorderRadius = 20.0;
  static const double chipBorderRadius = 24.0;

  // ── Image Constraints ─────────────────────────────────────────────────────
  static const int maxImageDimension = 1920;
  static const int imageQuality = 85;

  // ── Hive Box Keys ─────────────────────────────────────────────────────────
  static const String fabricBoxName = 'vastra_fabric_catalog';
  static const String settingsBoxName = 'vastra_settings';

  // ── SharedPreferences Keys ────────────────────────────────────────────────
  static const String onboardingDoneKey = 'onboarding_complete';
}
