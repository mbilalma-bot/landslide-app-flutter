import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:landslide_app/models/perangkat_model.dart';
import 'package:landslide_app/models/riwayat_row.dart';
import 'package:landslide_app/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();
  static const String _pendingSensorKey = 'supabase_sensor_data_pending_v1';
  static const int _maxPendingItems = 200;
  bool _isFlushingPending = false;

  SupabaseClient get client => Supabase.instance.client;

  // ==========================================
  // 1. MANAJEMEN IDENTITAS PERANGKAT
  // ==========================================

  Future<List<PerangkatModel>> fetchPerangkatList() async {
    try {
      final response = await client
          .from('identitas_perangkat')
          .select()
          .order('id_perangkat', ascending: true)
          .timeout(const Duration(seconds: 8));

      final list = (response as List)
          .cast<Map<String, dynamic>>()
          .map((item) => PerangkatModel.fromMap(item))
          .toList();
      return list;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Supabase fetchPerangkatList error: $e');
        debugPrintStack(stackTrace: st);
      }
      return <PerangkatModel>[];
    }
  }

  Future<List<PerangkatModel>> fetchUserPerangkatList(int userId) async {
    try {
      final response = await client
          .from('registrasi_perangkat')
          .select('identitas_perangkat(*)')
          .eq('id_user', userId)
          .timeout(const Duration(seconds: 8));

      final list = (response as List).map((item) {
        final deviceData = item['identitas_perangkat'] as Map<String, dynamic>;
        return PerangkatModel.fromMap(deviceData);
      }).toList();

      return list;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Supabase fetchUserPerangkatList error: $e');
        debugPrintStack(stackTrace: st);
      }
      return <PerangkatModel>[];
    }
  }

  Future<PerangkatModel?> getDeviceById(String idPerangkat) async {
    try {
      final response = await client
          .from('identitas_perangkat')
          .select()
          .eq('id_perangkat', idPerangkat.trim())
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      
      if (response == null) return null;
      return PerangkatModel.fromMap(response);
    } catch (e) {
      if (kDebugMode) debugPrint('getDeviceById error: $e');
      return null;
    }
  }

  Future<bool> checkDeviceExists(String idPerangkat) async {
    final device = await getDeviceById(idPerangkat);
    return device != null;
  }

  Future<bool> isDeviceLinkedToUser(int userId, String idPerangkat) async {
    try {
      final response = await client
          .from('registrasi_perangkat')
          .select('id')
          .eq('id_user', userId)
          .eq('id_perangkat', idPerangkat.trim())
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      return response != null;
    } catch (e) {
      if (kDebugMode) debugPrint('isDeviceLinkedToUser error: $e');
      return false;
    }
  }

  Future<void> addPerangkat({
    required String idPerangkat,
    required String namaPerangkat,
    int? userId,
  }) async {
    final cleanId = idPerangkat.trim();
    final cleanNama = namaPerangkat.trim();

    try {
      // 1. Pastikan perangkat ada di tabel master identitas_perangkat
      // Jika belum ada, tambahkan sebagai perangkat baru
      // Jika sudah ada, update namanya (jika user mengubahnya di dialog)
      final existingDevice = await getDeviceById(cleanId);
      if (existingDevice == null) {
        await client.from('identitas_perangkat').insert({
          'id_perangkat': cleanId,
          'nama_perangkat': cleanNama,
        });
      } else if (existingDevice.namaPerangkat != cleanNama) {
        // Update nama di master jika berbeda
        await updatePerangkat(
          idPerangkat: cleanId,
          namaPerangkat: cleanNama,
        );
      }

      // 2. Jika ada userId, hubungkan perangkat ke user tersebut di registrasi_perangkat
      if (userId != null) {
        // Cek apakah sudah terhubung sebelumnya
        final alreadyLinked = await isDeviceLinkedToUser(userId, cleanId);
        if (!alreadyLinked) {
          await client.from('registrasi_perangkat').insert({
            'id_user': userId,
            'id_perangkat': cleanId,
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('addPerangkat error: $e');
      rethrow;
    }
  }

  Future<void> updatePerangkat({
    required String idPerangkat,
    required String namaPerangkat,
  }) async {
    final cleanNama = namaPerangkat.trim();

    try {
      await client
          .from('identitas_perangkat')
          .update({'nama_perangkat': cleanNama})
          .eq('id_perangkat', idPerangkat.trim())
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      if (kDebugMode) debugPrint('updatePerangkat error: $e');
      rethrow;
    }
  }

  Future<void> deletePerangkat(String idPerangkat, {int? userId}) async {
    try {
      if (userId != null) {
        // Hapus hubungan user dengan perangkat saja (Unlink)
        // Aksi ini tidak menghapus data di tabel identitas_perangkat
        await client
            .from('registrasi_perangkat')
            .delete()
            .eq('id_user', userId)
            .eq('id_perangkat', idPerangkat.trim())
            .timeout(const Duration(seconds: 8));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('deletePerangkat error: $e');
      rethrow;
    }
  }

  // ==========================================
  // 2. PENGIRIMAN & PENYIMPANAN DATA SENSOR
  // ==========================================

  Future<void> insertSensorData({
    required String idPerangkat,
    required DateTime waktuUpdate,
    required double nilaiHujan,
    required String statusHujan,
    required double nilaiKelembapan,
    required String statusKelembapan,
    required double nilaiKemiringan,
    required String statusKemiringan,
    required String kerawananLongs,
  }) async {
    final payload = <String, dynamic>{
      'id_perangkat': idPerangkat.trim(),
      'waktu_update': waktuUpdate.toIso8601String(),
      'nilai_hujan': nilaiHujan,
      'status_hujan': statusHujan,
      'nilai_kelembapan': nilaiKelembapan,
      'status_kelembapan': statusKelembapan,
      'nilai_kemiringan': nilaiKemiringan,
      'status_kemiringan': statusKemiringan,
      'kerawanan_longsor': kerawananLongs,
    };

    try {
      await client
          .from('sensor_data')
          .insert(payload)
          .timeout(const Duration(seconds: 6));
    } catch (e, st) {
      await _enqueuePendingSensorData(payload);
      if (kDebugMode) {
        debugPrint('Supabase insertSensorData error: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  Future<void> insertSensorDataFromMqtt(Map<String, dynamic> mqttData) async {
    DateTime? waktuUpdate;
    final rawWaktu = mqttData['waktu'];
    if (rawWaktu is String) {
      final normalized = rawWaktu.contains('T')
          ? rawWaktu
          : rawWaktu.replaceFirst(' ', 'T');
      waktuUpdate = DateTime.tryParse(normalized);
    } else if (rawWaktu is DateTime) {
      waktuUpdate = rawWaktu;
    }
    waktuUpdate ??= DateTime.now();

    double parseDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    final idPerangkat = (mqttData['device_id'] ??
            mqttData['id_perangkat'] ??
            'ESP32-S3-Longsor')
        .toString()
        .trim();
    final nilaiHujan = parseDouble(mqttData['Sensor Hujan']);
    final statusHujan = (mqttData['Status Hujan'] ?? 'N/A').toString();
    final nilaiKelembapan = parseDouble(mqttData['Sensor Kelembapan']);
    final statusKelembapan = (mqttData['Status Kelembapan'] ?? 'N/A')
        .toString();
    final nilaiKemiringan = parseDouble(mqttData['Sensor Kemiringan']);
    final statusKemiringan = (mqttData['Status Kemiringan'] ?? 'N/A')
        .toString();
    final kerawananLongs = (mqttData['Status Kerawanan'] ?? 'N/A').toString();

    final payload = <String, dynamic>{
      'id_perangkat': idPerangkat,
      'waktu_update': waktuUpdate.toIso8601String(),
      'nilai_hujan': nilaiHujan,
      'status_hujan': statusHujan,
      'nilai_kelembapan': nilaiKelembapan,
      'status_kelembapan': statusKelembapan,
      'nilai_kemiringan': nilaiKemiringan,
      'status_kemiringan': statusKemiringan,
      'kerawanan_longsor': kerawananLongs,
    };

    try {
      await client
          .from('sensor_data')
          .insert(payload)
          .timeout(const Duration(seconds: 6));
    } catch (e, st) {
      await _enqueuePendingSensorData(payload);
      if (kDebugMode) {
        debugPrint('Supabase insertSensorDataFromMqtt queued: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  Future<List<Map<String, dynamic>>> fetchSensorDataLastHours({
    String? idPerangkat,
    int hours = 24,
    int? limit,
  }) async {
    final since = DateTime.now()
        .toUtc()
        .subtract(Duration(hours: hours))
        .toIso8601String();
    var filter = client
        .from('sensor_data')
        .select(
          'id_perangkat,waktu_update,nilai_hujan,nilai_kelembapan,nilai_kemiringan,status_hujan,status_kelembapan,status_kemiringan,kerawanan_longsor',
        )
        .gte('waktu_update', since);

    if (idPerangkat != null && idPerangkat.trim().isNotEmpty) {
      filter = filter.eq('id_perangkat', idPerangkat.trim());
    }

    var transform = filter.order('waktu_update', ascending: true);

    if (limit != null) {
      transform = transform.limit(limit);
    }

    final res = await transform.timeout(const Duration(seconds: 6));
    return (res as List).cast<Map<String, dynamic>>();
  }

  // ==========================================
  // 3. RIWAYAT PERUBAHAN STATUS KERAWANAN
  // ==========================================

  Future<List<RiwayatRow>> fetchRiwayatSensorData({int limit = 400}) async {
    try {
      // Ambil data sensor terurut kronologis (ascending) untuk diproses logika transisi status
      final response = await client
          .from('sensor_data')
          .select(
            'id,id_perangkat,waktu_update,nilai_hujan,status_hujan,nilai_kelembapan,status_kelembapan,nilai_kemiringan,status_kemiringan,kerawanan_longsor',
          )
          .order('waktu_update', ascending: true)
          .limit(limit)
          .timeout(const Duration(seconds: 8));

      final rows = (response as List)
          .cast<Map<String, dynamic>>()
          .map((item) => RiwayatRow.fromMap(item))
          .toList();

      return rows;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Supabase fetchRiwayatSensorData error: $e');
        debugPrintStack(stackTrace: st);
      }
      return <RiwayatRow>[];
    }
  }

  Stream<List<RiwayatRow>> riwayatStream({int limit = 500}) {
    return client
        .from('sensor_data')
        .stream(primaryKey: ['id'])
        .order('waktu_update', ascending: true)
        .limit(limit)
        .map((event) {
          return event.map((item) => RiwayatRow.fromMap(item)).toList();
        });
  }

  // ==========================================
  // 4. USER AUTH (user_data)
  // ==========================================

  static const String _userSessionKey = 'landslide_user_session_v1';
  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  Future<void> saveUserSession(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userSessionKey, jsonEncode(user.toMap()));
    _currentUser = user;
  }

  Future<UserModel?> loadUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userSessionKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      _currentUser = UserModel.fromMap(data);
      return _currentUser;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userSessionKey);
    _currentUser = null;
  }

  Future<bool> checkUsernameExists(String username) async {
    try {
      final res = await client
          .from('user_data')
          .select('username_user')
          .eq('username_user', username.trim())
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      return res != null;
    } catch (e) {
      if (kDebugMode) debugPrint('checkUsernameExists error: $e');
      return false;
    }
  }

  Future<UserModel?> registerUser({
    required String nama,
    required String username,
    required String password,
  }) async {
    try {
      final res = await client
          .from('user_data')
          .insert({
            'nama_user': nama.trim(),
            'username_user': username.trim(),
            'password_user': password,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 8));

      return UserModel.fromMap(res);
    } catch (e) {
      if (kDebugMode) debugPrint('registerUser error: $e');
      rethrow;
    }
  }

  Future<UserModel?> loginUser({
    required String username,
    required String password,
  }) async {
    try {
      final res = await client
          .from('user_data')
          .select()
          .eq('username_user', username.trim())
          .eq('password_user', password)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (res == null) return null;
      final user = UserModel.fromMap(res);
      await saveUserSession(user);
      return user;
    } catch (e) {
      if (kDebugMode) debugPrint('loginUser error: $e');
      rethrow;
    }
  }

  Future<void> updateUserData({
    required int id,
    required String nama,
    required String username,
    required String password,
  }) async {
    try {
      final res = await client
          .from('user_data')
          .update({
            'nama_user': nama.trim(),
            'username_user': username.trim(),
            'password_user': password,
          })
          .eq('id', id)
          .select()
          .single()
          .timeout(const Duration(seconds: 8));

      final updatedUser = UserModel.fromMap(res);
      await saveUserSession(updatedUser);
    } catch (e) {
      if (kDebugMode) debugPrint('updateUserData error: $e');
      rethrow;
    }
  }

  // ==========================================
  // 5. CACHE & OFFLINE QUEUE
  // ==========================================

  Future<void> flushPendingSensorData() async {
    if (_isFlushingPending) return;
    _isFlushingPending = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = prefs.getStringList(_pendingSensorKey) ?? <String>[];
      if (items.isEmpty) return;

      final remaining = <String>[];
      var sentCount = 0;

      for (final raw in items) {
        if (sentCount >= 20) {
          remaining.add(raw);
          continue;
        }

        Map<String, dynamic>? payload;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            payload = decoded.map(
              (key, value) => MapEntry(key.toString(), value),
            );
          }
        } catch (_) {}

        if (payload == null) continue;

        try {
          await client
              .from('sensor_data')
              .insert(payload)
              .timeout(const Duration(seconds: 6));
          sentCount += 1;
        } catch (_) {
          remaining.add(raw);
        }
      }

      await prefs.setStringList(_pendingSensorKey, remaining);
    } finally {
      _isFlushingPending = false;
    }
  }

  Future<void> _enqueuePendingSensorData(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = prefs.getStringList(_pendingSensorKey) ?? <String>[];
      items.add(jsonEncode(payload));
      final trimmed = items.length > _maxPendingItems
          ? items.sublist(items.length - _maxPendingItems)
          : items;
      await prefs.setStringList(_pendingSensorKey, trimmed);
    } catch (_) {}
  }
}
