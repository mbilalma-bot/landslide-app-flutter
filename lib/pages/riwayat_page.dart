import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:landslide_app/models/riwayat_row.dart';
import 'package:landslide_app/supabase/supabase_service.dart';

class RiwayatPage extends StatefulWidget {
  const RiwayatPage({super.key});

  @override
  State<RiwayatPage> createState() => _RiwayatPageState();
}

class _RiwayatPageState extends State<RiwayatPage> {
  late Stream<List<RiwayatRow>> _riwayatStream;

  @override
  void initState() {
    super.initState();
    _riwayatStream = SupabaseService.instance.riwayatStream(limit: 500);
  }

  /// Logika filter perubahan status berturut-turut:
  /// - Data masukan diasumsikan terurut kronologis (ascending berdasarkan waktu_update).
  /// - Riwayat tidak bergantung satu id_perangkat saja, melainkan membaca semua perangkat.
  /// - Status berulang yang sama berturut-turut dari perangkat yang sama diabaikan.
  /// - Hanya titik perubahan status yang dicatat, dengan mempertahankan waktu pertama kali status tersebut muncul.
  /// - Hasil akhir diurutkan secara Descending (terbaru di atas).
  static List<RiwayatRow> _filterStatusTransitions(
    List<RiwayatRow> chronologicalRows,
  ) {
    final Map<String, String> lastStatusPerDevice = <String, String>{};
    final List<RiwayatRow> transitions = <RiwayatRow>[];

    for (final row in chronologicalRows) {
      final deviceKey = row.idPerangkat.trim().isNotEmpty
          ? row.idPerangkat.trim()
          : 'SEMUA_PERANGKAT';
      final currentStatus = row.kerawananLongsor.trim().toLowerCase();

      final lastStatus = lastStatusPerDevice[deviceKey];

      // Jika belum ada status untuk perangkat ini, atau status berubah dari status sebelumnya
      if (lastStatus == null || lastStatus != currentStatus) {
        lastStatusPerDevice[deviceKey] = currentStatus;
        transitions.add(row);
      }
      // Jika status sama dengan data berturut-turut sebelumnya, dilewati (tidak diduplikasi)
    }

    // Urutkan dari yang paling baru ke paling lama
    transitions.sort((a, b) => b.waktuUpdate.compareTo(a.waktuUpdate));
    return transitions;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RiwayatRow>>(
      stream: _riwayatStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF8A6242)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFC62828),
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Gagal memuat riwayat data: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Color(0xFF2F241D), fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }

        final rawRows = snapshot.data ?? <RiwayatRow>[];
        final filteredRows = _filterStatusTransitions(rawRows);

        if (filteredRows.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Belum ada riwayat perubahan status kerawanan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF2F241D).withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: filteredRows.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = filteredRows[index];
            return _RiwayatCard(item: item);
          },
        );
      },
    );
  }
}

class _RiwayatCard extends StatelessWidget {
  const _RiwayatCard({required this.item});

  final RiwayatRow item;

  @override
  Widget build(BuildContext context) {
    final palette = _getRiwayatPalette(item.kerawananLongsor);
    const detailStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Color(0xFF2D3748),
      height: 1.4,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderColor, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris 1: ID Perangkat
          Text(
            item.idPerangkat,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: palette.titleColor,
            ),
          ),
          const SizedBox(height: 3),
          // Baris 2: Status Kerentanan langsung tanpa label tambahan
          Text(
            item.kerawananLongsor,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.statusColor,
            ),
          ),
          const SizedBox(height: 12),
          // Baris 3: Rincian sensor di kiri & Waktu di kanan
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status Hujan : ${item.statusHujan}',
                      style: detailStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Status Kelembapan : ${item.statusKelembapan} (${item.nilaiKelembapan.toStringAsFixed(1)}%)',
                      style: detailStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Status Kemiringan : ${item.statusKemiringan} (${item.nilaiKemiringan.toStringAsFixed(1)}°)',
                      style: detailStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatWaktu(item.waktuUpdate),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4A5568),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatWaktu(DateTime waktu) {
    try {
      return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(waktu);
    } catch (_) {
      try {
        return DateFormat('dd MMM yyyy, HH:mm').format(waktu);
      } catch (_) {
        return waktu.toIso8601String();
      }
    }
  }
}

class _RiwayatPalette {
  const _RiwayatPalette({
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
    required this.statusColor,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;
  final Color statusColor;
}

_RiwayatPalette _getRiwayatPalette(String status) {
  final s = status.toLowerCase();

  if (s.contains('aman') || s.contains('normal') || s.contains('rendah')) {
    return const _RiwayatPalette(
      backgroundColor: Color(0xFFDCEFE1),
      borderColor: Color(0xFFBCE3C5),
      titleColor: Color(0xFF1B4324),
      statusColor: Color(0xFF2E7D32),
    );
  }

  if (s.contains('waspada') || s.contains('sedang') || s.contains('siaga')) {
    return const _RiwayatPalette(
      backgroundColor: Color(0xFFFFF1C7),
      borderColor: Color(0xFFFFDF8E),
      titleColor: Color(0xFF594000),
      statusColor: Color(0xFF8D5B00),
    );
  }

  if (s.contains('bahaya') || s.contains('tinggi') || s.contains('darurat')) {
    return const _RiwayatPalette(
      backgroundColor: Color(0xFFFFDCDA),
      borderColor: Color(0xFFF5B6B2),
      titleColor: Color(0xFF5D1212),
      statusColor: Color(0xFFC62828),
    );
  }

  // Default abu-abu lembut sesuai wireframe
  return const _RiwayatPalette(
    backgroundColor: Color(0xFFCAD4DC),
    borderColor: Color(0xFFB8C5CE),
    titleColor: Color(0xFF1E272E),
    statusColor: Color(0xFF2F3640),
  );
}
