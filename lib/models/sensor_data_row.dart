class SensorDataRow {
  const SensorDataRow({
    required this.waktuUpdate,
    required this.nilaiHujan,
    required this.nilaiKelembapan,
    required this.nilaiKemiringan,
  });

  final DateTime waktuUpdate;
  final double nilaiHujan;
  final double nilaiKelembapan;
  final double nilaiKemiringan;

  static SensorDataRow? tryFromMap(Map<String, dynamic> map) {
    DateTime? waktu;
    final rawWaktu = map['waktu_update'];
    if (rawWaktu is String) {
      waktu = DateTime.tryParse(rawWaktu);
    }
    if (waktu == null) return null;

    double parseDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return SensorDataRow(
      waktuUpdate: waktu.toLocal(),
      nilaiHujan: parseDouble(map['nilai_hujan']),
      nilaiKelembapan: parseDouble(map['nilai_kelembapan']),
      nilaiKemiringan: parseDouble(map['nilai_kemiringan']),
    );
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'waktu_update': waktuUpdate.toUtc().toIso8601String(),
      'nilai_hujan': nilaiHujan,
      'nilai_kelembapan': nilaiKelembapan,
      'nilai_kemiringan': nilaiKemiringan,
    };
  }
}
