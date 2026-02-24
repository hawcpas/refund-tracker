import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:refund_tracker/theme/app_colors.dart';
import 'firebase_options.dart';


import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/account_settings_screen.dart';
import 'screens/admin_users_screen.dart';

// ✅ add this import
import 'services/auth_service.dart';
import 'widgets/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _authService = AuthService();

  // ✅ Needed so we can navigate + show snackbar from anywhere
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();

    // ✅ Start guard once for the whole app
    _authService.startSessionGuard(
      onForcedLogout: () {
        // 1) show message
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'Your account has been disabled. Please contact an admin.',
            ),
          ),
        );

        // 2) go to login and clear stack
        _navKey.currentState?.pushNamedAndRemoveUntil('/login', (r) => false);
      },
    );
  }

  @override
  void dispose() {
    // ✅ Stop guard when app closes
    _authService.stopSessionGuard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandBlue,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Axume & Associates CPAs Portal',
      debugShowCheckedModeBanner: false,

      // ✅ keys so guard can redirect + snackbar
      navigatorKey: _navKey,
      scaffoldMessengerKey: _messengerKey,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,

        scaffoldBackgroundColor: AppColors.pageBackgroundLight,

        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.brandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

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
              color: AppColors.brandBlue.withOpacity(0.16),
              width: 1,
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: AppColors.brandBlue, width: 1.6),
          ),
        ),

        iconTheme: const IconThemeData(color: AppColors.brandBlue),

        textTheme: const TextTheme(
          titleLarge: TextStyle(fontWeight: FontWeight.w900),
          titleMedium: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),

      home: const LoginScreen(),

      routes: {
        '/login': (_) => const LoginScreen(),
        '/forgot-password': (_) => const ForgotPasswordScreen(),
        '/verify-email': (_) => const VerifyEmailScreen(),

        '/dashboard': (_) => const AuthGate(child: DashboardScreen()),

        '/account-settings': (_) =>
            const AuthGate(child: AccountSettingsScreen()),

        '/admin-users': (_) =>
            const AuthGate(requireAdmin: true, child: AdminUsersScreen()),
      },
    );
  }
}
