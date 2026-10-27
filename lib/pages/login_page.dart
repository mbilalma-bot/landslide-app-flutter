import 'dart:async';

import 'package:flutter/material.dart';
import 'package:landslide_app/pages/dashboard_page.dart';
import 'package:landslide_app/supabase/supabase_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  void _showRegisterDialog() {
    final messenger = ScaffoldMessenger.of(context);
    final regFormKey = GlobalKey<FormState>();
    final namaController = TextEditingController();
    final userController = TextEditingController();
    final passController = TextEditingController();
    final confirmPassController = TextEditingController();
    
    bool isRegSubmitting = false;
    bool? isUsernameTaken;
    bool isCheckingUsername = false;
    Timer? debounceTimer;
    bool obscurePass = true;
    bool obscureConfirmPass = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void checkUsername(String value) {
              if (debounceTimer?.isActive ?? false) debounceTimer!.cancel();
              if (value.trim().isEmpty) {
                setDialogState(() {
                  isUsernameTaken = null;
                  isCheckingUsername = false;
                });
                return;
              }

              setDialogState(() => isCheckingUsername = true);
              debounceTimer = Timer(const Duration(milliseconds: 600), () async {
                final exists = await SupabaseService.instance.checkUsernameExists(value);
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  isUsernameTaken = exists;
                  isCheckingUsername = false;
                });
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Column(
                children: [
                  _LogoCircle(size: 70),
                  SizedBox(height: 10),
                  Text(
                    'Daftar Akun Baru',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: regFormKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTextField(
                        controller: namaController,
                        label: 'NAMA',
                        icon: Icons.person_outline_rounded,
                        validator: (v) => v == null || v.isEmpty ? 'Nama wajib diisi' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: userController,
                        label: 'USERNAME',
                        icon: Icons.alternate_email_rounded,
                        onChanged: checkUsername,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Username wajib diisi';
                          if (isUsernameTaken == true) return 'Username sudah digunakan';
                          return null;
                        },
                      ),
                      _buildUsernameStatus(isCheckingUsername, isUsernameTaken, userController.text),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: passController,
                        label: 'PASSWORD',
                        icon: Icons.lock_outline_rounded,
                        obscureText: obscurePass,
                        suffixIcon: IconButton(
                          icon: Icon(obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                        ),
                        validator: (v) => v == null || v.length < 8 ? 'Minimal 8 karakter' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: confirmPassController,
                        label: 'KONFIRMASI PASSWORD',
                        icon: Icons.lock_reset_rounded,
                        obscureText: obscureConfirmPass,
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirmPass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setDialogState(() => obscureConfirmPass = !obscureConfirmPass),
                        ),
                        validator: (v) => v != passController.text ? 'Password tidak cocok' : null,
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              actions: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: isRegSubmitting || isCheckingUsername
                          ? null
                          : () async {
                              if (!regFormKey.currentState!.validate()) return;
                              setDialogState(() => isRegSubmitting = true);
                              try {
                                await SupabaseService.instance.registerUser(
                                  nama: namaController.text,
                                  username: userController.text,
                                  password: passController.text,
                                );
                                if (!dialogContext.mounted) return;
                                Navigator.pop(dialogContext);
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Pendaftaran berhasil! Silakan login.'),
                                    backgroundColor: Color(0xFF2E7D32),
                                  ),
                                );
                              } catch (e) {
                                setDialogState(() => isRegSubmitting = false);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Gagal mendaftar: $e'),
                                    backgroundColor: const Color(0xFFC62828),
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8A6242),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isRegSubmitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('DAFTAR', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                    // const SizedBox(height: 10),
                    // const Text('Sudah punya akun? Masuk di sini.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 186, 172, 162),
                        foregroundColor: Color(0xFF8A6242),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('KEMBALI', style: TextStyle(color: Color.fromARGB(255, 77, 54, 36), fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final user = await SupabaseService.instance.loginUser(
        username: _usernameController.text,
        password: _passwordController.text,
      );

      if (user != null) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Login berhasil! Selamat datang.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardPage()),
        );
      } else {
        setState(() => _isLoading = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Username atau Password salah'),
            backgroundColor: Color(0xFFC62828),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Terjadi kesalahan: $e'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 40),
                const _LogoCircle(size: 120),
                const SizedBox(height: 60),
                _buildTextField(
                  controller: _usernameController,
                  label: 'USERNAME',
                  icon: Icons.person_outline_rounded,
                  validator: (v) => v == null || v.isEmpty ? 'Username wajib diisi' : null,
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _passwordController,
                  label: 'PASSWORD',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Password wajib diisi' : null,
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A6242),
                    foregroundColor: const Color.fromARGB(255, 255, 255, 255),
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text(
                          'MASUK',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          )
                        ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Belum punya akun? ',
                      style: TextStyle(
                        fontSize: 14
                        )
                      ),
                    GestureDetector(
                      onTap: _showRegisterDialog,
                      child: const Text(
                        'Daftar di sini.',
                        style: TextStyle(color: Color(0xFF8A6242), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                // ElevatedButton(
                //   onPressed: _showRegisterDialog,
                //   style: ElevatedButton.styleFrom(
                //     backgroundColor: const Color(0xFFCAD4DC),
                //     foregroundColor: const Color(0xFF2F241D),
                //     minimumSize: const Size(double.infinity, 52),
                //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                //     elevation: 0,
                //   ),
                //   child: const Text('DAFTAR', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      onChanged: onChanged,
      validator: validator,
      // style: const TextStyle(fontSize: 16), // <--- UNTUK MENGATUR UKURAN FONT TEKS INPUT
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        // labelStyle: const TextStyle(fontSize: 14), // <--- UNTUK MENGATUR UKURAN FONT LABEL
        labelStyle: const TextStyle(fontSize: 12),
        prefixIcon: Icon(icon, color: const Color(0xFF7C746E)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color.fromARGB(255, 138, 116, 98).withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildUsernameStatus(bool isChecking, bool? isTaken, String text) {
    if (isChecking) {
      return const Padding(
        padding: EdgeInsets.only(top: 6, left: 4),
        child: Row(
          children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8A6242))),
            SizedBox(width: 8),
            Text('Mengecek username...', style: TextStyle(fontSize: 12, color: Color(0xFF7C746E))),
          ],
        ),
      );
    }
    if (isTaken == true) {
      return const Padding(
        padding: EdgeInsets.only(top: 6, left: 4),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Color(0xFFC62828), size: 14),
            SizedBox(width: 6),
            Text('Username sudah terdaftar', style: TextStyle(fontSize: 12, color: Color(0xFFC62828), fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    if (isTaken == false && text.trim().isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 6, left: 4),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 14),
            SizedBox(width: 6),
            Text('Username tersedia', style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _LogoCircle extends StatelessWidget {
  final double size;
  const _LogoCircle({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 255, 255),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: ClipOval(
        child: Image.asset(
          'lib/materials/logo_landslide.png',
          width: size * 0.95,
          height: size * 0.95,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Text(
              'LOGO',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF2F241D),
                fontSize: size * 0.2,
              ),
            );
          },
        ),
      ),
    );
  }
}