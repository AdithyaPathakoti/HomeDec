import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'providers/vastra_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation for a consistent premium experience
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent status bar with white icons
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF080808),
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
      ],
      child: MaterialApp(
        title: 'Vastra – AI Fabric Visualizer',
        debugShowCheckedModeBanner: false,
        theme: VastraTheme.dark,
        home: const HomeScreen(),
      ),
    );
  }
}
