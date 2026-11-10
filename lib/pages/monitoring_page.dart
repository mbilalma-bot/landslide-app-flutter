import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:landslide_app/models/perangkat_model.dart';
import 'package:landslide_app/models/sensor_data_row.dart';
import 'package:landslide_app/mqtt/mqtt_client_android.dart';
import 'package:landslide_app/supabase/supabase_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MonitoringPage extends StatelessWidget {
  const MonitoringPage({
    super.key,
    required this.perangkat,
    this.enableCharts = true,
    this.onBack,
  });

  final PerangkatModel perangkat;
  final bool enableCharts;
  final VoidCallback? onBack;

  static const Map<String, dynamic> _fallbackSensorData = <String, dynamic>{
    'waktu': null,
    'Status Hujan': 'Menunggu data',
    'Status Kelembapan': 'Menunggu data',
    'Status Kemiringan': 'Menunggu data',
    'Status Kerawanan': 'Menunggu data',
    'Sensor Hujan': 0,
    'Sensor Kelembapan': 0,
    'Sensor Kemiringan': 0,
  };

  @override
  Widget build(BuildContext context) {
    final mqttHandler = Provider.of<MqttHandler?>(context);
    final rawMqttData = mqttHandler?.sensorData ?? _fallbackSensorData;

    // Gunakan data MQTT jika id_perangkat/device_id cocok, atau gunakan fallback
    final mqttDeviceId =
        (rawMqttData['device_id'] ?? rawMqttData['id_perangkat'])
            ?.toString()
            .trim();
    final isMatchingMqtt =
        mqttDeviceId == null ||
        mqttDeviceId.toLowerCase() ==
            perangkat.idPerangkat.trim().toLowerCase() ||
        (mqttDeviceId == 'ESP32-S3-Longsor' &&
            perangkat.idPerangkat.toLowerCase().contains('esp32'));
    final data = isMatchingMqtt ? rawMqttData : _fallbackSensorData;

    final riskStatus = data['Status Kerawanan']?.toString() ?? 'Menunggu data';
    final statusPalette = getStatusPalette(riskStatus);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DeviceInfoCard(
              deviceId: perangkat.idPerangkat,
              deviceName: perangkat.namaPerangkat,
              updateTime: _formatWaktu(data['waktu']),
            ),
            const SizedBox(height: 16),
            _OverallStatusCard(
              status: riskStatus,
              palette: statusPalette,
              helperText: _riskHelperText(mqttHandler),
            ),
            const SizedBox(height: 16),
            _SensorValuesCard(data: data),
            const SizedBox(height: 16),
            _SensorChartsCard(
              idPerangkat: perangkat.idPerangkat,
              enabled: enableCharts,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatWaktu(dynamic waktu) {
    if (waktu == null) return 'Belum ada pembaruan';

    final raw = waktu.toString().trim();
    if (raw.isEmpty) return 'Belum ada pembaruan';

    DateTime? parsed = DateTime.tryParse(raw);
    if (parsed == null && raw.contains(' ')) {
      parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    }

    if (parsed == null) return raw;
    return DateFormat(
      'dd MMM yyyy, HH:mm:ss',
      'id_ID',
    ).format(parsed.toLocal());
  }

  static String _riskHelperText(MqttHandler? mqttHandler) {
    if (mqttHandler == null) {
      return 'Dashboard berjalan dalam mode pratinjau.';
    }
    if (mqttHandler.isUsingCachedData) {
      return 'Menampilkan status terakhir yang tersimpan.';
    }
    if (!mqttHandler.hasInternet) {
      return 'Koneksi internet offline.';
    }
    return 'Status diperbarui secara realtime.';
  }
}

class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({
    required this.deviceId,
    required this.deviceName,
    required this.updateTime,
  });

  final String deviceId;
  final String deviceName;
  final String updateTime;

  @override
  Widget build(BuildContext context) {
    const infoStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Color(0xFF4F433C),
      height: 1.45,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DeviceInfoLine(
          label: 'ID Perangkat',
          value: deviceId,
          style: infoStyle,
        ),
        const SizedBox(height: 6),
        _DeviceInfoLine(
          label: 'Nama Perangkat',
          value: deviceName,
          style: infoStyle,
        ),
        const SizedBox(height: 6),
        _DeviceInfoLine(
          label: 'Tanggal Pembaruan',
          value: updateTime,
          style: infoStyle,
        ),
      ],
    );
  }
}

