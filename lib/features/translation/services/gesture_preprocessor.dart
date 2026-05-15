import 'dart:math';

/// Preprocessor sesuai pipeline Python training:
/// BLE Raw (29) → MA (flex only) → Butterworth LPF → Sliding Window → Z-score → [116 features]
///
/// Kolom input (29):
///   [0-3]  Hand Quaternion (w,x,y,z)
///   [4]    Pinky Flex,  [5-8]  Pinky Q
///   [9]    Ring Flex,   [10-13] Ring Q
///   [14]   Middle Flex, [15-18] Middle Q
///   [19]   Index Flex,  [20-23] Index Q
///   [24]   Thumb Flex,  [25-28] Thumb Q
class GesturePreprocessor {
  static const int numCols = 29;
  static const int maWindow = 5;
  static const int slidingWindowSize = 5;
  // Flex column indices
  static const List<int> flexIndices = [4, 9, 14, 19, 24];

  final List<double> scalerMean;
  final List<double> scalerScale;

  // ─── Moving Average state ─────────────────────────────────────────────
  // Satu antrian per kolom flex (5 kolom)
  final List<List<double>> _maBuffers = List.generate(5, (_) => []);

  // ─── Butterworth IIR state ─────────────────────────────────────────────
  // Order-4 Butterworth LPF, cutoff=0.3
  // Dihitung via butter(4, 0.3, btype='low', output='sos')
  static const List<List<double>> _biquadSOS = [
    [0.01856301, 0.03712602, 0.01856301, 1.0, -0.67274091, 0.1445352],
    [1.0, 2.0, 1.0, 1.0, -0.89765794, 0.5271869],
  ];
  late List<List<List<double>>> _bqState; // [29][2][2]

  // ─── Sliding Window ─────────────────────────────────────────────────────
  final List<List<double>> _slidingBuffer = []; // max size = slidingWindowSize

  bool get isReady => _slidingBuffer.length >= slidingWindowSize;

  GesturePreprocessor({
    required this.scalerMean,
    required this.scalerScale,
  }) {
    _resetBiquadState();
  }

  void _resetBiquadState() {
    _bqState = List.generate(
      numCols,
      (_) => List.generate(2, (_) => [0.0, 0.0]),
    );
  }

  // ─── 1. Moving Average (flex only) ───────────────────────────────────────
  List<double> _applyMA(List<double> frame) {
    final out = List<double>.from(frame);
    for (int f = 0; f < flexIndices.length; f++) {
      final col = flexIndices[f];
      _maBuffers[f].add(frame[col]);
      if (_maBuffers[f].length > maWindow) _maBuffers[f].removeAt(0);
      out[col] = _maBuffers[f].reduce((a, b) => a + b) / _maBuffers[f].length;
    }
    return out;
  }

  // ─── 2. Butterworth LPF (Direct Form II Biquad) ─────────────────────────
  double _biquadFilter(double x, int section, int col) {
    final b0 = _biquadSOS[section][0];
    final b1 = _biquadSOS[section][1];
    final b2 = _biquadSOS[section][2];
    final a1 = _biquadSOS[section][4];
    final a2 = _biquadSOS[section][5];

    final s = _bqState[col][section];
    final w = x - a1 * s[0] - a2 * s[1];
    final y = b0 * w + b1 * s[0] + b2 * s[1];
    s[1] = s[0];
    s[0] = w;
    return y;
  }

  List<double> _applyLPF(List<double> frame) {
    final out = List<double>.filled(numCols, 0.0);
    for (int col = 0; col < numCols; col++) {
      double x = frame[col];
      // Cascade 2 biquad sections
      x = _biquadFilter(x, 0, col);
      x = _biquadFilter(x, 1, col);
      out[col] = x;
    }
    return out;
  }

  // ─── 3. Sliding Window → 116 features ──────────────────────────────────
  // URUTAN WAJIB: [means... 29, stds... 29, mins... 29, maxs... 29]
  List<double>? _computeWindowFeatures() {
    if (_slidingBuffer.length < slidingWindowSize) return null;

    final means = <double>[];
    final stds = <double>[];
    final mins = <double>[];
    final maxs = <double>[];

    for (int col = 0; col < numCols; col++) {
      final values = _slidingBuffer.map((row) => row[col]).toList();
      final mean = values.reduce((a, b) => a + b) / slidingWindowSize;
      final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / slidingWindowSize;
      final std = sqrt(variance);
      final minVal = values.reduce(min);
      final maxVal = values.reduce(max);

      means.add(mean);
      stds.add(std);
      mins.add(minVal);
      maxs.add(maxVal);
    }
    return [...means, ...stds, ...mins, ...maxs];
  }

  // ─── 4. Z-Score ─────────────────────────────────────────────────────────
  List<double> _standardScale(List<double> features) {
    return List.generate(
      features.length,
      (i) {
        final s = scalerScale[i] == 0 ? 1.0 : scalerScale[i];
        return (features[i] - scalerMean[i]) / s;
      },
    );
  }

  // ─── Public API ──────────────────────────────────────────────────────────
  /// Feed satu frame (29 values). Returns 116 scaled features jika window penuh,
  /// null jika masih dalam warmup.
  List<double>? process(List<double> rawFrame) {
    assert(rawFrame.length == numCols, 'Expected $numCols values, got ${rawFrame.length}');

    // Step 1 — MA
    final afterMA = _applyMA(rawFrame);

    // Step 2 — Butterworth LPF
    final afterLPF = _applyLPF(afterMA);

    // Step 3 — Sliding Window
    _slidingBuffer.add(afterLPF);
    if (_slidingBuffer.length > slidingWindowSize) {
      _slidingBuffer.removeAt(0);
    }

    final windowFeatures = _computeWindowFeatures();
    if (windowFeatures == null) return null;

    // Step 4 — Z-Score
    return _standardScale(windowFeatures);
  }

  void reset() {
    _maBuffers.forEach((buf) => buf.clear());
    _resetBiquadState();
    _slidingBuffer.clear();
  }
}
