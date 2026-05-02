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
import 'screens/generate_upload_link.dart';
import 'screens/auth_action_screen.dart';
import 'screens/file_box.dart';
import 'screens/otp_verify_screen.dart';

import 'services/auth_service.dart';
import 'shell/app_shell.dart';
import 'services/post_login_route.dart';
import 'screens/terms_of_service_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/security_screen.dart';
import 'screens/legal_screen.dart';

import 'theme/app_theme.dart';

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

    TextTheme _fluentTextTheme(TextTheme base) {
      // Fluent 2 Web type ramp (mapped into Flutter TextTheme)
      // Source ramp includes: caption2 10/14, caption1 12/16, body1 14/20, body2 16/22,
      // subtitle1 20/26, title3 24/32, title2 28/36, title1 32/40. [1](https://fluent2.microsoft.design/typography)[2](https://fluentuipr.z22.web.core.windows.net/heads/master/public-docsite-v9/storybook/index.html?path=/docs/theme-typography--page)
      TextStyle s(
        TextStyle? t, {
        double? size,
        double? height,
        FontWeight? weight,
        double? letterSpacing,
      }) {
        return (t ?? const TextStyle()).copyWith(
          fontFamily: 'Segoe UI',
          fontFamilyFallback: const [
            'Segoe UI Variable',
            'Segoe UI Web',
            'Segoe UI',
            'Helvetica Neue',
            'Arial',
            'sans-serif',
          ],
          fontSize: size,
          height: height,
          fontWeight: weight,
          letterSpacing: letterSpacing,
        );
      }

      return base.copyWith(
        // Page titles / section titles (Fluent “Subtitle 1” ~ 20/26 semibold)
        titleLarge: s(
          base.titleLarge,
          size: 20,
          height: 26 / 20,
          weight: FontWeight.w600,
          letterSpacing: -0.1,
        ),

        // Card/section headers (Fluent “Body 2” or “Subtitle 2” vibes)
        titleMedium: s(
          base.titleMedium,
          size: 16,
          height: 22 / 16,
          weight: FontWeight.w600,
        ),

        // Standard body (Fluent “Body 1” 14/20)
        bodyMedium: s(
          base.bodyMedium,
          size: 14,
          height: 20 / 14,
          weight: FontWeight.w400,
        ),

        // Slightly smaller body / helper (Fluent “Caption 1” 12/16)
        bodySmall: s(
          base.bodySmall,
          size: 12,
          height: 16 / 12,
          weight: FontWeight.w400,
        ),

        // Labels (use 12 semibold like Fluent caption strong)
        labelLarge: s(
          base.labelLarge,
          size: 12,
          height: 16 / 12,
          weight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelMedium: s(
          base.labelMedium,
          size: 12,
          height: 16 / 12,
          weight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelSmall: s(
          base.labelSmall,
          size: 10,
          height: 14 / 10,
          weight: FontWeight.w600,
          letterSpacing: 0.2,
        ),

        // Smaller headline for admin-style pages (avoid giant marketing headers)
        headlineSmall: s(
          base.headlineSmall,
          size: 24,
          height: 32 / 24,
          weight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      );
    }

    return MaterialApp(
      title: 'Axume & Associates CPAs Portal',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      scaffoldMessengerKey: _messengerKey,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,

        // ✅ Office 365 page background
        scaffoldBackgroundColor: AppColors.pageCanvas,

        // ✅ REGISTER APP THEME (THIS IS THE KEY)
        extensions: const [
          AppTheme(
            pageBackground: AppColors.pageCanvas, // #F7F5F2
            contentBackground: AppColors.contentCanvas, // #FFFFFF
            navigationBackground: AppColors.navigationCanvas,
            divider: AppColors.divider,
          ),
        ],

        // ✅ Fluent / Microsoft typography ramp (KEEP — this is good)
        textTheme: ThemeData.light().textTheme.copyWith(
          titleLarge: const TextStyle(
            fontFamily: 'Segoe UI',
            fontFamilyFallback: [
              'Segoe UI Variable',
              'Segoe UI Web',
              'Segoe UI',
              'Helvetica Neue',
              'Arial',
              'sans-serif',
            ],
            fontSize: 20,
            height: 26 / 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: Color(0xFF111827),
          ),

          titleMedium: const TextStyle(
            fontFamily: 'Segoe UI',
            fontFamilyFallback: [
              'Segoe UI Variable',
              'Segoe UI Web',
              'Segoe UI',
              'Helvetica Neue',
              'Arial',
              'sans-serif',
            ],
            fontSize: 16,
            height: 22 / 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),

          bodyMedium: const TextStyle(
            fontFamily: 'Segoe UI',
            fontFamilyFallback: [
              'Segoe UI Variable',
              'Segoe UI Web',
              'Segoe UI',
              'Helvetica Neue',
              'Arial',
              'sans-serif',
            ],
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF323130), // ✅ Fluent neutral text
          ),

          bodySmall: const TextStyle(
            fontFamily: 'Segoe UI',
            fontFamilyFallback: [
              'Segoe UI Variable',
              'Segoe UI Web',
              'Segoe UI',
              'Helvetica Neue',
              'Arial',
              'sans-serif',
            ],
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w400,
            color: Color(0xFF605E5C), // ✅ Fluent secondary text
          ),

          labelLarge: const TextStyle(
            fontFamily: 'Segoe UI',
            fontFamilyFallback: [
              'Segoe UI Variable',
              'Segoe UI Web',
              'Segoe UI',
              'Helvetica Neue',
              'Arial',
              'sans-serif',
            ],
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: Color(0xFF323130),
          ),

          labelMedium: const TextStyle(
            fontFamily: 'Segoe UI',
            fontFamilyFallback: [
              'Segoe UI Variable',
              'Segoe UI Web',
              'Segoe UI',
              'Helvetica Neue',
              'Arial',
              'sans-serif',
            ],
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: Color(0xFF323130),
          ),

          labelSmall: const TextStyle(
            fontFamily: 'Segoe UI',
            fontFamilyFallback: [
              'Segoe UI Variable',
              'Segoe UI Web',
              'Segoe UI',
              'Helvetica Neue',
              'Arial',
              'sans-serif',
            ],
            fontSize: 10,
            height: 14 / 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: Color(0xFF605E5C),
          ),

          headlineSmall: const TextStyle(
            fontFamily: 'Segoe UI',
            fontFamilyFallback: [
              'Segoe UI Variable',
              'Segoe UI Web',
              'Segoe UI',
              'Helvetica Neue',
              'Arial',
              'sans-serif',
            ],
            fontSize: 24,
            height: 32 / 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: Color(0xFF111827),
          ),
        ),

        // ✅ No page transitions (keep — enterprise correct)
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: NoTransitionsBuilder(),
            TargetPlatform.iOS: NoTransitionsBuilder(),
            TargetPlatform.linux: NoTransitionsBuilder(),
            TargetPlatform.macOS: NoTransitionsBuilder(),
            TargetPlatform.windows: NoTransitionsBuilder(),
          },
        ),

        // ✅ Neutral AppBar (Office365 does NOT use brand blue chrome)
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE9E9E9),
          foregroundColor: Color(0xFF323130),
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),
      ),

      // ✅ KEEP EVERYTHING BELOW EXACTLY THE SAME
      onGenerateRoute: (settings) {
        final raw = settings.name ?? '/';
        final uri = Uri.parse(raw);
        final route = uri.path; // ✅ path only (no query)
        final rid = uri.queryParameters['rid'];

        // ✅ ✅ ✅ HARD SHORT-CIRCUIT DROP-OFF ROUTES (public)
        if (route.startsWith('/dropoff') && route != '/file-box') {
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

        // ✅ Public routes (no auth, no shell)
        if (route == '/' ||
            route == '/login' ||
            route == '/forgot-password' ||
            route == '/verify-email' ||
            route == '/terms' ||
            route == '/privacy' ||
            route == '/legal' ||
            route == '/security') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) {
              switch (route) {
                case '/forgot-password':
                  return const ForgotPasswordScreen();
                case '/privacy':
                  return const PrivacyPolicyScreen();
                case '/terms':
                  return const TermsOfServiceScreen();
                case '/legal':
                  return const LegalScreen();
                case '/security':
                  return const SecurityScreen();
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

        // ✅ Protected routes — unchanged
        switch (route) {
          case '/dashboard':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                requestedRoute: route,
                builder: (_) => const AppShell(initialRoute: '/dashboard'),
              ),
            );

          case '/account-settings':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                requestedRoute: route,
                builder: (_) =>
                    const AppShell(initialRoute: '/account-settings'),
              ),
            );

          case '/resources':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                requestedRoute: route,
                builder: (_) => const AppShell(initialRoute: '/resources'),
              ),
            );

          case '/shared-files':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                requestedRoute: route,
                builder: (_) => const AppShell(initialRoute: '/shared-files'),
              ),
            );

          case '/admin-users':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                requestedRoute: route,
                builder: (user) =>
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .get(),
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (!snap.hasData) {
                          return const AppShell(initialRoute: '/dashboard');
                        }
                        final data = snap.data!.data() ?? {};
                        final role = (data['role'] ?? '')
                            .toString()
                            .toLowerCase()
                            .trim();
                        if (role != 'admin') {
                          return const AppShell(initialRoute: '/dashboard');
                        }
                        return const AppShell(initialRoute: '/admin-users');
                      },
                    ),
              ),
            );

          case '/file-box':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                requestedRoute: route,
                builder: (user) =>
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .get(),
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
                        if (!hasDropoffAccess) {
                          return const AppShell(initialRoute: '/dashboard');
                        }
                        return const AppShell(initialRoute: '/file-box');
                      },
                    ),
              ),
            );

          case '/generate-upload-link':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                requestedRoute: route,
                builder: (user) =>
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .get(),
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
                        if (!hasDropoffAccess) {
                          return const AppShell(initialRoute: '/dashboard');
                        }
                        return const AppShell(
                          initialRoute: '/generate-upload-link',
                        );
                      },
                    ),
              ),
            );

          default:
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AuthGate(
                requestedRoute: route,
                builder: (_) => const AppShell(initialRoute: '/dashboard'),
              ),
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
  final String requestedRoute;

  const _AuthGate({required this.builder, required this.requestedRoute});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;
        if (user == null) return const LoginScreen();
        if (!user.emailVerified) return const VerifyEmailScreen();

        return FutureBuilder<IdTokenResult>(
          // 🔐 Force refresh so OTP + timestamp claims are authoritative
          future: user.getIdTokenResult(true),
          builder: (context, tokenSnap) {
            if (tokenSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final claims = tokenSnap.data?.claims ?? {};

            final otpVerified = claims['otp_verified'] == true;

            final at = claims['otp_verified_at'];
            final atMs = (at is int) ? at : (at is num ? at.toInt() : 0);

            final nowMs = DateTime.now().millisecondsSinceEpoch;

            // ✅ OTP valid for 1 hour
            final otpFresh =
                otpVerified && atMs > 0 && (nowMs - atMs) <= (60 * 60 * 1000);

            // ✅ If someone deep-links to an admin route and OTP is expired,
            // force post-OTP navigation to a safe destination.
            final isProtected = requestedRoute.startsWith('/admin');
            final safeRoute = (isProtected && !otpFresh)
                ? '/dashboard'
                : requestedRoute;

            // ✅ HARD STOP: never render protected UI until OTP is fresh
            if (!otpFresh) {
              return OtpVerifyScreen(nextRoute: safeRoute);
            }

            // ✅ OTP verified and fresh → allow the requested screen
            return builder(user);
          },
        );
      },
    );
  }
}