class _DeviceInfoLine extends StatelessWidget {
  const _DeviceInfoLine({
    required this.label,
    required this.value,
    required this.style,
  });

  final String label;
  final String value;
  final TextStyle style;

  static const double _labelWidth = 150;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(label, style: style),
        ),
        Text(':', style: style),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: style.copyWith(
              fontWeight: label == 'Nama Perangkat'
                  ? FontWeight.w700
                  : FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _OverallStatusCard extends StatelessWidget {
  const _OverallStatusCard({
    required this.status,
    required this.palette,
    required this.helperText,
  });

  final String status;
  final StatusPalette palette;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(
        backgroundColor: palette.background,
        borderColor: palette.border,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status Kerentanan Saat Ini',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2F241D),
            ),
          ),
          const SizedBox(height: 12),
          StatusChip(
            label: status,
            color: palette.foreground,
            backgroundColor: Colors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 12),
          Text(
            helperText,
            style: const TextStyle(color: Color(0xFF5B4D44), height: 1.45),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card nilai sensor (3 sensor, tanpa grafik)
// ---------------------------------------------------------------------------

class _SensorValuesCard extends StatelessWidget {
  const _SensorValuesCard({required this.data});

  final Map<String, dynamic> data;

  static const _MetricPalette _tiltPalette = _MetricPalette(
    name: 'Kemiringan',
    accent: Color.fromARGB(255, 203, 60, 60),
    background: Color.fromARGB(255, 248, 238, 238),
    border: Color.fromARGB(255, 203, 60, 60),
    icon: Icons.landscape_rounded,
  );
  static const _MetricPalette _humidityPalette = _MetricPalette(
    name: 'Kelembapan Tanah',
    accent: Color.fromARGB(255, 173, 182, 1),
    background: Color.fromARGB(255, 252, 252, 234),
    border: Color.fromARGB(255, 173, 182, 1),
    icon: Icons.opacity_rounded,
  );
  static const _MetricPalette _rainPalette = _MetricPalette(
    name: 'Hujan',
    accent: Color(0xFF1565C0),
    background: Color(0xFFEAF4FF),
    border: Color(0xFF1565C0),
    icon: Icons.water_drop_rounded,
  );

  /// Menampilkan nilai sensor dengan 2 angka di belakang koma.
  /// Digit setelahnya DIPOTONG (bukan dibulatkan), misal 25.6789 -> "25.67".
  static String _formatSensorValue(dynamic value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return '0.00';
    final truncated = (parsed * 100).truncateToDouble() / 100;
    return truncated.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(
        backgroundColor: const Color(0xFFF5F5FB),
        borderColor: const Color(0xFFE1E2F4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nilai Sensor',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2F241D),
            ),
          ),
          const SizedBox(height: 14),
          _SensorValueRow(
            palette: _tiltPalette,
            sensorName: 'Kemiringan',
            statusText:
                data['Status Kemiringan']?.toString() ?? 'Menunggu data',
            valueText: _formatSensorValue(data['Sensor Kemiringan']),
            // unit: '°',
          ),
          const SizedBox(height: 10),
          _SensorValueRow(
            palette: _humidityPalette,
            sensorName: 'Kelembapan Tanah',
            statusText:
                data['Status Kelembapan']?.toString() ?? 'Menunggu data',
            valueText: _formatSensorValue(data['Sensor Kelembapan']),
            // unit: '%',
          ),
          const SizedBox(height: 10),
          _SensorValueRow(
            palette: _rainPalette,
            sensorName: 'Hujan',
            statusText: data['Status Hujan']?.toString() ?? 'Menunggu data',
            valueText: _formatSensorValue(data['Sensor Hujan']),
            // unit: 'mm',
          ),
        ],
      ),
    );
  }
}

/// Satu baris sensor: [Icon | Nama + Status] [Nilai]
/// Layout mengikuti ilustrasi: icon+teks di kiri, nilai besar di tengah-kanan
class _SensorValueRow extends StatelessWidget {
  const _SensorValueRow({
    required this.palette,
    required this.sensorName,
    required this.statusText,
    required this.valueText,
    // this.unit = '',
  });

