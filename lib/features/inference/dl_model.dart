// ─────────────────────────────────────────────────────────────────────────────
//  dl_model.dart — Backward Compatibility Shim
//
//  Semua logika inference telah dipindahkan ke:
//    lib/features/translation/services/prediction_service.dart
//
//  File ini hanya menjaga agar tidak ada broken import dari file lain yang
//  mungkin masih memakai DLModel / DLPredictionResult secara langsung.
// ─────────────────────────────────────────────────────────────────────────────

// Re-export dari PredictionService agar import lama tetap bekerja
import 'package:bisindo_app/features/translation/services/prediction_service.dart';

export '../translation/services/prediction_service.dart'
    show PredictionService, PredictionResult;

// Alias nama lama → nama baru (untuk kode yang masih pakai DLPredictionResult)
typedef DLPredictionResult = PredictionResult;
typedef DLModel = PredictionService;
