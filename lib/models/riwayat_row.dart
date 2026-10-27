class RiwayatRow {
  const RiwayatRow({
    required this.idPerangkat,
    required this.kerawananLongsor,
    required this.statusHujan,
    required this.nilaiHujan,
    required this.statusKelembapan,
    required this.nilaiKelembapan,
    required this.statusKemiringan,
    required this.nilaiKemiringan,
    required this.waktuUpdate,
    this.id,
  });

  final dynamic id;
  final String idPerangkat;
  final String kerawananLongsor;
  final String statusHujan;
  final double nilaiHujan;
  final String statusKelembapan;
  final double nilaiKelembapan;
  final String statusKemiringan;
  final double nilaiKemiringan;
  final DateTime waktuUpdate;

  factory RiwayatRow.fromMap(Map<String, dynamic> map) {
    DateTime? waktu;
    final rawWaktu = map['waktu_update'];
    if (rawWaktu is String) {
      waktu = DateTime.tryParse(rawWaktu);
      if (waktu == null && rawWaktu.contains(' ')) {
        waktu = DateTime.tryParse(rawWaktu.replaceFirst(' ', 'T'));
      }
    } else if (rawWaktu is DateTime) {
      waktu = rawWaktu;
    }
    waktu ??= DateTime.now();

    double parseDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return RiwayatRow(
      id: map['id'],
      idPerangkat: (map['id_perangkat'] ?? map['device_id'] ?? 'Perangkat').toString(),
      kerawananLongsor: (map['kerawanan_longsor'] ?? map['Status Kerawanan'] ?? 'Aman').toString(),
      statusHujan: (map['status_hujan'] ?? map['Status Hujan'] ?? '-').toString(),
      nilaiHujan: parseDouble(map['nilai_hujan'] ?? map['Sensor Hujan']),
      statusKelembapan: (map['status_kelembapan'] ?? map['Status Kelembapan'] ?? '-').toString(),
      nilaiKelembapan: parseDouble(map['nilai_kelembapan'] ?? map['Sensor Kelembapan']),
      statusKemiringan: (map['status_kemiringan'] ?? map['Status Kemiringan'] ?? '-').toString(),
      nilaiKemiringan: parseDouble(map['nilai_kemiringan'] ?? map['Sensor Kemiringan']),
      waktuUpdate: waktu.toLocal(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'id_perangkat': idPerangkat,
      'kerawanan_longsor': kerawananLongsor,
      'status_hujan': statusHujan,
      'nilai_hujan': nilaiHujan,
      'status_kelembapan': statusKelembapan,
      'nilai_kelembapan': nilaiKelembapan,
      'status_kemiringan': statusKemiringan,
      'nilai_kemiringan': nilaiKemiringan,
      'waktu_update': waktuUpdate.toUtc().toIso8601String(),
    };
  }
}
