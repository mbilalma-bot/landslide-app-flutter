import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
// Hanya gunakan server_client untuk Android/Desktop, hapus browser_client
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:landslide_app/supabase/supabase_service.dart';

class MqttHandler extends ChangeNotifier {
  static const String _sensorDataCacheKey = 'dashboard_sensor_data_cache_v1';

  MqttClient? client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>?
  _updatesSubscription;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _internetProbeTimer;
  Timer? _mqttReconnectTimer;
  bool _isProbingInternet = false;
  int _internetFailStreak = 0;
  int _mqttReconnectAttempt = 0;
  ConnectivityResult _lastConnectivityResult = ConnectivityResult.none;

  bool isConnecting = false;
  String? lastConnectionError;
  bool hasInternet = false;
  bool isUsingCachedData = false;
  bool isRestoringCache = true;

  // Tampungan data sensor terbaru
  Map<String, dynamic> sensorData = {
    "device_id": "ESP32-S3-Longsor",
    "id_perangkat": "ESP32-S3-Longsor",
    "waktu": null,
    "Status Hujan": "Menunggu data...",
    "Status Kelembapan": "Menunggu data...",
    "Status Kemiringan": "Menunggu data...",
    "Status Kerawanan": "Menunggu data...",
    "Output Kerawanan": 0,
    "Sensor Hujan": 0,
    "Sensor Kelembapan": 0,
    "Sensor Kemiringan": 0,
  };

  MqttHandler() {
    unawaited(_restoreCachedSensorData());
    _startConnectivityMonitoring();
  }

  Future<void> connect() async {
    if (isConnecting) return;

    if (!hasInternet) {
      lastConnectionError = 'Tidak ada koneksi internet';
      _scheduleMqttReconnect();
      notifyListeners();
      return;
    }

    if (client?.connectionStatus?.state == MqttConnectionState.connected) {
      lastConnectionError = null;
      notifyListeners();
      return;
    }

    isConnecting = true;
    lastConnectionError = null;
    notifyListeners();

    final String clientId =
        'fl_${DateTime.now().millisecondsSinceEpoch % 1000000000}';
    const String broker = 'broker.emqx.io';
    const int port = 1883; // Port standar TCP untuk hardware/Android

    // Bersihkan subscription lama sebelum mencoba koneksi baru
    await _clearUpdatesSubscription();
    _disconnectInternal();

    // Inisialisasi client khusus Android
    client = MqttServerClient.withPort(broker, clientId, port);
    _configureCommonClientSettings(client!, clientId);

    try {
      if (kDebugMode) {
        debugPrint('Mencoba menghubungkan ke MQTT: $broker:$port');
      }
      await client!.connect().timeout(const Duration(seconds: 6));
    } on TimeoutException {
      lastConnectionError = 'Timeout saat menghubungkan MQTT';
      if (kDebugMode) {
        debugPrint('Kesalahan koneksi MQTT ($broker:$port): timeout');
      }
      _disconnectInternal();
    } catch (e) {
      lastConnectionError = e.toString();
      if (kDebugMode) {
        debugPrint('Kesalahan koneksi MQTT ($broker:$port): $e');
      }
      _disconnectInternal();
    }

    if (client?.connectionStatus?.state == MqttConnectionState.connected) {
      if (kDebugMode) {
        debugPrint('MQTT Client Terhubung! Endpoint: $broker:$port');
      }
      _mqttReconnectAttempt = 0;
      _cancelMqttReconnect();
      if (_updatesSubscription == null) {
        _subscribeAndListen();
      }
      _ensureInternetProbing();
    } else {
      lastConnectionError =
          'Koneksi Gagal - Status: ${client?.connectionStatus}';
      if (kDebugMode) debugPrint(lastConnectionError);
      _disconnectInternal();
      _ensureInternetProbing();
      _mqttReconnectAttempt += 1;
      _scheduleMqttReconnect();
    }

    isConnecting = false;
    notifyListeners();
  }

  void _configureCommonClientSettings(
    MqttClient configuredClient,
    String clientId,
  ) {
    configuredClient.logging(on: kDebugMode);
    configuredClient.keepAlivePeriod = 20;
    configuredClient.connectTimeoutPeriod = 5000;

    // Auto Reconnect
    configuredClient.autoReconnect = false;
    configuredClient.resubscribeOnAutoReconnect = false;

    configuredClient.onConnected = onConnected;
    configuredClient.onDisconnected = onDisconnected;
    configuredClient.onSubscribed = onSubscribed;
    configuredClient.onFailedConnectionAttempt = onFailedConnectionAttempt;
    configuredClient.pongCallback = pong;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();

    configuredClient.connectionMessage = connMessage;
  }

