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
    final mqttDeviceId = (rawMqttData['device_id'] ?? rawMqttData['id_perangkat'])?.toString().trim();
    final isMatchingMqtt = mqttDeviceId == null ||
        mqttDeviceId.toLowerCase() == perangkat.idPerangkat.trim().toLowerCase() ||
        (mqttDeviceId == 'ESP32-S3-Longsor' && perangkat.idPerangkat.toLowerCase().contains('esp32'));
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
            _SensorOverviewCard(
              idPerangkat: perangkat.idPerangkat,
              enabled: enableCharts,
              data: data,
              overallStatus: riskStatus,
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
      return 'Status ditampilkan dari data terakhir yang tersimpan lokal.';
    }
    if (!mqttHandler.hasInternet) {
      return 'Koneksi internet sedang tidak tersedia. Menampilkan data terakhir.';
    }
    return 'Status kerentanan diperbarui secara realtime dari sensor yang terhubung.';
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
              fontWeight: label == 'Nama Perangkat' ? FontWeight.w700 : FontWeight.w600,
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

class _SensorOverviewCard extends StatefulWidget {
  const _SensorOverviewCard({
    required this.idPerangkat,
    required this.enabled,
    required this.data,
    required this.overallStatus,
  });

  final String idPerangkat;
  final bool enabled;
  final Map<String, dynamic> data;
  final String overallStatus;

  @override
  State<_SensorOverviewCard> createState() => _SensorOverviewCardState();
}

class _SensorOverviewCardState extends State<_SensorOverviewCard> {
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
    const rainPalette = _MetricPalette(
      name: 'Hujan',
      accent: Color(0xFF1565C0),
      background: Color(0xFFEAF4FF),
      border: Color(0xFFC8E1FF),
      icon: Icons.water_drop_rounded,
    );
    const tiltPalette = _MetricPalette(
      name: 'Kemiringan',
      accent: Color(0xFF2E7D32),
      background: Color(0xFFEEF8F0),
      border: Color(0xFFD1EAD5),
      icon: Icons.landscape_rounded,
    );
    const humidityPalette = _MetricPalette(
      name: 'Kelembapan',
      accent: Color(0xFF00838F),
      background: Color(0xFFEAFBFC),
      border: Color(0xFFC8EEF2),
      icon: Icons.opacity_rounded,
    );

