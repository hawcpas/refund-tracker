import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/centered_form.dart';
import '../theme/app_colors.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // ✅ MATCH ChangePasswordScreen TOKENS
  static const double _pageVPad = 28;
  static const double _pageHPad = 18;
  static const double _cardRadius = 18;
  static const double _cardPad = 16;
  static const double _fieldGap = 12;
  static const double _blockGap = 16;
  static const double _buttonH = 46;

  static const double _logoSize = 80;
  static const double _accentH = 4;
  static const double _accentW = 72;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = "No signed-in user.";
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));

      final data = doc.data() ?? {};
      firstNameController.text = (data['firstName'] ?? '').toString();
      lastNameController.text = (data['lastName'] ?? '').toString();
    } on FirebaseException catch (e) {
      _error = "Could not load profile (${e.code}).";
    } catch (_) {
      _error = "Could not load profile.";
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final fn = firstNameController.text.trim();
    final ln = lastNameController.text.trim();

    if (fn.isEmpty || ln.isEmpty) {
      setState(() => _error = "First name and last name are required.");
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final displayName = ('$fn $ln').trim();

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'firstName': fn,
          'lastName': ln,
          'displayName': displayName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await user.updateDisplayName(displayName);

      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      setState(() => _error = "Could not save changes (${e.code}).");
    } catch (_) {
      setState(() => _error = "Could not save changes. Please try again.");
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      appBar: AppBar(title: const Text("Account Settings")),
      body: ColoredBox(
        color: AppColors.pageBackgroundLight,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            vertical: _pageVPad,
            horizontal: _pageHPad,
          ),
          children: [
            CenteredForm(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(_cardRadius),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(_cardPad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ✅ LOGO
                      const ImageIcon(
                        AssetImage(
                          'assets/icons/aa_logo_imageicon_256.png',
                        ),
                        size: _logoSize,
                        color: AppColors.brandBlue,
                      ),
                      const SizedBox(height: 14),

                      Container(
                        height: _accentH,
                        width: _accentW,
                        margin: const EdgeInsets.only(bottom: _blockGap),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),

                      Text(
                        "Account settings",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF101828),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Update your profile information.",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF475467),
                        ),
                      ),
                      const SizedBox(height: _blockGap),

                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.25),
                            ),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFB42318),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: _blockGap),
                      ],

                      if (_loading) ...[
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: _blockGap),
                      ] else ...[
                        TextField(
                          controller: firstNameController,
                          decoration: const InputDecoration(
                            labelText: "First name",
                            prefixIcon: Icon(
                              Icons.person_outline,
                              color: AppColors.brandBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: _fieldGap),
                        TextField(
                          controller: lastNameController,
                          decoration: const InputDecoration(
                            labelText: "Last name",
                            prefixIcon: Icon(
                              Icons.badge_outlined,
                              color: AppColors.brandBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: _blockGap),

                        SizedBox(
                          height: _buttonH,
                          child: _saving
                              ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                              : FilledButton.icon(
                                  onPressed: _save,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text("Save changes"),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.brandBlue,
                                    foregroundColor:
                                        AppColors.cardBackground,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}