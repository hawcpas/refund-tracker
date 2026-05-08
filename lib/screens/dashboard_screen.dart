import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import '../theme/app_colors.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/content_text_zoom.dart';
import '../shell/app_shell.dart';
import '../theme/app_theme.dart';
import '../utils/file_kind.dart';

String? _extractIndexUrl(String message) {
  final m = RegExp(r'https?://\S+').firstMatch(message);
  if (m == null) return null;

  // Firestore messages sometimes end URL with a trailing ')' or '.'
  var url = m.group(0) ?? '';
  url = url.replaceAll(RegExp(r'[)\],.]+$'), '');
  return url;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardActionCard extends StatelessWidget {
  const _DashboardActionCard({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context).extension<AppTheme>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 220), // ✅ taller card
      decoration: BoxDecoration(
        color: appTheme.contentBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Blue top accent line (Microsoft style)
          Container(
            height: 3,
            decoration: const BoxDecoration(
              color: AppColors.brandBlue,
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ Recommended label (no icon)
                const Text(
                  'Recommended',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandBlue,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF374151),
                  ),
                ),

                const SizedBox(height: 20),

                // ✅ Button anchored bottom-left
                SizedBox(
                  height: 34,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: onPressed,
                    child: Text(buttonLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticSurface extends StatelessWidget {
  const _StaticSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context).extension<AppTheme>()!;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: appTheme.contentBackground,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.black.withOpacity(0.12), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(children: children),
      ),
    );
  }
}

/// ============================
/// FILE TYPE META (MATCHES File Box)
/// ============================

class _RecentUploadsFromActivity extends StatelessWidget {
  const _RecentUploadsFromActivity({required this.isAdmin});

  final bool isAdmin;

  static const int _maxRecentRows = 6;
  static const double _recentRowHeight = 56.0;
  static const double _recentMaxHeight = _maxRecentRows * _recentRowHeight;

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream(String uid) {
    return FirebaseFirestore.instance
        .collectionGroup('files')
        .where('deleted', isEqualTo: false) // ✅ never show deleted
        .where(
          'requestCreatedByUid',
          isEqualTo: uid,
        ) // ✅ only files from MY requests
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  DateTime? _asDate(dynamic ts) => ts is Timestamp ? ts.toDate() : null;

  String _relativeTime(DateTime? dt) {
    if (dt == null) return 'Just now';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream(uid),
      builder: (context, snap) {
        if (snap.hasError) {
          final errText = snap.error.toString();
          final url = _extractIndexUrl(errText);
          final projectId = Firebase.app().options.projectId;

          return _DashboardListSection(
            title: 'Recent files',
            subtitle: 'Only files currently visible in File Box.',
            children: [
              _DashboardListRow(
                leadingIcon: Icons.warning_amber_outlined,
                title: 'Failed to load recent files',
                subtitle: url != null
                    ? 'Index required • project: $projectId (tap to copy)'
                    : 'Unexpected error (tap to copy)',
                onTap: () async {
                  final toCopy = url ?? errText;
                  await Clipboard.setData(ClipboardData(text: toCopy));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Error copied to clipboard'),
                      ),
                    );
                  }
                },
              ),
            ],
          );
        }

        if (!snap.hasData) {
          return _DashboardListSection(
            title: 'Recent files',
            subtitle: 'Only files currently visible in File Box.',
            children: const [
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Loading…',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return _DashboardListSection(
            title: 'Recent files',
            subtitle: 'Only files currently visible in File Box.',
            children: [
              _DashboardListRow(
                leadingIcon: Icons.inbox_outlined,
                title: 'No recent files',
                subtitle: 'No active (non-deleted) files found.',
                onTap: () {},
                enabled: false,
              ),
            ],
          );
        }

        // Build rows from live file docs (same source as File Box)
        final rows = docs.map((d) {
          final m = d.data();

          final fileName = _s(m['originalName']).isEmpty
              ? 'Untitled'
              : _s(m['originalName']);
          final contentType = _s(m['contentType']);
          final meta = resolveFileMeta(
            fileName: fileName,
            contentType: contentType,
          );

          final requestId = _s(m['requestId']);
          final business = _s(m['requestBusinessName']);

          // uploadedBy: { type: "client", name: requestClientName }
          // set in finalizeDropoffUpload [2](https://axumecpa-my.sharepoint.com/personal/guillermo_axumecpas_com/Documents/Personal_Files/Other/Microsoft%20Related/Microsoft%20Copilot%20Chat%20Files/index.js)
          final uploadedBy = m['uploadedBy'];
          final clientName = (uploadedBy is Map) ? _s(uploadedBy['name']) : '';

          final createdAt = _asDate(m['createdAt']);
          final subtitleParts = <String>[
            if (clientName.isNotEmpty) 'From $clientName' else 'From Client',
            if (business.isNotEmpty) business,
            _relativeTime(createdAt),
          ];

          return Tooltip(
            message: meta.tooltip,
            child: _DashboardListRow(
              leadingIcon: meta.icon,
              iconColor: Colors.white,
              leadingColor: meta.color,
              title: fileName,
              subtitle: subtitleParts.join(' • '),
              onTap: () {
                final shell = context.findAncestorStateOfType<AppShellState>();
                if (shell != null && requestId.isNotEmpty) {
                  shell.openDropoffDetails(requestId);
                }
              },
            ),
          );
        }).toList();

        // ✅ Hard cap visual height with internal scroll
        return _DashboardListSection(
          title: 'Recent files',
          subtitle: 'Only files currently visible in File Box.',
          children: [
            SizedBox(
              height: _recentMaxHeight,
              child: Scrollbar(
                thumbVisibility: rows.length > _maxRecentRows,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: rows.length,
                  physics: rows.length > _maxRecentRows
                      ? const AlwaysScrollableScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.black.withOpacity(0.08)),
                  itemBuilder: (context, index) => rows[index],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardListSection extends StatelessWidget {
  const _DashboardListSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _StaticSurface(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Divider(height: 1, color: Colors.black.withOpacity(0.08)),
        ..._withDividers(children),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> kids) {
    final out = <Widget>[];
    for (int i = 0; i < kids.length; i++) {
      out.add(kids[i]);
      if (i != kids.length - 1) {
        out.add(Divider(height: 1, color: Colors.black.withOpacity(0.08)));
      }
    }
    return out;
  }
}

class _DashboardListRow extends StatelessWidget {
  const _DashboardListRow({
    required this.leadingIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.leadingColor = const Color(0xFFF1F5F9),
    this.iconColor = AppColors.brandBlue,
    this.trailing,
    this.enabled = true,
  });

  final IconData leadingIcon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  final Color leadingColor;
  final Color iconColor;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),

      // ✅ Match your chrome hover language (same as AppShell IconButtons)
      overlayColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (states.contains(MaterialState.pressed)) {
          return const Color(0xFFE2E8F0); // slightly stronger pressed
        }
        if (states.contains(MaterialState.hovered)) {
          return const Color(0xFFF1F5F9); // matches your command/icon hover
        }
        return null;
      }),

      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            _LeadingIconTile(
              icon: leadingIcon,
              color: leadingColor,
              iconColor: enabled ? iconColor : const Color(0xFFB0B7C3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? const Color(0xFF111827)
                          : const Color(0xFF98A2B3),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? const Color(0xFF6B7280)
                          : const Color(0xFFB0B7C3),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: enabled
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFFD1D5DB),
                ),
          ],
        ),
      ),
    );
  }
}