    final chartsReady = widget.enabled && !_isInitialLoading && _rows.isNotEmpty;
    final hasInternet = Provider.of<MqttHandler?>(context)?.hasInternet ?? false;
    final chartMessage = _errorText ??
        (hasInternet
            ? 'Belum ada data grafik dalam 24 jam terakhir.'
            : 'Mode offline: grafik menampilkan cache terakhir (jika tersedia).');

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
            'Monitoring Sensor',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2F241D),
            ),
          ),
          const SizedBox(height: 16),
          _MetricSectionCard(
            title: 'Hujan',
            valueLabel: 'Nilai Hujan',
            valueText: '${widget.data['Sensor Hujan'] ?? 0}',
            statusText: widget.data['Status Hujan']?.toString() ?? 'Menunggu data',
            vulnerabilityText: widget.overallStatus,
            palette: rainPalette,
            chartTitle: 'Grafik Hujan 24 Jam',
            chartContent: !widget.enabled
                ? const _ChartInfoBox(
                    message: 'Grafik dinonaktifkan untuk mode pengujian.',
                  )
                : _isInitialLoading
                    ? const _ChartInfoBox(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : chartsReady
                        ? SizedBox(
                            height: 210,
                            child: _LineSensorChart(
                              color: rainPalette.accent,
                              points: _rows
                                  .map(
                                    (row) => _ChartPoint(
                                      x: row.waktuUpdate,
                                      y: row.nilaiHujan,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          )
                        : _ChartInfoBox(message: chartMessage),
          ),
          const SizedBox(height: 12),
          _MetricSectionCard(
            title: 'Kemiringan',
            valueLabel: 'Nilai Kemiringan',
            valueText: '${widget.data['Sensor Kemiringan'] ?? 0}',
            statusText: widget.data['Status Kemiringan']?.toString() ?? 'Menunggu data',
            vulnerabilityText: widget.overallStatus,
            palette: tiltPalette,
            chartTitle: 'Grafik Kemiringan 24 Jam',
            chartContent: !widget.enabled
                ? const _ChartInfoBox(
                    message: 'Grafik dinonaktifkan untuk mode pengujian.',
                  )
                : _isInitialLoading
                    ? const _ChartInfoBox(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : chartsReady
                        ? SizedBox(
                            height: 210,
                            child: _LineSensorChart(
                              color: tiltPalette.accent,
                              points: _rows
                                  .map(
                                    (row) => _ChartPoint(
                                      x: row.waktuUpdate,
                                      y: row.nilaiKemiringan,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          )
                        : _ChartInfoBox(message: chartMessage),
          ),
          const SizedBox(height: 12),
          _MetricSectionCard(
            title: 'Kelembapan Tanah',
            valueLabel: 'Nilai Kelembapan',
            valueText: '${widget.data['Sensor Kelembapan'] ?? 0}',
            statusText: widget.data['Status Kelembapan']?.toString() ?? 'Menunggu data',
            vulnerabilityText: widget.overallStatus,
            palette: humidityPalette,
            chartTitle: 'Grafik Kelembapan 24 Jam',
            chartContent: !widget.enabled
                ? const _ChartInfoBox(
                    message: 'Grafik dinonaktifkan untuk mode pengujian.',
                  )
                : _isInitialLoading
                    ? const _ChartInfoBox(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : chartsReady
                        ? SizedBox(
                            height: 210,
                            child: _LineSensorChart(
                              color: humidityPalette.accent,
                              points: _rows
                                  .map(
                                    (row) => _ChartPoint(
                                      x: row.waktuUpdate,
                                      y: row.nilaiKelembapan,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          )
                        : _ChartInfoBox(message: chartMessage),
          ),
        ],
      ),
    );
  }
}

class _MetricSectionCard extends StatelessWidget {
  const _MetricSectionCard({
    required this.title,
    required this.valueLabel,
    required this.valueText,
    required this.statusText,
    required this.vulnerabilityText,
    required this.palette,
    required this.chartTitle,
    required this.chartContent,
  });

  final String title;
  final String valueLabel;
  final String valueText;
  final String statusText;
  final String vulnerabilityText;
  final _MetricPalette palette;
  final String chartTitle;
  final Widget chartContent;

  @override
  Widget build(BuildContext context) {
    final vulnerabilityPalette = getStatusPalette(vulnerabilityText);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: palette.accent.withValues(alpha: 0.14),
                child: Icon(palette.icon, color: palette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2F241D),
                  ),
                ),
              ),
              StatusChip(label: statusText, color: palette.accent),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valueLabel,
                      style: const TextStyle(
                        color: Color(0xFF6E655F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      valueText,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2F241D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: vulnerabilityPalette.background.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: vulnerabilityPalette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kerentanan',
                        style: TextStyle(
                          color: Color(0xFF6E655F),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        vulnerabilityText,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: vulnerabilityPalette.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
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
                        chartTitle,
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
                chartContent,
              ],
            ),
          ),
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
    final spots = points
        .map(
          (point) => FlSpot(point.x.millisecondsSinceEpoch.toDouble(), point.y),
        )
        .toList(growable: false);

    final minX = spots.first.x;
    final maxX = spots.last.x;
    final minY = points.map((point) => point.y).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((point) => point.y).reduce((a, b) => a > b ? a : b);
    final ySpread = (maxY - minY).abs();
    final yPadding = ySpread < 1 ? 1.0 : ySpread * 0.2;
    final xPadding = minX == maxX ? 60000.0 : 0.0;
    final xInterval = (maxX - minX) <= 0 ? 3600000.0 : (maxX - minX) / 4;
    final formatter = DateFormat('HH:mm');

    return LineChart(
      LineChartData(
        minX: minX - xPadding,
        maxX: maxX + xPadding,
        minY: minY - yPadding,
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