  void _subscribeAndListen() {
    const topic = '+/monitoring-longsor/data_sensor';
    client?.subscribe(topic, MqttQos.atLeastOnce);

    _updatesSubscription = client?.updates?.listen((
      List<MqttReceivedMessage<MqttMessage>> c,
    ) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final String pt = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );

      try {
        final Map<String, dynamic> data = jsonDecode(pt);
        
        // Ambil device_id dari topik jika tidak ada di JSON
        final topicReceived = c[0].topic;
        final topicParts = topicReceived.split('/');
        if (topicParts.isNotEmpty && (data['device_id'] == null && data['id_perangkat'] == null)) {
          data['device_id'] = topicParts[0];
        }

        sensorData = _mergeSensorData(data);
        lastConnectionError = null;
        isUsingCachedData = false;
        unawaited(_persistSensorData());
        notifyListeners();

        // Simpan semua data dari MQTT ke tabel `sensor_data`
        unawaited(SupabaseService.instance.insertSensorDataFromMqtt(sensorData));

        if (kDebugMode) {
          debugPrint('Data diterima dari topik $topicReceived: $pt');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Gagal parsing JSON: $e');
      }
    });
  }

  void _disconnectInternal() {
    try {
      client?.disconnect();
    } catch (_) {}
  }

  Future<void> _clearUpdatesSubscription() async {
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
  }

  void onConnected() {
    if (kDebugMode) debugPrint('Berhasil terhubung ke Broker');
    _mqttReconnectAttempt = 0;
    _cancelMqttReconnect();
    if (_updatesSubscription == null) {
      _subscribeAndListen();
    }
    _ensureInternetProbing();
    notifyListeners();
  }

  void onDisconnected() {
    if (kDebugMode) debugPrint('Terputus dari Broker');
    unawaited(_clearUpdatesSubscription());
    _ensureInternetProbing();
    if (hasInternet) {
      _mqttReconnectAttempt += 1;
      _scheduleMqttReconnect();
    }
    notifyListeners();
  }

  void onSubscribed(String topic) {
    if (kDebugMode) debugPrint('Berhasil Subscribe ke topik: $topic');
  }

  void onFailedConnectionAttempt(int attempt) {
    if (kDebugMode) {
      debugPrint('Gagal mencoba koneksi MQTT (attempt: $attempt)');
    }
  }

  void pong() {
    if (kDebugMode) debugPrint('Ping response diterima');
  }

  void _startConnectivityMonitoring() {
    _connectivitySubscription?.cancel();
    unawaited(_syncInitialConnectivity());
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      _lastConnectivityResult = result;
      if (result == ConnectivityResult.none) {
        await _setInternetStatus(false, force: true);
        _ensureInternetProbing();
        return;
      }

      final internetOk = await _checkInternet();
      await _setInternetStatus(internetOk, force: true);
      _ensureInternetProbing();
    });
  }

  Future<void> _syncInitialConnectivity() async {
    try {
      _lastConnectivityResult = await Connectivity().checkConnectivity();
    } catch (_) {
      _lastConnectivityResult = ConnectivityResult.none;
    }
    unawaited(_refreshInternetStatus());
    _ensureInternetProbing();
  }

  Future<void> _refreshInternetStatus() async {
    if (_lastConnectivityResult == ConnectivityResult.none) {
      await _setInternetStatus(false, force: true);
      return;
    }
    await _probeInternetOnce();
  }

  void _ensureInternetProbing() {
    final mqttConnected =
        client?.connectionStatus?.state == MqttConnectionState.connected;
    final shouldProbe =
        _lastConnectivityResult != ConnectivityResult.none &&
        (!hasInternet || !mqttConnected);

    if (!shouldProbe) {
      _internetProbeTimer?.cancel();
      _internetProbeTimer = null;
      return;
    }

    if (_internetProbeTimer != null) return;

    unawaited(_probeInternetOnce());
    _internetProbeTimer = Timer.periodic(const Duration(seconds: 30), (
      _,
    ) async {
      final mqttConnectedNow =
          client?.connectionStatus?.state == MqttConnectionState.connected;
      final shouldProbeNow =
          _lastConnectivityResult != ConnectivityResult.none &&
          (!hasInternet || !mqttConnectedNow);
      if (!shouldProbeNow) {
        _internetProbeTimer?.cancel();
        _internetProbeTimer = null;
        return;
      }

      if (_isProbingInternet) return;
      _isProbingInternet = true;
      try {
        final internetOk = await _checkInternet();
        await _setInternetStatus(internetOk);
      } finally {
        _isProbingInternet = false;
      }
    });
  }

  Future<void> _probeInternetOnce() async {
    if (_lastConnectivityResult == ConnectivityResult.none) return;
    if (_isProbingInternet) return;
    _isProbingInternet = true;
    try {
      final internetOk = await _checkInternet();
      await _setInternetStatus(internetOk, force: true);
    } finally {
      _isProbingInternet = false;
    }
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup(
        'example.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setInternetStatus(bool internetOk, {bool force = false}) async {
    if (internetOk) {
      _internetFailStreak = 0;
    } else {
      _internetFailStreak += 1;
    }

    final bool effectiveInternetOk = force
        ? internetOk
        : (internetOk || _internetFailStreak < 2);

    if (effectiveInternetOk == hasInternet) return;

    hasInternet = effectiveInternetOk;
    if (!hasInternet) {
      lastConnectionError = 'Tidak ada koneksi internet';
      await _clearUpdatesSubscription();
      _disconnectInternal();
      _cancelMqttReconnect();
    } else {
      lastConnectionError = null;
      _mqttReconnectAttempt = 0;
      _scheduleMqttReconnect(immediate: true);
      unawaited(SupabaseService.instance.flushPendingSensorData());
    }

    _ensureInternetProbing();
    notifyListeners();
  }

  void _cancelMqttReconnect() {
    _mqttReconnectTimer?.cancel();
    _mqttReconnectTimer = null;
  }

  void _scheduleMqttReconnect({bool immediate = false}) {
    if (!hasInternet) return;
    if (isConnecting) return;
    if (client?.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }
    if (_mqttReconnectTimer != null) return;

    final delay = immediate ? Duration.zero : _nextReconnectDelay();
    _mqttReconnectTimer = Timer(delay, () {
      _mqttReconnectTimer = null;
      if (!hasInternet) return;
      if (client?.connectionStatus?.state == MqttConnectionState.connected) {
        return;
      }
      if (isConnecting) return;
      unawaited(connect());
    });
  }

  Duration _nextReconnectDelay() {
    final attempt = _mqttReconnectAttempt.clamp(0, 6);
    final seconds = switch (attempt) {
      0 => 2,
      1 => 4,
      2 => 8,
      3 => 16,
      4 => 30,
      _ => 60,
    };
    return Duration(seconds: seconds);
  }

  Map<String, dynamic> _mergeSensorData(Map<String, dynamic> incomingData) {
    final merged = {
      ...sensorData,
      ...incomingData.map(
        (key, value) => MapEntry(key, _normalizeForStorage(value)),
      ),
    };

    final deviceId = incomingData['device_id'] ?? incomingData['id_perangkat'];
    if (deviceId != null) {
      merged['device_id'] = deviceId.toString();
      merged['id_perangkat'] = deviceId.toString();
    }
    return merged;
  }

  dynamic _normalizeForStorage(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    return value.toString();
  }

  Future<void> _restoreCachedSensorData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawCache = prefs.getString(_sensorDataCacheKey);
      if (rawCache == null || rawCache.isEmpty) {
        isRestoringCache = false;
        notifyListeners();
        return;
      }

      final decoded = jsonDecode(rawCache);
      if (decoded is Map) {
        sensorData = _mergeSensorData(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
        isUsingCachedData = true;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Gagal memulihkan cache sensor: $e');
      }
    } finally {
      isRestoringCache = false;
      notifyListeners();
    }
  }

  Future<void> _persistSensorData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sensorDataCacheKey, jsonEncode(sensorData));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Gagal menyimpan cache sensor: $e');
      }
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _internetProbeTimer?.cancel();
    _cancelMqttReconnect();
    _clearUpdatesSubscription();
    _disconnectInternal();
    super.dispose();
  }
}
