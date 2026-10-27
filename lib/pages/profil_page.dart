import 'dart:async';

import 'package:flutter/material.dart';
import 'package:landslide_app/supabase/supabase_service.dart';

class ProfilPage extends StatefulWidget {
  const ProfilPage({super.key});

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  void _showEditProfilDialog() {
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final namaController = TextEditingController(text: user.namaUser);
    final userController = TextEditingController(text: user.usernameUser);
    final passController = TextEditingController(text: user.passwordUser);
    final confirmPassController = TextEditingController(text: user.passwordUser);

    bool isSubmitting = false;
    bool obscurePass = true;
    bool obscureConfirmPass = true;
    bool? isUsernameTaken;
    bool isCheckingUsername = false;
    Timer? debounceTimer;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void checkUsername(String value) {
              if (value.trim() == user.usernameUser) {
                setDialogState(() {
                  isUsernameTaken = false;
                  isCheckingUsername = false;
                });
                return;
              }
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
              title: const Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: Color(0xFF8A6242), size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Ubah Data Profil',
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
                      _buildUsernameStatus(isCheckingUsername, isUsernameTaken, userController.text, user.usernameUser),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: passController,
                        label: 'PASSWORD BARU',
                        icon: Icons.lock_outline_rounded,
                        obscureText: obscurePass,
                        suffixIcon: IconButton(
                          icon: Icon(obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                        ),
                        validator: (v) => v == null || v.length < 6 ? 'Minimal 6 karakter' : null,
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
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('BATALKAN'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isSubmitting || isCheckingUsername
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setDialogState(() => isSubmitting = true);
                                try {
                                  await SupabaseService.instance.updateUserData(
                                    id: user.id!,
                                    nama: namaController.text,
                                    username: userController.text,
                                    password: passController.text,
                                  );
                                  if (!dialogContext.mounted) return;
                                  Navigator.pop(dialogContext);
                                  setState(() {}); // Rebuild ProfilPage
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Profil berhasil diperbarui!'),
                                      backgroundColor: Color(0xFF2E7D32),
                                    ),
                                  );
                                } catch (e) {
                                  setDialogState(() => isSubmitting = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Gagal memperbarui profil: $e'),
                                      backgroundColor: const Color(0xFFC62828),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8A6242),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isSubmitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('SIMPAN DATA', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.instance.currentUser;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            // Logo Orang (Referencing Wireframe)
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFCAD4DC),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.person_rounded,
                size: 70,
                color: Color(0xFF8A6242),
              ),
            ),
            const SizedBox(height: 40),

            // Data Profil (Display Only)
            _buildInfoCard(
              label: 'NAMA',
              value: user?.namaUser ?? '-',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 16),
            _buildInfoCard(
              label: 'USERNAME TERKAIT',
              value: user?.usernameUser != null ? '@${user!.usernameUser}' : '-',
              icon: Icons.alternate_email_rounded,
            ),
            const SizedBox(height: 16),
            _buildInfoCard(
              label: 'PASSWORD',
              value: '*' * (user?.passwordUser.length ?? 6),
              icon: Icons.lock_outline_rounded,
            ),
            const SizedBox(height: 32),

            // Tombol Ubah Data
            ElevatedButton.icon(
              onPressed: _showEditProfilDialog,
              icon: const Icon(Icons.edit_rounded, size: 20),
              label: const Text(
                'UBAH DATA?',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCAD4DC),
                foregroundColor: const Color(0xFF2F241D),
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFCAD4DC).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF7C746E), size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7C746E),
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2F241D),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF7C746E)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFCAD4DC).withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildUsernameStatus(bool isChecking, bool? isTaken, String text, String currentUsername) {
    if (text.trim() == currentUsername) return const SizedBox.shrink();
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