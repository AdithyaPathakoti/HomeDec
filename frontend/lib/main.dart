import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const VastraApp());
}

class VastraApp extends StatelessWidget {
  const VastraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vastra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.white,
        colorScheme: ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.grey,
        ),
        fontFamily: 'Inter', // Custom font can be added later
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
