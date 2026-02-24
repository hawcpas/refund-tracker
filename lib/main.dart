import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:refund_tracker/theme/app_colors.dart';
import 'firebase_options.dart';

import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/account_settings_screen.dart';
import 'screens/admin_users_screen.dart';

import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _authService = AuthService();

  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();

    // ✅ Global session guard (disabled users)
    _authService.startSessionGuard(
      onForcedLogout: () {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'Your account has been disabled. Please contact an admin.',
            ),
          ),
        );
        _navKey.currentState?.pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
      },
    );
  }

  @override
  void dispose() {
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

      // ❌ NO `home:` — critical for Flutter Web deep links
      onGenerateRoute: (settings) {
        final user = FirebaseAuth.instance.currentUser;
        final route = settings.name ?? '/';

        bool isPublic(String r) =>
            r == '/' ||
            r == '/login' ||
            r == '/forgot-password' ||
            r == '/verify-email';

        // -------------------------
        // PUBLIC ROUTES
        // -------------------------
        if (isPublic(route)) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) {
              switch (route) {
                case '/forgot-password':
                  return const ForgotPasswordScreen();
                case '/verify-email':
                  return const VerifyEmailScreen();
                case '/':
                case '/login':
                default:
                  return const LoginScreen();
              }
            },
          );
        }

        // -------------------------
        // NOT SIGNED IN → LOGIN
        // -------------------------
        if (user == null) {
          return MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          );
        }

        // -------------------------
        // EMAIL NOT VERIFIED
        // -------------------------
        if (!user.emailVerified) {
          return MaterialPageRoute(
            builder: (_) => const VerifyEmailScreen(),
          );
        }

        // -------------------------
        // PROTECTED ROUTES
        // -------------------------
        return MaterialPageRoute(
          settings: settings,
          builder: (_) {
            switch (route) {
              case '/dashboard':
                return const DashboardScreen();

              case '/account-settings':
                return const AccountSettingsScreen();

              case '/admin-users':
                return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .get(const GetOptions(source: Source.server)),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final data = snap.data!.data() ?? {};
                    final role =
                        (data['role'] ?? '').toString().toLowerCase().trim();
                    final status =
                        (data['status'] ?? '').toString().toLowerCase().trim();
                    final disabled =
                        data['disabled'] == true ||
                        status == 'disabled' ||
                        status == 'inactive';

                    if (disabled) return const LoginScreen();
                    if (role != 'admin') return const DashboardScreen();

                    return const AdminUsersScreen();
                  },
                );

              default:
                return const DashboardScreen();
            }
          },
        );
      },
    );
  }
}