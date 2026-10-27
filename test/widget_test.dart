import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landslide_app/models/perangkat_model.dart';
import 'package:landslide_app/pages/dashboard_page.dart';
import 'package:landslide_app/pages/monitoring_page.dart';

void main() {
  testWidgets('Bottom navigation berpindah antar halaman utama', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DashboardPage(
          enableCharts: false,
          autoConnect: false,
        ),
      ),
    );

    // Verifikasi berada di Dashboard
    expect(find.text('Dashboard'), findsWidgets);

    // Navigasi ke Riwayat
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.text('Riwayat'), findsWidgets);

    // Navigasi ke Profil
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Halaman Profil'), findsOneWidget);

    // Kembali ke Dashboard
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsWidgets);
  });

  testWidgets('MonitoringPage menampilkan ID dan Nama Perangkat', (WidgetTester tester) async {
    const testPerangkat = PerangkatModel(
      idPerangkat: 'ESP32-001',
      namaPerangkat: 'Lereng Bukit Barat',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MonitoringPage(
            perangkat: testPerangkat,
            enableCharts: false,
          ),
        ),
      ),
    );

    expect(find.text('ID Perangkat'), findsOneWidget);
    expect(find.text('ESP32-001'), findsOneWidget);
    expect(find.text('Nama Perangkat'), findsOneWidget);
    expect(find.text('Lereng Bukit Barat'), findsOneWidget);
    expect(find.text('Status Kerentanan Saat Ini'), findsOneWidget);
  });
}
