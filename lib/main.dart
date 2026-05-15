
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'core/app_theme.dart';
import 'features/bluetooth/ble_provider.dart';
import 'features/translation/translation_provider.dart';
import 'features/home/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BLEProvider()),
        ChangeNotifierProxyProvider<BLEProvider, TranslationProvider>(
          create: (context) => TranslationProvider(),
          update: (context, ble, translation) {
            final trans = translation ?? TranslationProvider();
            // Sinkronisasi data sensor ke translator
            if (ble.connectionState == BluetoothConnectionState.connected || ble.isMockMode) {
              if (ble.currentData.isNotEmpty) {
                trans.updateData(ble.currentData);
              }
            }
            return trans;
          },
        ),
      ],
      child: MaterialApp(
        title: 'SIBI Translator',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme, // Force Dark Theme for Premium feel
        home: const HomeScreen(),
      ),
    );
  }
}
