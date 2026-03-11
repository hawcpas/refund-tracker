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
import 'screens/admin_dropoff_screen.dart';
import 'screens/auth_action_screen.dart';

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

        // ✅ ✅ ✅ HARD SHORT-CIRCUIT DROP-OFF ROUTES
        // Must come FIRST and must use startsWith
        if (route.startsWith('/dropoff')) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => route == '/dropoff/success'
                ? const DropoffSuccessScreen()
                : const DropoffClientScreen(),
          );
        }

        // ✅ ✅ ✅ HARD SHORT-CIRCUIT AUTH ACTION ROUTES
        // Password reset & email verification from email links
        if (route.startsWith('/auth/action')) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const AuthActionScreen(),
          );
        }

        // ✅ Public auth routes
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

        // ✅ Everything below REQUIRES auth
        final user = FirebaseAuth.instance.currentUser;

        if (user == null) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }

        if (!user.emailVerified) {
          return MaterialPageRoute(builder: (_) => const VerifyEmailScreen());
        }

        return MaterialPageRoute(
          settings: settings,
          builder: (_) {
            switch (route) {
              case '/dashboard':
                return const DashboardScreen();

              case '/account-settings':
                return const AccountSettingsScreen();

              case '/resources':
                return const ResourcesScreen();

              case '/shared-files':
                return const SharedFilesScreen();

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
                    final role = (data['role'] ?? '')
                        .toString()
                        .toLowerCase()
                        .trim();

                    final canManageDropoffs =
                        role == 'admin' ||
                        (data['capabilities']?['dropoffs'] == true);

                    // ❌ Only admins can access admin USERS screen
                    if (role != 'admin') return const DashboardScreen();
                    return const AdminUsersScreen();
                  },
                );

              case '/admin-dropoffs':
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
                    final role = (data['role'] ?? '')
                        .toString()
                        .toLowerCase()
                        .trim();

                    final hasDropoffAccess =
                        role == 'admin' ||
                        (data['capabilities']?['dropoffs'] == true);

                    // ❌ No access → back to dashboard
                    if (!hasDropoffAccess) {
                      return const DashboardScreen();
                    }

                    // ✅ Admins + Associates both land here
                    return const AdminDropoffsScreen();
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
