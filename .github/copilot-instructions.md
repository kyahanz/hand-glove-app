**Repository:** BISINDO Smart Translator (Flutter)

**Purpose (big picture):**
- Mobile + desktop Flutter app that translates BISINDO (Indonesian Sign Language) gestures using a smart glove: Bluetooth data -> TFLite inference -> speech (TTS).
- Major components: `lib/features/bluetooth` (BLE), `lib/features/inference` (TFLite), `lib/features/translation` (translation + TTS), `lib/features/learning` (UI for learning), `lib/features/home` (entry UI), and `lib/core` (theme & shared utilities).

**Key architecture & data flow (why):**
- `BLEService` (lib/features/bluetooth/ble_service.dart) maintains low-level Bluetooth interactions. It exposes:
  - `dataStream` (Stream<List<double>>) with incoming sensor packets.
  - `connectionState` (Stream<BluetoothConnectionState>) to observe connection.
  - Mock mode (`toggleMockMode`) to simulate sensors for local testing.
- `BLEProvider` (lib/features/bluetooth/ble_provider.dart) wraps `BLEService` as a `ChangeNotifier`. UI widgets consume `BLEProvider` for connection/scanning state. Avoid expensive re-builds on every data packet — providers opt to not notify on every sensor update (see comments in `BLEProvider`).
- `TFLiteService` (lib/features/inference/tflite_service.dart) is the inference wrapper: loads a TFLite model and exposes a `predict(List<double>)` function. The project currently mocks loading and inference (explicit comments). When adding a model, add it to `assets` and update `pubspec.yaml`.
- `TranslationProvider` (lib/features/translation/translation_provider.dart) receives data from `BLEProvider` (wired via `ChangeNotifierProxyProvider` in `lib/main.dart`) and uses `TFLiteService` to predict text; it runs `TTSService` (flutter_tts) when enabled.

**Patterns, conventions & code smells**
- Provider pattern: Use `ChangeNotifier` + `ChangeNotifierProxyProvider` to feed data between services. Prefer listening to streams in `Service` classes and exposing the state via `Provider` wrappers.
- Services vs Providers: Keep Bluetooth and device integration inside `Service` classes and expose them via `Provider` for UI-level state management.
- Mock mode: BLE mock is implemented in `BLEService.toggleMockMode(true)`. Use this pathway for offline UI, testing, or automated UI tests.
- TFLite mocked: `TFLiteService.loadModel` and `predict` use mocked logic. Replace only after adding the model artifact and testing on-device.
- Avoid notifying the whole UI on every incoming packet (high-frequency). `BLEProvider` purposefully throttles UI rebuilds.

**Important files & entry points**
- App entry: `lib/main.dart` — sets `MultiProvider` with `BLEProvider` and `TranslationProvider` wiring.
- BLE: `lib/features/bluetooth/ble_service.dart` and `lib/features/bluetooth/ble_provider.dart`.
- Inference: `lib/features/inference/tflite_service.dart` (mocked) and `lib/features/inference` folder.
- UI: `lib/features/home/home_screen.dart`, `lib/features/translation/translation_screen.dart`, `lib/features/learning/learning_screen.dart`.
- Theme: `lib/core/app_theme.dart`.

**Platform & permission notes**
- Bluetooth on Android (12+): Add `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` in `AndroidManifest.xml` and handle runtime with `permission_handler`. For older versions, `ACCESS_FINE_LOCATION` may be required for scanning.
- iOS: Add `NSBluetoothAlwaysUsageDescription` and `NSLocationWhenInUseUsageDescription` (if needed) in `ios/Runner/Info.plist` for Bluetooth; add `NSMicrophoneUsageDescription` if using speech input.
- TFLite model: When adding `assets/model.tflite` be sure to declare it in `pubspec.yaml` under `flutter.assets`.

**Build / Run / Test workflows**
- Run on a connected device / emulator: `flutter run` or `flutter run -d <deviceId>`.
- Build release APK: `flutter build apk --release`
- Build iOS: `flutter build ios` (macOS), ensure code signing and iOS privacy entries.
- Build Windows: `flutter build windows`.
- Run tests: `flutter test` (the repo has the default widget test; update tests to match current UI components).
- Formatting & lint: `dart format .` and `flutter analyze`.

**Debugging tips / Developer guidance**
- To run offline workflows or UI without a glove device, toggle mock mode at runtime in `Translator` screen (top-right switch) or call `BLEProvider.toggleMockMode(true)` in a provider test.
- When adding a real TFLite model: verify dimensions and preprocessing steps in `TFLiteService`. The model mock uses the first sensor value for a demo; update `predict` and `loadModel` accordingly.
- Avoid calling `notifyListeners()` for every raw packet; instead, buffer or sample the stream in `BLEService` or throttle in `BLEProvider`.
- Bluetooth scanning and connections are platform-specific (Android 12+ behavior vs earlier). Reproduce bugs on a real device when possible.

**How to add a new feature / integration**
1. Create a `Service` for platform or network interactions (e.g., `lib/features/<feature>/<feature>_service.dart`), expose `Stream`s when data is continuous.
2. Create a `Provider` that wraps the service and exposes UI-safe getters and methods (e.g., `lib/features/<feature>/<feature>_provider.dart`).
3. Register provider in `lib/main.dart` with `ChangeNotifierProvider` or `ChangeNotifierProxyProvider` if you need injected values from other providers.
4. Add UI under `lib/features/<feature>/*` and reference the provider.

**Why some decisions were made**
- Mocking: Model and BLE mock mode exist to allow development without hardware/devices or model artifact, lowering friction for prototyping and CI.
- Provider + Services split: Provides a clean separation between platform code and UI, making it easier to test & replace components.

**Common quick fixes / TODOs**
- Add platform permissions: Update AndroidManifest.xml and Info.plist for production-grade Bluetooth usage.
- Replace TFLiteService mock with a real model: add `assets/model.tflite`, register, and implement preprocessing/quantization steps.
- Add more granular unit and widget tests; current test is from the Flutter template and does not match the app UI.

If anything here is unclear or you need additional walkthroughs (e.g., adding a real TFLite model, CI for building releases, or adding Windows packaging), say which part and I'll detail step-by-step instructions.