class _LeadingIconTile extends StatelessWidget {
  const _LeadingIconTile({
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: iconColor),
    );
  }
}

class _PrimaryActionsPanel extends StatelessWidget {
  const _PrimaryActionsPanel({required this.children, this.header});

  final String? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _SurfaceTable(
      children: [
        if (header != null && header!.trim().isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              header!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF374151),
                letterSpacing: 0.2,
              ),
            ),
          ),
          Divider(height: 1, color: Colors.black.withOpacity(0.08)),
        ],
        ..._withDividers(children),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> kids) {
    final out = <Widget>[];
    for (int i = 0; i < kids.length; i++) {
      out.add(kids[i]);
      if (i != kids.length - 1) {
        out.add(Divider(height: 1, color: Colors.black.withOpacity(0.08)));
      }
    }
    return out;
  }
}

class _PrimaryActionRow extends StatefulWidget {
  const _PrimaryActionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.meta,
    required this.buttonLabel,
    required this.onPressed,
    this.enabled = true,
    this.accentColor = AppColors.brandBlue,
  });

  final IconData icon;
  final String title;
  final String description;
  final String meta;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool enabled;
  final Color accentColor;

  @override
  State<_PrimaryActionRow> createState() => _PrimaryActionRowState();
}

class _PrimaryActionRowState extends State<_PrimaryActionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 620;

    final bg = !widget.enabled
        ? Colors.transparent
        : _hover
        ? const Color(0xFFF6F7F9)
        : Colors.transparent;

    final titleColor = widget.enabled
        ? const Color(0xFF111827)
        : const Color(0xFF98A2B3);
    final descColor = widget.enabled
        ? const Color(0xFF475467)
        : const Color(0xFFB0B7C3);
    final metaColor = widget.enabled
        ? const Color(0xFF667085)
        : const Color(0xFFB0B7C3);
    final iconColor = widget.enabled
        ? widget.accentColor
        : const Color(0xFFB0B7C3);

    final row = InkWell(
      onTap: widget.enabled
          ? widget.onPressed
          : null, // ✅ entire row acts like entry point
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        color: bg,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: isNarrow
            ? _buildNarrow(context, iconColor, titleColor, descColor, metaColor)
            : _buildWide(context, iconColor, titleColor, descColor, metaColor),
      ),
    );

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => setState(() => _hover = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hover = false) : null,
      child: row,
    );
  }

  Widget _buildWide(
    BuildContext context,
    Color iconColor,
    Color titleColor,
    Color descColor,
    Color metaColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(widget.icon, size: 22, color: iconColor),
        const SizedBox(width: 14),

        // Left: title + description
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.description,
                style: TextStyle(
                  fontSize: 12.8,
                  height: 1.35,
                  color: descColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 16),

        // Right: meta + CTA
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  widget.meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    color: metaColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 34,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.enabled
                        ? widget.accentColor
                        : const Color(0xFFE5E7EB),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: widget.enabled ? widget.onPressed : null,
                  child: Text(widget.buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow(
    BuildContext context,
    Color iconColor,
    Color titleColor,
    Color descColor,
    Color metaColor,
  ) {
    // Mobile / narrow: stack meta + full-width button
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: 22, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          widget.description,
          style: TextStyle(
            fontSize: 12.8,
            height: 1.35,
            color: descColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.meta,
          style: TextStyle(
            fontSize: 12.5,
            color: metaColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.enabled
                  ? widget.accentColor
                  : const Color(0xFFE5E7EB),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: widget.enabled ? widget.onPressed : null,
            child: Text(widget.buttonLabel),
          ),
        ),
      ],
    );
  }
}

