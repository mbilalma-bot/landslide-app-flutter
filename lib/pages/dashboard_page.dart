import 'dart:async';

import 'package:flutter/material.dart';
import 'package:landslide_app/models/perangkat_model.dart';
import 'package:landslide_app/mqtt/mqtt_client_android.dart';
import 'package:landslide_app/pages/login_page.dart';
import 'package:landslide_app/pages/monitoring_page.dart';
import 'package:landslide_app/pages/profil_page.dart';
import 'package:landslide_app/pages/riwayat_page.dart';
import 'package:landslide_app/supabase/supabase_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:provider/provider.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    this.initialIndex = 0,
    this.enableCharts = true,
    this.autoConnect = true,
  });

  final int initialIndex;
  final bool enableCharts;
  final bool autoConnect;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late int _selectedIndex;
  PerangkatModel? _selectedPerangkat;

  List<PerangkatModel> _perangkatList = <PerangkatModel>[];
  bool _isLoadingPerangkat = true;
  String? _perangkatError;

  static const List<String> _pageTitles = <String>[
    'Dashboard',
    'Riwayat',
    'Profil',
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _loadPerangkatList();

    if (!widget.autoConnect) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mqttHandler = Provider.of<MqttHandler?>(context, listen: false);
      if (mqttHandler == null) return;

      final isConnected =
          mqttHandler.client?.connectionStatus?.state ==
          MqttConnectionState.connected;

      if (mqttHandler.hasInternet &&
          !mqttHandler.isConnecting &&
          !isConnected) {
        mqttHandler.connect();
      }
    });
  }

  Future<void> _loadPerangkatList() async {
    setState(() {
      _isLoadingPerangkat = true;
      _perangkatError = null;
    });

    try {
      final user = SupabaseService.instance.currentUser;
      if (user == null || user.id == null) {
        throw Exception('User tidak ditemukan');
      }

      final list = await SupabaseService.instance.fetchUserPerangkatList(user.id!);
      if (!mounted) return;
      setState(() {
        _perangkatList = list;
        _isLoadingPerangkat = false;

        // Jika perangkat yang sedang dimonitor diperbarui, sinkronkan data namanya
        if (_selectedPerangkat != null) {
          final found = list.where(
            (p) => p.idPerangkat == _selectedPerangkat!.idPerangkat,
          );
          if (found.isNotEmpty) {
            _selectedPerangkat = found.first;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _perangkatError = 'Gagal memuat perangkat: $e';
        _isLoadingPerangkat = false;
      });
    }
  }

  void _showTambahPerangkatDialog() {
    final messenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final idController = TextEditingController();
    final namaController = TextEditingController();
    bool isSubmitting = false;

    // State untuk pengecekan ID
    bool? isIdRegistered;
    String? existingDeviceName;
    bool? isAlreadyOwned;
    bool isCheckingId = false;
    Timer? debounceTimer;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void checkId(String value) {
              if (debounceTimer?.isActive ?? false) debounceTimer!.cancel();
              if (value.trim().isEmpty) {
                setDialogState(() {
                  isIdRegistered = null;
                  existingDeviceName = null;
                  isAlreadyOwned = null;
                  isCheckingId = false;
                });
                return;
              }

              setDialogState(() => isCheckingId = true);
              debounceTimer = Timer(const Duration(milliseconds: 600), () async {
                final cleanId = value.trim();
                final existingDevice =
                    await SupabaseService.instance.getDeviceById(cleanId);
                
                bool owned = false;
                final user = SupabaseService.instance.currentUser;
                if (user?.id != null) {
                  owned = await SupabaseService.instance.isDeviceLinkedToUser(
                    user!.id!,
                    cleanId,
                  );
                }

                if (!dialogContext.mounted) return;
                setDialogState(() {
                  isIdRegistered = existingDevice != null;
                  existingDeviceName = existingDevice?.namaPerangkat;
                  isAlreadyOwned = owned;
                  isCheckingId = false;
                  
                  // Auto-fill nama jika ditemukan dan user belum mengetik nama sendiri secara manual
                  // atau jika user baru saja memasukkan ID yang terdaftar
                  if (existingDevice != null && namaController.text.isEmpty) {
                    namaController.text = existingDevice.namaPerangkat;
                  }
                });
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.developer_board_rounded, color: Color(0xFF8A6242)),
                  SizedBox(width: 10),
                  Text(
                    'Tambah Perangkat',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: idController,
                        onChanged: checkId,
                        decoration: InputDecoration(
                          labelText: 'ID Perangkat',
                          hintText: 'Contoh: ESP32-S3-Longsor',
                          prefixIcon: const Icon(Icons.qr_code_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'ID Perangkat wajib diisi';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(  
                        controller: namaController,
                        decoration: InputDecoration(
                          labelText: 'Nama Perangkat',
                          hintText: 'Contoh: Lereng Barat Bukit',
                          prefixIcon: const Icon(Icons.label_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Nama Perangkat wajib diisi';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 6),
                      // Indikator Status Pendaftaran ID
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Builder(
                          builder: (context) {
                            if (isCheckingId) {
                              return const Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF8A6242),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Mengecek ID...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF7C746E),
                                    ),
                                  ),
                                ],
                              );
                            }

                            if (isAlreadyOwned == true) {
                              return const Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Color(0xFFF57C00),
                                    size: 14,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Perangkat sudah Anda miliki',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFF57C00),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              );
                            }

                            if (isIdRegistered == true) {
                              return Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF2E7D32),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Perangkat ditemukan: "$existingDeviceName". Anda bisa mengganti namanya jika mau.',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF2E7D32),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            if (isIdRegistered == false &&
                                idController.text.trim().isNotEmpty) {
                              return const Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    color: Color(0xFF1976D2),
                                    size: 14,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'ID Baru (Akan ditambahkan ke sistem)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF1976D2),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                OutlinedButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          debounceTimer?.cancel();
                          Navigator.of(dialogContext).pop();
                        },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Kembali'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting || isCheckingId || isAlreadyOwned == true
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSubmitting = true);
                          try {
                            final user = SupabaseService.instance.currentUser;
                            await SupabaseService.instance.addPerangkat(
                              idPerangkat: idController.text.trim(),
                              namaPerangkat: namaController.text.trim(),
                              userId: user?.id,
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Perangkat berhasil dihubungkan!'),
                                backgroundColor: Color(0xFF2E7D32),
                              ),
                            );
                            _loadPerangkatList();
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Gagal menyimpan: $e'),
                                backgroundColor: const Color(0xFFC62828),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A6242),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Simpan ID',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditPerangkatDialog(PerangkatModel perangkat) {
    final messenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final namaController = TextEditingController(text: perangkat.namaPerangkat);
    bool isSubmitting = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.edit_rounded, color: Color(0xFF8A6242)),
                  SizedBox(width: 10),
                  Text(
                    'Edit Perangkat',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F3EF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE7DDD3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ID Perangkat (Tetap):',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7C746E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              perangkat.idPerangkat,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2F241D),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: namaController,
                        decoration: InputDecoration(
                          labelText: 'Nama Perangkat',
                          prefixIcon: const Icon(Icons.label_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Nama Perangkat wajib diisi';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                OutlinedButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Kembali'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSubmitting = true);
                          try {
                            await SupabaseService.instance.updatePerangkat(
                              idPerangkat: perangkat.idPerangkat,
                              namaPerangkat: namaController.text.trim(),
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Perubahan nama berhasil disimpan!'),
                                backgroundColor: Color(0xFF2E7D32),
                              ),
                            );
                            _loadPerangkatList();
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Gagal memperbarui: $e'),
                                backgroundColor: const Color(0xFFC62828),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A6242),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Simpan Perubahan',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmHapusPerangkat(PerangkatModel perangkat) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Hapus Perangkat?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: Text(
            'Apakah Anda yakin ingin menghapus perangkat "${perangkat.namaPerangkat}" (${perangkat.idPerangkat}) dari database?',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  final user = SupabaseService.instance.currentUser;
                  await SupabaseService.instance.deletePerangkat(
                    perangkat.idPerangkat,
                    userId: user?.id,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Perangkat berhasil dihapus!'),
                      backgroundColor: Color(0xFF2E7D32),
                    ),
                  );
                  if (_selectedPerangkat?.idPerangkat == perangkat.idPerangkat) {
                    setState(() {
                      _selectedPerangkat = null;
                    });
                  }
                  _loadPerangkatList();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal menghapus: $e'),
                      backgroundColor: const Color(0xFFC62828),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mqttHandler = Provider.of<MqttHandler?>(context);
    final isInsideMonitoring = _selectedIndex == 0 && _selectedPerangkat != null;

    final pages = <Widget>[
      _buildDashboardContent(),
      const RiwayatPage(),
      const ProfilPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: isInsideMonitoring ? 0 : 16,
        leading: isInsideMonitoring
            ? IconButton(
                tooltip: 'Kembali ke Daftar Perangkat',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  setState(() {
                    _selectedPerangkat = null;
                  });
                },
              )
            : null,
        title: Row(
          children: [
            if (!isInsideMonitoring) ...[
              const _LogoBadge(),
              const SizedBox(width: 12),
            ] else ...[
              const SizedBox(width: 4),
              const _LogoBadge(),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                isInsideMonitoring ? 'Monitoring' : _pageTitles[_selectedIndex],
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        actions: [
          _ConnectionStatusButton(mqttHandler: mqttHandler),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            color: Colors.white,
            surfaceTintColor: Colors.white,
            onSelected: (value) async {
              if (value == 'logout') {
                await SupabaseService.instance.clearUserSession();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Berhasil Logout')),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(value: 'logout', child: Text('Logout')),
            ],
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      floatingActionButton: (_selectedIndex == 0 && _selectedPerangkat == null)
          ? SizedBox(
              width: 58,
              height: 64,
              child: FloatingActionButton(
                onPressed: _showTambahPerangkatDialog,
                backgroundColor: const Color(0xFF8A6242),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 4,
                tooltip: 'Tambah Perangkat',
                child: const Icon(Icons.add_rounded, size: 32),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (_selectedIndex == index) return;
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Riwayat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    if (_selectedPerangkat != null) {
      return MonitoringPage(
        perangkat: _selectedPerangkat!,
        enableCharts: widget.enableCharts,
        onBack: () {
          setState(() {
            _selectedPerangkat = null;
          });
        },
      );
    }

    if (_isLoadingPerangkat) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8A6242)),
      );
    }

    if (_perangkatError != null && _perangkatList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _perangkatError!,
              style: const TextStyle(color: Color(0xFFC62828)),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadPerangkatList,
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    // Tampilan kosong jika belum ada perangkat terdaftar
    if (_perangkatList.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPerangkatList,
        color: const Color(0xFF8A6242),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Belum ada Perangkat yang terdaftar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontStyle: FontStyle.italic,
                      color: const Color(0xFF2F241D).withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Tampilan daftar perangkat berupa kartu
    return RefreshIndicator(
      onRefresh: _loadPerangkatList,
      color: const Color(0xFF8A6242),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _perangkatList.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final perangkat = _perangkatList[index];
          return _PerangkatCard(
            perangkat: perangkat,
            onTap: () {
              setState(() {
                _selectedPerangkat = perangkat;
              });
            },
            onEdit: () => _showEditPerangkatDialog(perangkat),
            onHapus: () => _confirmHapusPerangkat(perangkat),
          );
        },
      ),
    );
  }
}

class _PerangkatCard extends StatelessWidget {
  const _PerangkatCard({
    required this.perangkat,
    required this.onTap,
    required this.onEdit,
    required this.onHapus,
  });

  final PerangkatModel perangkat;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onHapus;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFCAD4DC), // Warna abu-abu lembut sesuai wireframe gambar 2
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ID ALAT : ${perangkat.idPerangkat}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E272E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      perangkat.namaPerangkat,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF3B4856),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit Perangkat',
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: Color(0xFF1976D2), // Biru
                      size: 22,
                    ),
                    splashRadius: 22,
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Hapus Perangkat',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFD32F2F), // Merah
                      size: 22,
                    ),
                    splashRadius: 22,
                    onPressed: onHapus,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF8A6242).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'lib/materials/logo_landslide.png',
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.terrain_rounded, color: Color(0xFF8A6242));
          },
        ),
      ),
    );
  }
}

