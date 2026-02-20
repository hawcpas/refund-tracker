import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/forgot_password_screen.dart';

// ✅ SINGLE SOURCE OF TRUTH FOR BRAND COLOR
const kBrandBlue = Color(0xFF08449E);

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
      seedColor: kBrandBlue,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'A&A Portal',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,

        // ✅ Ensures white backgrounds stay white
        scaffoldBackgroundColor: Colors.white,

        // ✅ PROFESSIONAL, CONSISTENT APP BAR
        appBarTheme: AppBarTheme(
          backgroundColor: kBrandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,

          // ✅ CRITICAL for Material 3
          // Prevents gray / dull overlays
          surfaceTintColor: Colors.transparent,
        ),

        // ✅ Consistent modern primary buttons
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),

        // ✅ Clean modern inputs across the app
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF4F7FF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),

      home: const LoginScreen(),

      routes: {
        '/login': (_) => const LoginScreen(),
        '/dashboard': (_) => const DashboardScreen(),
        '/signup': (_) => const SignupScreen(),
        '/change-password': (_) => const ChangePasswordScreen(),
        '/verify-email': (_) => const VerifyEmailScreen(),
        '/forgot-password': (_) => const ForgotPasswordScreen(),
      },
    );
  }
}