  final _MetricPalette palette;
  final String sensorName;
  final String statusText;
  final String valueText;
  // final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kolom kiri: icon
            Container(
              width: 64,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.10),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  bottomLeft: Radius.circular(15),
                ),
              ),
              child: Center(
                child: Icon(palette.icon, color: palette.accent, size: 28),
              ),
            ),
            // Kolom tengah: nama sensor + status
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      sensorName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2F241D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    StatusChip(label: statusText, color: palette.accent),
                  ],
                ),
              ),
            ),
            // Kolom kanan: nilai sensor (center vertikal)
            Container(
              constraints: const BoxConstraints(minWidth: 72),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(15),
                  bottomRight: Radius.circular(15),
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      valueText,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: palette.accent,
                        height: 1.1,
                      ),
                    ),
                    // if (unit.isNotEmpty)
                    //   Text(
                    //     unit,
                    //     style: TextStyle(
                    //       fontSize: 11,
                    //       fontWeight: FontWeight.w600,
                    //       color: palette.accent.withValues(alpha: 0.75),
                    //     ),
                    //   ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card grafik sensor (3 grafik dalam satu card)
// ---------------------------------------------------------------------------

class _SensorChartsCard extends StatefulWidget {
  const _SensorChartsCard({required this.idPerangkat, required this.enabled});

  final String idPerangkat;
  final bool enabled;

  @override
  State<_SensorChartsCard> createState() => _SensorChartsCardState();
}

class _SensorChartsCardState extends State<_SensorChartsCard> {
  String get _chartCacheKey => 'monitoring_chart_cache_${widget.idPerangkat}';

