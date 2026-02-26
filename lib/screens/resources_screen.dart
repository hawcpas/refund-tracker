import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

class ResourcesScreen extends StatelessWidget {
  const ResourcesScreen({super.key});

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const double contentWidth = 740;
    const double rowIndent = 20;

    final sections = <_ResourceSection>[
      _ResourceSection(
        title: 'Firm Tools',
        description: 'Core firm platforms and communications.',
        items: const [
          _ResourceLink(
            title: 'Axume & Associates Website',
            subtitle: 'Company homepage',
            url: 'https://www.axumecpas.com/',
            icon: Icons.public,
          ),
          _ResourceLink(
            title: 'Wildix',
            subtitle: 'Phone system / communications portal',
            url: 'https://farmlaborpayroll.wildixin.com/authorization/',
            icon: Icons.phone_in_talk_outlined,
          ),
        ],
      ),
      _ResourceSection(
        title: 'Client Portals',
        description: 'Secure portals for exchanging client documents.',
        items: const [
          _ResourceLink(
            title: 'ShareFile',
            subtitle: 'Secure file exchange',
            url:
                'https://auth.sharefile.io/axumecpas/login?returnUrl=%2fconnect%2fauthorize%2fcallback%3fclient_id%3dDzi4UPUAg5l8beKdioecdcnmHUTWWln6%26state%3doPhvHV46Gj6A7JJhyll3ww--%26acr_values%3dtenant%253Aaxumecpas%26response_type%3dcode%26redirect_uri%3dhttps%253A%252F%252Faxumecpas.sharefile.com%252Flogin%252Foauthlogin%26scope%3dsharefile%253Arestapi%253Av3%2520sharefile%253Arestapi%253Av3-internal%2520offline_access%2520openid',
            icon: Icons.folder_open_outlined,
          ),
          _ResourceLink(
            title: 'SecureSend',
            subtitle: 'Client portal login',
            url: 'https://www.securefirmportal.com/Account/Login/119710',
            icon: Icons.lock_outline,
          ),
        ],
      ),
      _ResourceSection(
        title: 'Security',
        description:
            'Tools to safely inspect suspicious links and verify email risk.',
        items: const [
          _ResourceLink(
            title: 'Email Verifier (IPQualityScore)',
            subtitle: 'Check email validity and potential risk signals',
            url: 'https://www.ipqualityscore.com/free-email-verifier',
            icon: Icons.mark_email_read_outlined,
          ),
        ],
      ),
      _ResourceSection(
        title: 'Research & Intelligence',
        description: 'Tools for research and guided workflows.',
        items: const [
          _ResourceLink(
            title: 'CoCounsel (Thomson Reuters)',
            subtitle: 'AI-assisted accounting research and workflows',
            url:
                'https://accounting.cocounsel.thomsonreuters.com/login?callbackUrl=https%3A%2F%2Faccounting.cocounsel.thomsonreuters.com%2F',
            icon: Icons.psychology_outlined,
          ),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      appBar: AppBar(title: const Text('Sites & Resources')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            children: [
              // ---------- WHITE CONTENT SURFACE ----------
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: contentWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.black.withOpacity(0.05),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Firm Resources',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF101828),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Curated tools and portals available to all signed-in users.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF475467),
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ---------- SECTIONS ----------
                        ...sections.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionHeader(
                                  title: s.title,
                                  description: s.description,
                                ),
                                const SizedBox(height: 6),

                                Padding(
                                  padding: EdgeInsets.only(left: rowIndent),
                                  child: Column(
                                    children: [
                                      for (int i = 0;
                                          i < s.items.length;
                                          i++) ...[
                                        _ResourceRow(
                                          icon: s.items[i].icon,
                                          title: s.items[i].title,
                                          subtitle: s.items[i].subtitle,
                                          onTap: () => _openLink(
                                            context,
                                            s.items[i].url,
                                          ),
                                        ),
                                        if (i != s.items.length - 1)
                                          Divider(
                                            height: 1,
                                            color:
                                                Colors.black.withOpacity(0.06),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),
                        Text(
                          'Links open in your default browser.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.lightGrey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceSection {
  final String title;
  final String description;
  final List<_ResourceLink> items;
  const _ResourceSection({
    required this.title,
    required this.description,
    required this.items,
  });
}

class _ResourceLink {
  final String title;
  final String subtitle;
  final String url;
  final IconData icon;
  const _ResourceLink({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.icon,
  });
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String description;

  const _SectionHeader({
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.brandBlue.withOpacity(0.04),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF101828),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF475467),
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceRow extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ResourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_ResourceRow> createState() => _ResourceRowState();
}

class _ResourceRowState extends State<_ResourceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: Colors.black.withOpacity(0.03),
        splashColor: Colors.black.withOpacity(0.02),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: AppColors.brandBlue.withOpacity(0.85),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandBlue,
                        height: 1.05,
                        decoration: _hovered
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        decorationThickness: 1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new,
                size: 16,
                color: AppColors.brandBlue.withOpacity(
                  _hovered ? 0.75 : 0.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}