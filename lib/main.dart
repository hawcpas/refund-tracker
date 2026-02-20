import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/forgot_password_screen.dart';

// ✅ SINGLE SOURCE OF TRUTH — BRAND + PAGE BACKGROUND
const kBrandBlue = Color(0xFF08449E);

// ✅ Auth / portal background (matches Login / Signup / Forgot)
const kPageBackground = Color(0xFFF6F7F9);

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

        // ✅ DEFAULT APP BACKGROUND
        // Auth screens rely on this
        scaffoldBackgroundColor: kPageBackground,

        // ✅ PROFESSIONAL APP BAR (Dashboard, Change Password, etc.)
        appBarTheme: const AppBarTheme(
          backgroundColor: kBrandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent, // critical for M3
        ),

        // ✅ CONSISTENT PRIMARY ACTIONS
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46), // ✅ matches auth screens
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // ✅ CLEAN, MODERN INPUTS (baseline)
        // Screens may override details locally if needed
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF4F7FF),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: kBrandBlue.withOpacity(0.16),
              width: 1,
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(
              color: kBrandBlue,
              width: 1.6,
            ),
          ),
        ),

        // ✅ ICON THEME (prefix icons inherit brand tone)
        iconTheme: const IconThemeData(
          color: kBrandBlue,
        ),

        // ✅ TEXT THEME TWEAKS (subtle, enterprise)
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontWeight: FontWeight.w900),
          titleMedium: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),

      // ✅ ENTRY POINT
      home: const LoginScreen(),

      // ✅ ROUTES
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