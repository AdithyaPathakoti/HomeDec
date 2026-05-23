import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'providers/vastra_provider.dart';
import 'providers/fabric_catalog_provider.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Hive for local fabric catalog storage
  await Hive.initFlutter();

  // Force portrait orientation for a consistent premium experience
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Warm status bar — transparent with light icons
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D0A08),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const VastraApp());
}

class VastraApp extends StatelessWidget {
  const VastraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VastraProvider()),
        ChangeNotifierProvider(create: (_) => FabricCatalogProvider()),
      ],
      child: MaterialApp(
        title: 'Vastra – AI Fabric Visualizer',
        debugShowCheckedModeBanner: false,
        theme: VastraTheme.dark,
        home: const SplashScreen(),
      ),
    );
  }
}