class _ConnectionStatusButton extends StatelessWidget {
  const _ConnectionStatusButton({required this.mqttHandler});

  final MqttHandler? mqttHandler;

  @override
  Widget build(BuildContext context) {
    final isConnected = _isFullyConnected(mqttHandler);
    final iconColor = isConnected
        ? const Color(0xFF2E7D32)
        : const Color(0xFF8B8B8B);

    return IconButton(
      tooltip: _tooltipText(mqttHandler),
      onPressed: () {},
      splashRadius: 22,
      icon: SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.wifi_rounded, color: iconColor, size: 24),
            if (!isConnected)
              Transform.rotate(
                angle: -0.72,
                child: Container(
                  width: 3,
                  height: 24,
                  decoration: BoxDecoration(
                    color: iconColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _isFullyConnected(MqttHandler? mqttHandler) {
    if (mqttHandler == null) return false;
    return mqttHandler.hasInternet &&
        mqttHandler.client?.connectionStatus?.state ==
            MqttConnectionState.connected;
  }

  static String _tooltipText(MqttHandler? mqttHandler) {
    if (mqttHandler == null) {
      return 'Status koneksi tidak tersedia';
    }

    final mqttConnected =
        mqttHandler.client?.connectionStatus?.state ==
        MqttConnectionState.connected;

    if (mqttHandler.hasInternet && mqttConnected) {
      return 'Internet aktif, MQTT terhubung';
    }
    if (!mqttHandler.hasInternet) {
      return 'Internet tidak tersedia';
    }
    if (mqttHandler.isConnecting) {
      return 'Internet aktif, MQTT sedang menghubungkan';
    }
    return 'Internet aktif, MQTT terputus';
  }
}