class _DashboardIntroHeader extends StatelessWidget {
  const _DashboardIntroHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
            letterSpacing: -0.2,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loadingProfile = true;
  bool _hasDropoffAccess = false;

  String _fullName = '';
  String _role = '';
  String _wildixExt = '';
  String _clearflyNumber = '';

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().where((u) => u != null).first.then(
      (u) {
        if (!mounted) return;
        _loadProfile(u!);
      },
    );
  }

  Future<void> _loadProfile(User user) async {
    setState(() => _loadingProfile = true);

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data() ?? {};
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final display = (data['displayName'] ?? '').toString().trim();
    final name = ('$first $last').trim().isNotEmpty ? '$first $last' : display;

    final role = (data['role'] ?? '').toString().toLowerCase().trim();
    final hasDropoffs =
        role == 'admin' || (data['capabilities']?['dropoffs'] == true);

    final comms = Map<String, dynamic>.from(data['communications'] ?? {});
    final wildix = (comms['wildixExtension'] ?? '').toString().trim();
    final clearfly = (comms['clearflySmsNumber'] ?? '').toString().trim();

    if (!mounted) return;
    setState(() {
      _fullName = name;
      _role = role;
      _hasDropoffAccess = hasDropoffs;
      _wildixExt = wildix;
      _clearflyNumber = _formatUsPhone10(clearfly);
      _loadingProfile = false;
    });
  }

  String _formatUsPhone10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return input.trim();
    final t = digits.substring(digits.length - 10);
    return '${t.substring(0, 3)}-${t.substring(3, 6)}-${t.substring(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context).extension<AppTheme>()!;
    final theme = Theme.of(context);
    final isAdmin = !_loadingProfile && _role == 'admin';
    final welcomeText = _fullName.isNotEmpty
        ? 'Welcome, $_fullName'
        : 'Welcome';

    return PageScaffold(
      title: '',
      hideHeader: true,
      wrapInCard: false,

      // ✅ Welcome text ABOVE command bar (new slot)
      preCommandBar: _DashboardIntroHeader(
        title: welcomeText, // "Welcome, Guillermo"
        // subtitle: 'Here’s what you can do today',
      ),

      commandBar: FluentCommandBar(
        actions: [
          // File Box
          FluentCommandAction(
            icon: Icons.folder_open_outlined,
            label: 'File Box',
            onPressed: _hasDropoffAccess
                ? () => Navigator.pushNamed(context, '/file-box')
                : null,
            accent: false,
          ),

          // Upload links
          FluentCommandAction(
            icon: Icons.link_outlined,
            label: 'Requests',
            onPressed: _hasDropoffAccess
                ? () => Navigator.pushNamed(context, '/generate-upload-link')
                : null,
            accent: false,
          ),

          // Admin (admins only)
          if (isAdmin)
            FluentCommandAction(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Admin',
              onPressed: () {
                final shell = context.findAncestorStateOfType<AppShellState>();
                shell?.openAdmin();
              },
              accent: false, // ✅ neutral black
            ),
        ],
        overflowActions: const [],
      ),

      child: ContentTextZoom(
        scale: 1.1, // ✅ TEST HERE (try 1.05–1.12)

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RecentUploadsFromActivity(isAdmin: isAdmin),

            if (!_hasDropoffAccess)
              _SurfaceTable(
                children: const [
                  _InfoRow(
                    text:
                        'You do not currently have access to Files or Request links. '
                        'Please contact an administrator if this is unexpected.',
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// ============================
/// Office 365 style components
/// ============================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: const Color(0xFF374151),
        letterSpacing: 0.2,
      ),
    );
  }
}

class _SurfaceTable extends StatefulWidget {
  const _SurfaceTable({required this.children, this.enableHover = true});

  final List<Widget> children;
  final bool enableHover;

  @override
  State<_SurfaceTable> createState() => _SurfaceTableState();
}

class _SurfaceTableState extends State<_SurfaceTable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context).extension<AppTheme>()!;

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: widget.enableHover && _hover
            ? const Color(0xFFF0F0F0)
            : appTheme.contentBackground,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: widget.enableHover && _hover
              ? Colors.black.withOpacity(0.28)
              : Colors.black.withOpacity(0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.enableHover && _hover
                ? const Color(0x33000000)
                : const Color(0x1A000000),
            blurRadius: widget.enableHover && _hover ? 8 : 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(children: widget.children),
    );

    if (!widget.enableHover) {
      return child; // ✅ no MouseRegion at all
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: child,
    );
  }
}

class _RowItem extends StatelessWidget {
  const _RowItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.brandBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6B7280),
          height: 1.4,
        ),
      ),
    );
  }
}
