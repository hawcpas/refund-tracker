import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/verify_email_screen.dart';


const kNavyBlue = Color(0xFF003C9D);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: kNavyBlue,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Refund Tracker',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,

        // ✅ BRAND‑HEAVY BUT MODERN APP BAR
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,

          // ✅ CRITICAL for Material 3 (prevents dull overlay)
          surfaceTintColor: Colors.transparent,
        ),

        // ✅ Consistent modern buttons
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),

        // ✅ Clean modern inputs everywhere
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),

      home: const LoginScreen(),

      routes: {
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/signup': (context) => const SignupScreen(),
        '/change-password': (context) => const ChangePasswordScreen(),
        '/verify-email': (context) => const VerifyEmailScreen(),
      },
    );
  }
}