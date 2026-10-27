import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:landslide_app/models/user_model.dart';
import 'package:landslide_app/mqtt/mqtt_client_android.dart';
import 'package:landslide_app/pages/dashboard_page.dart';
import 'package:landslide_app/pages/login_page.dart';
import 'package:landslide_app/supabase/supabase_config.dart';
import 'package:landslide_app/supabase/supabase_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('id_ID', null);

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  // Cek session login sebelum menjalankan aplikasi
  final user = await SupabaseService.instance.loadUserSession();

  runApp(
    ChangeNotifierProvider(
      create: (_) => MqttHandler(),
      child: MyApp(initialUser: user),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.initialUser});

  final UserModel? initialUser;

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF8A6242);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'LandslideApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF2F241D),
          surfaceTintColor: Colors.white,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: seedColor.withValues(alpha: 0.16),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final color = states.contains(WidgetState.selected)
                ? seedColor
                : const Color(0xFF7C746E);
            return IconThemeData(color: color);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? seedColor
                  : const Color(0xFF7C746E),
            );
          }),
        ),
      ),
      home: initialUser != null ? const DashboardPage() : const LoginPage(),
    );
  }
}
