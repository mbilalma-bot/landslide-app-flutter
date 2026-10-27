import 'package:flutter_test/flutter_test.dart';
import 'package:landslide_app/models/riwayat_row.dart';

List<RiwayatRow> filterStatusTransitions(List<RiwayatRow> chronologicalRows) {
  final Map<String, String> lastStatusPerDevice = <String, String>{};
  final List<RiwayatRow> transitions = <RiwayatRow>[];

  for (final row in chronologicalRows) {
    final deviceKey = row.idPerangkat.trim().isNotEmpty
        ? row.idPerangkat.trim()
        : 'SEMUA_PERANGKAT';
    final currentStatus = row.kerawananLongsor.trim().toLowerCase();

    final lastStatus = lastStatusPerDevice[deviceKey];

    if (lastStatus == null || lastStatus != currentStatus) {
      lastStatusPerDevice[deviceKey] = currentStatus;
      transitions.add(row);
    }
  }

  transitions.sort((a, b) => b.waktuUpdate.compareTo(a.waktuUpdate));
  return transitions;
}

void main() {
  group('Logika Filter Riwayat Status Kerawanan', () {
    test('Mengabaikan status berulang berturut-turut pada perangkat yang sama', () {
      final t0 = DateTime(2026, 9, 4, 10, 0);
      final t1 = DateTime(2026, 9, 4, 10, 5);
      final t2 = DateTime(2026, 9, 4, 10, 10);
      final t3 = DateTime(2026, 9, 4, 10, 15);

      final chronological = [
        RiwayatRow(
          idPerangkat: 'DEV-1',
          kerawananLongsor: 'Aman',
          statusHujan: 'Tidak Hujan',
          nilaiHujan: 0,
          statusKelembapan: 'Kering',
          nilaiKelembapan: 20,
          statusKemiringan: 'Datar',
          nilaiKemiringan: 5,
          waktuUpdate: t0,
        ),
        RiwayatRow(
          idPerangkat: 'DEV-1',
          kerawananLongsor: 'Aman', // berulang berturut-turut -> abaikan
          statusHujan: 'Tidak Hujan',
          nilaiHujan: 0,
          statusKelembapan: 'Kering',
          nilaiKelembapan: 22,
          statusKemiringan: 'Datar',
          nilaiKemiringan: 5,
          waktuUpdate: t1,
        ),
        RiwayatRow(
          idPerangkat: 'DEV-1',
          kerawananLongsor: 'Waspada', // status berubah -> simpan
          statusHujan: 'Hujan Ringan',
          nilaiHujan: 10,
          statusKelembapan: 'Lembap',
          nilaiKelembapan: 60,
          statusKemiringan: 'Miring',
          nilaiKemiringan: 25,
          waktuUpdate: t2,
        ),
        RiwayatRow(
          idPerangkat: 'DEV-1',
          kerawananLongsor: 'Waspada', // berulang berturut-turut -> abaikan
          statusHujan: 'Hujan Sedang',
          nilaiHujan: 15,
          statusKelembapan: 'Lembap',
          nilaiKelembapan: 65,
          statusKemiringan: 'Miring',
          nilaiKemiringan: 25,
          waktuUpdate: t3,
        ),
      ];

      final result = filterStatusTransitions(chronological);

      // Harus hanya ada 2 entri: Waspada (t2) dan Aman (t0)
      expect(result.length, 2);
      expect(result.first.kerawananLongsor, 'Waspada');
      expect(result.first.waktuUpdate, t2);
      expect(result.last.kerawananLongsor, 'Aman');
      expect(result.last.waktuUpdate, t0);
    });

    test('Mencatat perubahan status per perangkat secara independen lalu mengurutkannya', () {
      final t0 = DateTime(2026, 9, 4, 10, 0);
      final t1 = DateTime(2026, 9, 4, 10, 5);
      final t2 = DateTime(2026, 9, 4, 10, 10);
      final t3 = DateTime(2026, 9, 4, 10, 15);

      final chronological = [
        RiwayatRow(
          idPerangkat: 'DEV-1',
          kerawananLongsor: 'Aman',
          statusHujan: 'Tidak Hujan',
          nilaiHujan: 0,
          statusKelembapan: 'Kering',
          nilaiKelembapan: 20,
          statusKemiringan: 'Datar',
          nilaiKemiringan: 5,
          waktuUpdate: t0,
        ),
        RiwayatRow(
          idPerangkat: 'DEV-2',
          kerawananLongsor: 'Waspada',
          statusHujan: 'Hujan Ringan',
          nilaiHujan: 12,
          statusKelembapan: 'Lembap',
          nilaiKelembapan: 55,
          statusKemiringan: 'Miring',
          nilaiKemiringan: 20,
          waktuUpdate: t1,
        ),
        RiwayatRow(
          idPerangkat: 'DEV-2',
          kerawananLongsor: 'Waspada', // sama untuk DEV-2 -> abaikan
          statusHujan: 'Hujan Ringan',
          nilaiHujan: 12,
          statusKelembapan: 'Lembap',
          nilaiKelembapan: 56,
          statusKemiringan: 'Miring',
          nilaiKemiringan: 20,
          waktuUpdate: t2,
        ),
        RiwayatRow(
          idPerangkat: 'DEV-1',
          kerawananLongsor: 'Bahaya', // berubah untuk DEV-1 -> catat!
          statusHujan: 'Hujan Deras',
          nilaiHujan: 80,
          statusKelembapan: 'Basah',
          nilaiKelembapan: 90,
          statusKemiringan: 'Curam',
          nilaiKemiringan: 45,
          waktuUpdate: t3,
        ),
      ];

      final result = filterStatusTransitions(chronological);

      // Terdiri dari: DEV-1 Bahaya (t3), DEV-2 Waspada (t1), DEV-1 Aman (t0)
      expect(result.length, 3);
      expect(result[0].idPerangkat, 'DEV-1');
      expect(result[0].kerawananLongsor, 'Bahaya');
      expect(result[0].waktuUpdate, t3);

      expect(result[1].idPerangkat, 'DEV-2');
      expect(result[1].kerawananLongsor, 'Waspada');
      expect(result[1].waktuUpdate, t1);

      expect(result[2].idPerangkat, 'DEV-1');
      expect(result[2].kerawananLongsor, 'Aman');
      expect(result[2].waktuUpdate, t0);
    });
  });
}