  Timer? _pollTimer;
  bool _isFetching = false;
  bool _isInitialLoading = true;
  String? _errorText;
  String? _lastSignature;
  List<SensorDataRow> _rows = const <SensorDataRow>[];
  MqttHandler? _mqttHandler;
  bool _lastInternetStatus = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _isInitialLoading = false;
      return;
    }

    _mqttHandler = Provider.of<MqttHandler?>(context, listen: false);
    _lastInternetStatus = _mqttHandler?.hasInternet ?? false;
    _mqttHandler?.addListener(_handleConnectivityChange);

    unawaited(_restoreCachedChartData());
    if (_lastInternetStatus) {
      unawaited(_loadData(initialLoad: true));
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mqttHandler?.removeListener(_handleConnectivityChange);
    super.dispose();
  }

  void _handleConnectivityChange() {
    if (!mounted) return;
    final now = _mqttHandler?.hasInternet ?? false;
    if (now == _lastInternetStatus) return;
    _lastInternetStatus = now;

    if (!widget.enabled) return;
    if (now) {
      unawaited(SupabaseService.instance.flushPendingSensorData());
      _startPolling();
      unawaited(_loadData(initialLoad: _rows.isEmpty));
    } else {
      _stopPolling();
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_loadData());
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _restoreCachedChartData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_chartCacheKey);
      if (raw == null || raw.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isInitialLoading = false;
        });
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        if (!mounted) return;
        setState(() {
          _isInitialLoading = false;
        });
        return;
      }

      final parsed = <SensorDataRow>[];
      for (final item in decoded) {
        if (item is Map) {
          final row = SensorDataRow.tryFromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          if (row != null) parsed.add(row);
        }
      }

      if (!mounted) return;
      if (parsed.isNotEmpty) {
        setState(() {
          _rows = parsed;
          _lastSignature = _buildSignature(parsed);
          _isInitialLoading = false;
        });
      } else {
        setState(() {
          _isInitialLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _persistCachedChartData(List<SensorDataRow> rows) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = rows
          .map((row) => row.toCacheMap())
          .toList(growable: false);
      await prefs.setString(_chartCacheKey, jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _loadData({bool initialLoad = false}) async {
    final hasInternet = _mqttHandler?.hasInternet ?? false;
    if (!hasInternet) return;
    if (_isFetching) return;
    _isFetching = true;

    try {
      final rows = await SupabaseService.instance.fetchSensorDataLastHours(
        idPerangkat: widget.idPerangkat,
        hours: 24,
      );
      final parsed = <SensorDataRow>[];
      for (final row in rows) {
        final item = SensorDataRow.tryFromMap(row);
        if (item != null) {
          parsed.add(item);
        }
      }

      final signature = _buildSignature(parsed);
      if (!mounted) return;

      if (initialLoad || signature != _lastSignature || _errorText != null) {
        setState(() {
          _rows = parsed;
          _lastSignature = signature;
          _errorText = null;
          _isInitialLoading = false;
        });
        unawaited(_persistCachedChartData(parsed));
      } else if (_isInitialLoading) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Grafik belum dapat dimuat.';
        _isInitialLoading = false;
      });
    } finally {
      _isFetching = false;
    }
  }

  String _buildSignature(List<SensorDataRow> rows) {
    if (rows.isEmpty) return 'empty';

    final last = rows.last;
    return [
      rows.length,
      last.waktuUpdate.millisecondsSinceEpoch,
      last.nilaiHujan.toStringAsFixed(2),
      last.nilaiKemiringan.toStringAsFixed(2),
      last.nilaiKelembapan.toStringAsFixed(2),
    ].join('-');
  }

  @override
  Widget build(BuildContext context) {
    const tiltPalette = _MetricPalette(
      name: 'Kemiringan',
      accent: Color.fromARGB(255, 203, 60, 60),
      background: Color.fromARGB(255, 248, 238, 238),
      border: Color.fromARGB(255, 203, 60, 60),
      icon: Icons.landscape_rounded,
    );
    const humidityPalette = _MetricPalette(
      name: 'Kelembapan Tanah',
      accent: Color.fromARGB(255, 173, 182, 1),
      background: Color.fromARGB(255, 252, 252, 234),
      border: Color.fromARGB(255, 173, 182, 1),
      icon: Icons.opacity_rounded,
    );
    const rainPalette = _MetricPalette(
      name: 'Hujan',
      accent: Color(0xFF1565C0),
      background: Color(0xFFEAF4FF),
      border: Color(0xFF1565C0),
      icon: Icons.water_drop_rounded,
    );

    final chartsReady =
        widget.enabled && !_isInitialLoading && _rows.isNotEmpty;
    final hasInternet =
        Provider.of<MqttHandler?>(context)?.hasInternet ?? false;
    final chartMessage =
        _errorText ??
        (hasInternet
            ? 'Belum ada data grafik dalam 24 jam terakhir.'
            : 'Mode offline: grafik menampilkan data terakhir.');

    Widget buildChartContent({
      required Color color,
      required List<double> Function(SensorDataRow) valueSelector,
    }) {
      if (!widget.enabled) {
        return const _ChartInfoBox(
          message: 'Grafik dinonaktifkan untuk mode pengujian.',
        );
      }
      if (_isInitialLoading) {
        return const _ChartInfoBox(
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (chartsReady) {
        final points = _rows
            .map((row) {
              final vals = valueSelector(row);
              return _ChartPoint(
                x: row.waktuUpdate,
                y: vals[0].clamp(0, double.infinity),
              );
            })
            .toList(growable: false);

        return SizedBox(
          height: 210,
          child: _LineSensorChart(color: color, points: points),
        );
      }
      return _ChartInfoBox(message: chartMessage);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(
        backgroundColor: const Color(0xFFF5F5FB),
        borderColor: const Color(0xFFE1E2F4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Grafik Sensor (24 Jam Terakhir)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2F241D),
            ),
          ),
          const SizedBox(height: 16),
          // Grafik Kemiringan
          _ChartSection(
            palette: tiltPalette,
            title: 'Grafik Kemiringan',
            content: buildChartContent(
              color: tiltPalette.accent,
              valueSelector: (row) => [row.nilaiKemiringan],
            ),
          ),
          const SizedBox(height: 12),
          // Grafik Kelembapan Tanah
          _ChartSection(
            palette: humidityPalette,
            title: 'Grafik Kelembapan Tanah',
            content: buildChartContent(
              color: humidityPalette.accent,
              valueSelector: (row) => [row.nilaiKelembapan],
            ),
          ),
          const SizedBox(height: 12),
          // Grafik Hujan
          _ChartSection(
            palette: rainPalette,
            title: 'Grafik Hujan',
            content: buildChartContent(
              color: rainPalette.accent,
              valueSelector: (row) => [row.nilaiHujan],
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu blok grafik dalam card grafik: judul + konten grafik
class _ChartSection extends StatelessWidget {
  const _ChartSection({
    required this.palette,
    required this.title,
    required this.content,
  });

  final _MetricPalette palette;
  final String title;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2F241D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }
}

class _ChartInfoBox extends StatelessWidget {
  const _ChartInfoBox({this.message, this.child})
    : assert(message != null || child != null);

  final String? message;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3EF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7DDD3)),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: child ?? Text(message!, textAlign: TextAlign.center),
    );
  }
}

class _LineSensorChart extends StatelessWidget {
  const _LineSensorChart({required this.color, required this.points});

  final Color color;
  final List<_ChartPoint> points;

  @override
  Widget build(BuildContext context) {
    // Clamp semua nilai negatif menjadi 0
    final clampedPoints = points
        .map((p) => _ChartPoint(x: p.x, y: p.y < 0 ? 0 : p.y))
        .toList(growable: false);

    final spots = clampedPoints
        .map(
          (point) => FlSpot(point.x.millisecondsSinceEpoch.toDouble(), point.y),
        )
        .toList(growable: false);

    final minX = spots.first.x;
    final maxX = spots.last.x;

    // minY selalu 0 (tidak ada nilai negatif)
    const minY = 0.0;
    final maxY = clampedPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final ySpread = maxY - minY;
    final yPadding = ySpread < 1 ? 1.0 : ySpread * 0.2;

    final xPadding = minX == maxX ? 60000.0 : 0.0;
    final xInterval = (maxX - minX) <= 0 ? 3600000.0 : (maxX - minX) / 4;
    final formatter = DateFormat('HH:mm');

    return LineChart(
      LineChartData(
        minX: minX - xPadding,
        maxX: maxX + xPadding,
        minY: 0,
        maxY: maxY + yPadding,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: yPadding,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: const Color(0xFFE8E1DB), strokeWidth: 1),
          getDrawingVerticalLine: (_) =>
              FlLine(color: const Color(0xFFF1ECE7), strokeWidth: 1),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: const Color(0xFFE0D7D1)),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF2F241D),
            getTooltipItems: (touchedSpots) {
              return touchedSpots
                  .map((spot) {
                    final date = DateTime.fromMillisecondsSinceEpoch(
                      spot.x.toInt(),
                    );
                    return LineTooltipItem(
                      '${DateFormat('dd/MM HH:mm').format(date)}\n${spot.y.toStringAsFixed(2)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  })
                  .toList(growable: false);
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) {
                // Jangan tampilkan label negatif
                if (value < 0) return const SizedBox.shrink();
                return Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6E655F),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: xInterval,
              getTitlesWidget: (value, meta) {
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    formatter.format(date),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6E655F),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPoint {
  const _ChartPoint({required this.x, required this.y});

  final DateTime x;
  final double y;
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.backgroundColor,
  });

  final String label;
  final Color color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MetricPalette {
  const _MetricPalette({
    required this.name,
    required this.accent,
    required this.background,
    required this.border,
    required this.icon,
  });

  final String name;
  final Color accent;
  final Color background;
  final Color border;
  final IconData icon;
}

class StatusPalette {
  const StatusPalette({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}

BoxDecoration cardDecoration({
  Color backgroundColor = Colors.white,
  Color borderColor = const Color(0xFFE8E1DB),
}) {
  return BoxDecoration(
    color: backgroundColor,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: borderColor),
    boxShadow: const [
      BoxShadow(color: Color(0x12000000), blurRadius: 20, offset: Offset(0, 8)),
    ],
  );
}

StatusPalette getStatusPalette(String value) {
  final normalized = value.toLowerCase();

  // Aman / Rendah / Normal / Landai / Kering / Tidak Hujan
  if (normalized.contains('aman') ||
      normalized.contains('normal') ||
      normalized.contains('rendah') ||
      normalized.contains('landai') ||
      normalized.contains('kering') ||
      normalized.contains('tdkhujan')) {
    return const StatusPalette(
      foreground: Color(0xFF2E7D32),
      background: Color(0xFFEAF7EC),
      border: Color(0xFFCBE7CF),
    );
  }

  // Waspada / Sedang / Siaga / Agak Curam / Basah
  if (normalized.contains('waspada') ||
      normalized.contains('sedang') ||
      normalized.contains('siaga') ||
      normalized.contains('agak curam') ||
      (normalized.contains('basah') && !normalized.contains('sngt'))) {
    return const StatusPalette(
      foreground: Color(0xFF9A6700),
      background: Color(0xFFFFF4D6),
      border: Color(0xFFFFE3A6),
    );
  }

  // Bahaya / Tinggi / Darurat / Sangat Curam / Sangat Basah / Deras
  if (normalized.contains('bahaya') ||
      normalized.contains('tinggi') ||
      normalized.contains('darurat') ||
      normalized.contains('sangat curam') ||
      normalized.contains('sngt basah') ||
      normalized.contains('deras')) {
    return const StatusPalette(
      foreground: Color(0xFFC62828),
      background: Color(0xFFFFECEB),
      border: Color(0xFFF5C6C3),
    );
  }

  return const StatusPalette(
    foreground: Color(0xFF8A6242),
    background: Color(0xFFF8F4EF),
    border: Color(0xFFE7DDD3),
  );
}
