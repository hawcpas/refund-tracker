import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:refund_tracker/theme/app_colors.dart';
import 'firebase_options.dart';

import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/account_settings_screen.dart';
import 'screens/admin_users_screen.dart';
import 'screens/resources_screen.dart';
import 'screens/shared_files_screen.dart';
import 'screens/dropoff/dropoff_client_screen.dart';
import 'screens/dropoff/dropoff_success_screen.dart';
import 'screens/view_dropoff_screen.dart';
import 'screens/auth_action_screen.dart';
import 'screens/dropoff_uploads_screen.dart';

import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ Enable clean, path-based URLs (no #)
  usePathUrlStrategy();

  runApp(const MyApp());
}

/// ✅ Global "no animation" transitions
class NoTransitionsBuilder extends PageTransitionsBuilder {
  const NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
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

    _authService.startSessionGuard(
      onForcedLogout: () {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'Your account has been disabled. Please contact an admin.',
            ),
          ),
        );

        // Always route to login on forced logout
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
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: NoTransitionsBuilder(),
            TargetPlatform.iOS: NoTransitionsBuilder(),
            TargetPlatform.linux: NoTransitionsBuilder(),
            TargetPlatform.macOS: NoTransitionsBuilder(),
            TargetPlatform.windows: NoTransitionsBuilder(),
          },
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.brandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),
      ),

      onGenerateRoute: (settings) {
        final route = settings.name ?? '/';

        // ✅ ✅ ✅ HARD SHORT-CIRCUIT DROP-OFF ROUTES (public)
        // ✅ ✅ ✅ HARD SHORT-CIRCUIT DROP-OFF ROUTES (public client-only)
        if (route.startsWith('/dropoff') && route != '/dropoff-uploads') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => route == '/dropoff/success'
                ? const DropoffSuccessScreen()
                : const DropoffClientScreen(),
          );
        }

        // ✅ ✅ ✅ HARD SHORT-CIRCUIT AUTH ACTION ROUTES (public)
        if (route.startsWith('/auth/action')) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const AuthActionScreen(),
          );
        }

        // ✅ Public auth routes (no gating)
        if (route == '/' ||
            route == '/login' ||
            route == '/forgot-password' ||
            route == '/verify-email') {
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

        // ✅ Protected routes: ONLY build them once auth is restored
        switch (route) {
          case '/dashboard':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  _AuthGate(builder: (_) => const DashboardScreen()),
            );

          case '/account-settings':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  _AuthGate(builder: (_) => const AccountSettingsScreen()),
            );

          case '/resources':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  _AuthGate(builder: (_) => const ResourcesScreen()),
            );

          case '/shared-files':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  _AuthGate(builder: (_) => const SharedFilesScreen()),
            );

          case '/admin-users':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                builder: (user) =>
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      // ✅ IMPORTANT: use the restored user.uid, NOT currentUser
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
                        final role = (data['role'] ?? '')
                            .toString()
                            .toLowerCase()
                            .trim();

                        // Only admins can access admin USERS screen
                        if (role != 'admin') return const DashboardScreen();
                        return const AdminUsersScreen();
                      },
                    ),
              ),
            );

          case '/dropoff-uploads':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                builder: (user) =>
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
                        final role = (data['role'] ?? '')
                            .toString()
                            .toLowerCase()
                            .trim();
                        final hasDropoffAccess =
                            role == 'admin' ||
                            (data['capabilities']?['dropoffs'] == true);

                        if (!hasDropoffAccess) return const DashboardScreen();
                        return const DropoffUploadsScreen();
                      },
                    ),
              ),
            );

          case '/view-dropoffs':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                builder: (user) =>
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      // ✅ IMPORTANT: use the restored user.uid, NOT currentUser
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
                        final role = (data['role'] ?? '')
                            .toString()
                            .toLowerCase()
                            .trim();

                        final hasDropoffAccess =
                            role == 'admin' ||
                            (data['capabilities']?['dropoffs'] == true);

                        // No access → back to dashboard
                        if (!hasDropoffAccess) return const DashboardScreen();

                        // Admins + Associates with capability land here
                        return const ViewDropoffsScreen();
                      },
                    ),
              ),
            );

          default:
            // Default protected landing
            return MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  _AuthGate(builder: (_) => const DashboardScreen()),
            );
        }
      },
    );
  }
}

/// ✅ AuthGate (builder form):
/// Prevents blank refresh by waiting for FirebaseAuth to restore session.
/// Firebase notes currentUser can be null until auth finishes initializing,
/// so authStateChanges() is the correct source of truth. [1](https://www.valimail.com/blog/understanding-email-authentication-headers/)[2](https://www.youtube.com/watch?v=S7LhAmuJGVA)
class _AuthGate extends StatelessWidget {
  final Widget Function(User user) builder;
  const _AuthGate({required this.builder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        // While Firebase restores session (especially on web refresh)
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;

        if (user == null) return const LoginScreen();
        if (!user.emailVerified) return const VerifyEmailScreen();

        // ✅ Only build protected UI AFTER user exists (prevents refresh blank)
        return builder(user);
      },
    );
  }
}
