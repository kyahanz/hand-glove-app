/// DummyData — Data uji menggunakan 33 fitur asli dari dataset CSV.
///
/// Format setiap baris = 33 nilai (TANPA timestamp), urutan kolom:
///   [0-3]   hand_w, hand_x, hand_y, hand_z
///   [4-7]   pinky_mcp_w/x/y/z
///   [8-11]  ring_mcp_w/x/y/z
///   [12-15] middle_mcp_w/x/y/z
///   [16-19] index_mcp_w/x/y/z
///   [20-23] thumb_mcp_w/x/y/z
///   [24-28] pinky_pip, ring_pip, middle_pip, index_pip, thumb_ip
///   [29-32] pinky_dip, ring_dip, middle_dip, index_dip
///
/// ⚠️  Setiap huruf harus memiliki minimal 5 sample IDENTIK agar debounce (5 frame
///     berturut-turut) terpenuhi dan label bisa muncul di UI.
///     Gunakan fungsi [repeated] untuk mengulang 1 sample sebanyak N kali.
class DummyData {
  /// Buat list berisi [sample] yang diulang sebanyak [times] kali.
  static List<List<double>> repeated(List<double> sample, {int times = 7}) =>
      List.generate(times, (_) => List<double>.from(sample));

  /// Map label huruf (UPPERCASE) → list sample 33-fitur.
  /// Setiap list harus memiliki minimal 5 entry agar debounce terpenuhi.
  static final Map<String, List<List<double>>> samples = {
    // ─── A ────────────────────────────────────────────────────────────────────
    // Sumber: dataset CSV row label='a'
    // timestamp: 726076032.0 (dibuang, hanya 33 fitur di bawah)
    'A': repeated([
      0.617001, 0.043031, 0.761382, -0.194311,   // hand Q (w,x,y,z)
      0.697330, 0.043420, -0.472008, 0.537638,   // pinky_mcp Q
      0.761604, -0.424210, -0.487463, -0.048843, // ring_mcp Q
      0.799812, 0.154814, -0.456398, 0.357818,   // middle_mcp Q
      0.661849, 0.552717, -0.491490, 0.122051,   // index_mcp Q
      0.862396, 0.419132, -0.282231, -0.030777,  // thumb_mcp Q
      88.774078, 65.863754, 67.282013, 83.737198, -19.685104, // PIP + thumb_ip
      53.264450, 39.518253, 40.369209, 50.242321,             // DIP
    ]),

    // ─── B ────────────────────────────────────────────────────────────────────
    // Sumber: dataset CSV row label='b'
    // timestamp: 801086016.0 (dibuang)
    'B': repeated([
      0.555018, 0.068676, 0.811062, -0.171516,   // hand Q
      0.936225, 0.121980, -0.184942, 0.272765,   // pinky_mcp Q
      0.844285, -0.519190, 0.015408, 0.131863,   // ring_mcp Q
      0.934283, 0.239834, -0.012506, 0.263513,   // middle_mcp Q
      0.737427, 0.634077, -0.230743, -0.030112,  // index_mcp Q
      0.611168, 0.424733, -0.658471, -0.111771,  // thumb_mcp Q
      -14.785652, 9.350967, 27.919617, -9.178802, 67.635712, // PIP + thumb_ip
      -8.871391, 5.610580, 16.751770, -5.507282,             // DIP
    ]),

    // ─── C ────────────────────────────────────────────────────────────────────
    // Sumber: dataset CSV row label='c'
    // timestamp: 876096064.0 (dibuang)
    'C': repeated([
      0.349436, -0.186102, 0.769195, -0.501597,  // hand Q
      0.640275, 0.444238, -0.262724, 0.568926,   // pinky_mcp Q
      0.869829, -0.469909, -0.101781, 0.110564,  // ring_mcp Q
      0.895474, 0.254609, -0.230669, 0.283004,   // middle_mcp Q
      0.708262, 0.577668, -0.404943, -0.026210,  // index_mcp Q
      0.772174, 0.383968, -0.250051, -0.440216,  // thumb_mcp Q
      59.978134, 104.202820, 48.978500, 51.686401, 40.227448, // PIP + thumb_ip
      35.986881, 62.521694, 29.387102, 31.011843,             // DIP
    ]),

    // ─── D ────────────────────────────────────────────────────────────────────
    // Placeholder — ganti dengan data CSV label='d' sebenarnya
    'D': repeated([
      0.9816, -0.0992, -0.1499, -0.0646,
      0.9585, 0.1883, 0.2006, -0.0748,
      0.9799, 0.0975, 0.1728, 0.0225,
      0.9883, 0.0165, 0.1091, -0.1053,
      0.9728, -0.1166, 0.1975, 0.0334,
      0.9715, -0.0542, -0.0421, 0.2270,
      -5.0, 10.0, 8.0, -12.0, 45.0,
      -3.0, 6.0, 5.0, -7.0,
    ]),

    // ─── E ────────────────────────────────────────────────────────────────────
    // Placeholder — ganti dengan data CSV label='e' sebenarnya
    'E': repeated([
      0.5642, -0.2185, -0.7813, -0.1533,
      0.8640, 0.3766, 0.3017, -0.1438,
      0.8557, 0.4165, 0.3045, -0.0397,
      0.9511, 0.1781, 0.2420, -0.0717,
      0.9214, -0.2402, 0.0981, 0.2894,
      0.8336, 0.0538, 0.5158, 0.1904,
      20.0, 35.0, 25.0, 18.0, 30.0,
      12.0, 21.0, 15.0, 11.0,
    ]),

    // ─── F ────────────────────────────────────────────────────────────────────
    // Placeholder — ganti dengan data CSV label='f' sebenarnya
    'F': repeated([
      0.6090, -0.2632, -0.7430, -0.0879,
      0.9016, 0.3651, 0.2168, -0.0823,
      0.8689, 0.4227, 0.2575, 0.0012,
      0.9520, 0.2276, 0.1898, -0.0764,
      0.8844, -0.2232, 0.2982, 0.2810,
      0.9244, 0.0490, 0.1897, 0.3271,
      15.0, 20.0, 18.0, 22.0, 40.0,
      9.0, 12.0, 11.0, 13.0,
    ]),

    // ─── G ────────────────────────────────────────────────────────────────────
    // Placeholder — ganti dengan data CSV label='g' sebenarnya
    'G': repeated([
      0.8203, -0.0606, -0.5287, 0.2095,
      0.6593, 0.2748, 0.6942, -0.0886,
      0.7445, 0.1166, 0.6563, -0.0372,
      0.7787, 0.0830, 0.5544, -0.2815,
      0.9382, -0.2464, 0.2174, 0.1084,
      0.9353, -0.2063, -0.1345, 0.2542,
      70.0, 80.0, 65.0, 72.0, 25.0,
      42.0, 48.0, 39.0, 43.0,
    ]),
  };
}
