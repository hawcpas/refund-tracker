import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/page_scaffold.dart';

enum _AuditRange { today, sevenDays, thirtyDays, custom, all }

class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _actionFilter = 'all';
  String _actorFilter = 'all';
  String _fileFilter = 'all';
  _AuditRange _range = _AuditRange.sevenDays;
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _queryRef() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'file_activity',
    );

    final start = _rangeStart;
    if (start != null) {
      q = q.where(
        'occurredAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(start),
      );
    }

    final end = _rangeEnd;
    if (end != null) {
      q = q.where('occurredAt', isLessThan: Timestamp.fromDate(end));
    }

    return q.orderBy('occurredAt', descending: true).limit(300);
  }

  DateTime? get _rangeStart {
    final now = DateTime.now();
    switch (_range) {
      case _AuditRange.today:
        return DateTime(now.year, now.month, now.day);
      case _AuditRange.sevenDays:
        return now.subtract(const Duration(days: 7));
      case _AuditRange.thirtyDays:
        return now.subtract(const Duration(days: 30));
      case _AuditRange.custom:
        final start = _customStart;
        return start == null
            ? null
            : DateTime(start.year, start.month, start.day);
      case _AuditRange.all:
        return null;
    }
  }

  DateTime? get _rangeEnd {
    if (_range != _AuditRange.custom) return null;
    final end = _customEnd;
    if (end == null) return null;
    return DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
  }

  bool _matches(_AuditEvent e) {
    if (_actionFilter != 'all' && e.action != _actionFilter) return false;
    if (_actorFilter != 'all' && e.actorKey != _actorFilter) return false;
    if (_fileFilter != 'all' && e.fileKey != _fileFilter) return false;
    if (_query.isEmpty) return true;
    return e.searchText.contains(_query);
  }

  Future<void> _pickCustomDate({required bool start}) async {
    final now = DateTime.now();
    final initial = start
        ? (_customStart ?? now)
        : (_customEnd ?? _customStart ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      _range = _AuditRange.custom;
      if (start) {
        _customStart = picked;
        if (_customEnd != null && _customEnd!.isBefore(picked)) {
          _customEnd = picked;
        }
      } else {
        _customEnd = picked;
        if (_customStart != null && _customStart!.isAfter(picked)) {
          _customStart = picked;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Audit Log',
      subtitle: 'Review file activity by person, file, action, and time period.',
      wrapInCard: false,
      maxContentWidth: 1280,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _queryRef().snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _AuditEmpty(
              icon: Icons.error_outline,
              title: 'Audit log unavailable',
              message: snap.error.toString(),
            );
          }

          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final events = snap.data!.docs
              .map((d) => _AuditEvent.fromDoc(d))
              .where(_matches)
              .toList();
          final allEvents = snap.data!.docs.map((d) => _AuditEvent.fromDoc(d));
          final actorOptions = _actorOptions(allEvents);
          final fileOptions = _fileOptions(
            snap.data!.docs.map((d) => _AuditEvent.fromDoc(d)),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AuditFilters(
                searchCtrl: _searchCtrl,
                actionFilter: _actionFilter,
                actorFilter: _actorFilter,
                fileFilter: _fileFilter,
                range: _range,
                customStart: _customStart,
                customEnd: _customEnd,
                actorOptions: actorOptions,
                fileOptions: fileOptions,
                onActionChanged: (v) => setState(() => _actionFilter = v),
                onActorChanged: (v) => setState(() => _actorFilter = v),
                onFileChanged: (v) => setState(() => _fileFilter = v),
                onRangeChanged: (v) => setState(() => _range = v),
                onPickStart: () => _pickCustomDate(start: true),
                onPickEnd: () => _pickCustomDate(start: false),
              ),
              const SizedBox(height: 12),
              _AuditSummary(events: events),
              const SizedBox(height: 12),
              if (events.isEmpty)
                const _AuditEmpty(
                  icon: Icons.manage_search_outlined,
                  title: 'No matching activity',
                  message: 'Try changing the date range or removing a filter.',
                )
              else
                _AuditTimeline(events: events),
            ],
          );
        },
      ),
    );
  }

  List<_AuditActorOption> _actorOptions(Iterable<_AuditEvent> events) {
    final map = <String, _AuditActorOption>{};
    for (final e in events) {
      if (e.actorKey.isEmpty || e.actorKey == '-') continue;
      map[e.actorKey] = _AuditActorOption(e.actorKey, e.actorLabel);
    }
    final values = map.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return values;
  }

  List<_AuditFileOption> _fileOptions(Iterable<_AuditEvent> events) {
    final map = <String, _AuditFileOption>{};
    for (final e in events) {
      if (e.fileKey.isEmpty || e.fileName.isEmpty) continue;
      map[e.fileKey] = _AuditFileOption(e.fileKey, e.fileName);
    }
    final values = map.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return values;
  }
}

class _AuditFilters extends StatelessWidget {
  const _AuditFilters({
    required this.searchCtrl,
    required this.actionFilter,
    required this.actorFilter,
    required this.fileFilter,
    required this.range,
    required this.customStart,
    required this.customEnd,
    required this.actorOptions,
    required this.fileOptions,
    required this.onActionChanged,
    required this.onActorChanged,
    required this.onFileChanged,
    required this.onRangeChanged,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final TextEditingController searchCtrl;
  final String actionFilter;
  final String actorFilter;
  final String fileFilter;
  final _AuditRange range;
  final DateTime? customStart;
  final DateTime? customEnd;
  final List<_AuditActorOption> actorOptions;
  final List<_AuditFileOption> fileOptions;
  final ValueChanged<String> onActionChanged;
  final ValueChanged<String> onActorChanged;
  final ValueChanged<String> onFileChanged;
  final ValueChanged<_AuditRange> onRangeChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 340,
            child: TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search file, person, client, email, or request',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          _AuditDropdown<String>(
            width: 180,
            value: actionFilter,
            icon: Icons.bolt_outlined,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All actions')),
              DropdownMenuItem(value: 'upload', child: Text('Uploaded')),
              DropdownMenuItem(value: 'sent', child: Text('Sent files')),
              DropdownMenuItem(value: 'view', child: Text('Viewed')),
              DropdownMenuItem(value: 'download', child: Text('Downloaded')),
              DropdownMenuItem(value: 'delete', child: Text('Deleted')),
              DropdownMenuItem(value: 'replaced', child: Text('Replaced')),
              DropdownMenuItem(value: 'denied', child: Text('Access denied')),
            ],
            onChanged: (v) => onActionChanged(v ?? 'all'),
          ),
          _AuditDropdown<String>(
            width: 220,
            value: actorOptions.any((a) => a.key == actorFilter)
                ? actorFilter
                : 'all',
            icon: Icons.person_search_outlined,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All people')),
              ...actorOptions.map(
                (a) => DropdownMenuItem(value: a.key, child: Text(a.label)),
              ),
            ],
            onChanged: (v) => onActorChanged(v ?? 'all'),
          ),
          _AuditDropdown<String>(
            width: 220,
            value: fileOptions.any((f) => f.key == fileFilter)
                ? fileFilter
                : 'all',
            icon: Icons.insert_drive_file_outlined,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All files')),
              ...fileOptions.map(
                (f) => DropdownMenuItem(value: f.key, child: Text(f.label)),
              ),
            ],
            onChanged: (v) => onFileChanged(v ?? 'all'),
          ),
          SegmentedButton<_AuditRange>(
            segments: const [
              ButtonSegment(value: _AuditRange.today, label: Text('Today')),
              ButtonSegment(value: _AuditRange.sevenDays, label: Text('7 days')),
              ButtonSegment(
                value: _AuditRange.thirtyDays,
                label: Text('30 days'),
              ),
              ButtonSegment(value: _AuditRange.custom, label: Text('Custom')),
              ButtonSegment(value: _AuditRange.all, label: Text('All')),
            ],
            selected: {range},
            onSelectionChanged: (v) => onRangeChanged(v.first),
            showSelectedIcon: false,
          ),
          if (range == _AuditRange.custom) ...[
            _DateButton(
              label: 'From',
              value: customStart,
              onPressed: onPickStart,
            ),
            _DateButton(label: 'To', value: customEnd, onPressed: onPickEnd),
          ],
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? label
        : '$label ${MaterialLocalizations.of(context).formatShortDate(value!)}';
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text(text),
    );
  }
}

class _AuditDropdown<T> extends StatelessWidget {
  const _AuditDropdown({
    required this.width,
    required this.value,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  final double width;
  final T value;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        value: value,
        isDense: true,
        icon: const Icon(Icons.expand_more, size: 18),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(icon, size: 18),
          border: const OutlineInputBorder(),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _AuditSummary extends StatelessWidget {
  const _AuditSummary({required this.events});

  final List<_AuditEvent> events;

  @override
  Widget build(BuildContext context) {
    int count(String action) => events.where((e) => e.action == action).length;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _AuditMetric(label: 'Events', value: events.length.toString()),
        _AuditMetric(label: 'Uploads', value: count('upload').toString()),
        _AuditMetric(label: 'Sent files', value: count('sent').toString()),
        _AuditMetric(label: 'Downloads', value: count('download').toString()),
        _AuditMetric(label: 'Deletes', value: count('delete').toString()),
      ],
    );
  }
}

class _AuditMetric extends StatelessWidget {
  const _AuditMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 154,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditTimeline extends StatelessWidget {
  const _AuditTimeline({required this.events});

  final List<_AuditEvent> events;

  @override
  Widget build(BuildContext context) {
    final items = _compactTimeline(events);
    final grouped = <String, List<_AuditTimelineItem>>{};
    for (final item in items) {
      grouped
          .putIfAbsent(_dayLabel(context, item.event.occurredAt), () => [])
          .add(item);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: grouped.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                color: const Color(0xFFFCFCFD),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    color: Color(0xFF344054),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              ...entry.value.map((item) => _AuditEventRow(item: item)),
            ],
          );
        }).toList(),
      ),
    );
  }

  List<_AuditTimelineItem> _compactTimeline(List<_AuditEvent> events) {
    final result = <_AuditTimelineItem>[];
    final viewGroups = <String, List<_AuditEvent>>{};

    for (final event in events) {
      if (event.action == 'view' && event.surface == 'sent_files') {
        viewGroups.putIfAbsent(event.linkKey, () => []).add(event);
      } else {
        result.add(_AuditTimelineItem(event: event));
      }
    }

    for (final group in viewGroups.values) {
      group.sort((a, b) {
        final aMs = a.occurredAt?.millisecondsSinceEpoch ?? 0;
        final bMs = b.occurredAt?.millisecondsSinceEpoch ?? 0;
        return bMs.compareTo(aMs);
      });
      result.add(_AuditTimelineItem(event: group.first, count: group.length));
    }

    result.sort((a, b) {
      final aMs = a.event.occurredAt?.millisecondsSinceEpoch ?? 0;
      final bMs = b.event.occurredAt?.millisecondsSinceEpoch ?? 0;
      return bMs.compareTo(aMs);
    });
    return result;
  }

  String _dayLabel(BuildContext context, DateTime? dt) {
    if (dt == null) return 'Unknown date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return MaterialLocalizations.of(context).formatFullDate(dt);
  }
}

class _AuditEventRow extends StatelessWidget {
  const _AuditEventRow({required this.item});

  final _AuditTimelineItem item;

  @override
  Widget build(BuildContext context) {
    final event = item.event;
    final time = event.occurredAt == null
        ? '-'
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(event.occurredAt!),
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE4E7EC))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: event.color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(event.icon, size: 18, color: event.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                if (item.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            time,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditEmpty extends StatelessWidget {
  const _AuditEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: const Color(0xFF98A2B3)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditActorOption {
  const _AuditActorOption(this.key, this.label);

  final String key;
  final String label;
}

class _AuditFileOption {
  const _AuditFileOption(this.key, this.label);

  final String key;
  final String label;
}

class _AuditTimelineItem {
  const _AuditTimelineItem({required this.event, this.count = 1});

  final _AuditEvent event;
  final int count;

  String get title {
    if (event.action == 'view' && event.surface == 'sent_files') {
      return '${event.clientLabel} opened the file link';
    }
    return event.title;
  }

  String get subtitle {
    final base = event.subtitle;
    if (event.action == 'view' && event.surface == 'sent_files') {
      final parts = <String>[
        'Latest open',
        if (count > 1) '$count open events in this view',
        if (event.recipientEmail.isNotEmpty) event.recipientEmail,
        if (event.shareId.isNotEmpty) 'Link ${event.shortShareId}',
      ];
      return parts.join(' - ');
    }
    return base;
  }
}

class _AuditEvent {
  const _AuditEvent({
    required this.id,
    required this.action,
    required this.shareId,
    required this.actorName,
    required this.actorEmail,
    required this.actorType,
    required this.fileName,
    required this.clientName,
    required this.clientEmail,
    required this.recipientEmail,
    required this.requestId,
    required this.fileId,
    required this.surface,
    required this.occurredAt,
  });

  final String id;
  final String action;
  final String shareId;
  final String actorName;
  final String actorEmail;
  final String actorType;
  final String fileName;
  final String clientName;
  final String clientEmail;
  final String recipientEmail;
  final String requestId;
  final String fileId;
  final String surface;
  final DateTime? occurredAt;

  factory _AuditEvent.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    String s(String key) => (data[key] ?? '').toString().trim();
    final ts = data['occurredAt'];
    return _AuditEvent(
      id: doc.id,
      action: _normalizeAction(s('action')),
      shareId: s('shareId'),
      actorName: s('actorName'),
      actorEmail: s('actorEmail'),
      actorType: s('actorType'),
      fileName: s('originalName'),
      clientName: s('requestClientName'),
      clientEmail: s('requestClientEmail'),
      recipientEmail: s('recipientEmail'),
      requestId: s('requestId'),
      fileId: s('fileId'),
      surface: s('surface'),
      occurredAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  static String _normalizeAction(String raw) {
    final action = raw.toLowerCase().trim();
    switch (action) {
      case 'file_sent':
      case 'secure_file_share_created':
      case 'secure_file_share_updated':
      case 'share':
        return 'sent';
      case 'file_downloaded':
        return 'download';
      case 'file_uploaded':
        return 'upload';
      case 'file_deleted':
        return 'delete';
      default:
        return action.isEmpty ? 'unknown' : action;
    }
  }

  String get actorLabel {
    if (actorName.isNotEmpty) return actorName;
    if (actorEmail.isNotEmpty) return actorEmail;
    if (actorType.isNotEmpty) return actorType;
    return '-';
  }

  String get actorKey {
    if (actorEmail.isNotEmpty) return actorEmail.toLowerCase();
    return actorLabel.toLowerCase();
  }

  String get fileKey {
    if (fileId.isNotEmpty) return fileId.toLowerCase();
    return fileName.toLowerCase();
  }

  String get linkKey {
    if (shareId.isNotEmpty) return 'share:$shareId';
    if (recipientEmail.isNotEmpty) return 'recipient:${recipientEmail.toLowerCase()}';
    if (clientEmail.isNotEmpty) return 'client:${clientEmail.toLowerCase()}';
    return 'file:$fileKey';
  }

  String get shortShareId {
    if (shareId.length <= 8) return shareId;
    return shareId.substring(0, 8);
  }

  String get clientLabel {
    final name = clientName.trim().isNotEmpty
        ? clientName.trim()
        : actorName.trim();
    final email = recipientEmail.trim().isNotEmpty
        ? recipientEmail.trim()
        : clientEmail.trim();
    if (name.isNotEmpty && email.isNotEmpty) return '$name ($email)';
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return 'Client';
  }

  String get title {
    final actor = actorLabel == '-' ? 'Someone' : actorLabel;
    final file = fileName.isEmpty ? 'a file' : fileName;
    final recipient = clientLabel == 'Client' ? '' : clientLabel;

    switch (action) {
      case 'upload':
        return '$actor uploaded $file';
      case 'sent':
        return recipient.isEmpty
            ? '$actor sent $file'
            : '$actor sent $file to $recipient';
      case 'view':
        return surface == 'sent_files'
            ? '$actor opened the file link'
            : '$actor viewed $file';
      case 'download':
        return '$actor downloaded $file';
      case 'delete':
        return '$actor deleted $file';
      case 'replaced':
        return '$actor replaced $file';
      case 'denied':
        return recipient.isEmpty
            ? 'Access was denied for $file'
            : 'Access was denied for $recipient';
      default:
        return '$actor recorded activity on $file';
    }
  }

  String get subtitle {
    final parts = <String>[
      _actionLabel,
      if (clientName.isNotEmpty) clientName,
      if (requestId.isNotEmpty) 'Request $requestId',
      if (surface.isNotEmpty) _surfaceLabel,
    ];
    return parts.join(' - ');
  }

  String get _actionLabel {
    switch (action) {
      case 'upload':
        return 'Received file';
      case 'sent':
        return 'Sent files';
      case 'view':
        return 'Viewed';
      case 'download':
        return 'Downloaded';
      case 'delete':
        return 'Deleted';
      case 'replaced':
        return 'Replaced';
      case 'denied':
        return 'Access denied';
      default:
        return action;
    }
  }

  String get _surfaceLabel {
    switch (surface) {
      case 'details':
        return 'File details';
      case 'history':
        return 'Activity history';
      case 'sent_files':
        return 'Sent files';
      case 'request_files':
        return 'Request files';
      default:
        return surface.replaceAll('_', ' ');
    }
  }

  IconData get icon {
    switch (action) {
      case 'upload':
        return Icons.file_upload_outlined;
      case 'sent':
        return Icons.send_outlined;
      case 'view':
        return Icons.visibility_outlined;
      case 'download':
        return Icons.download_outlined;
      case 'delete':
        return Icons.delete_outline;
      case 'replaced':
        return Icons.find_replace_outlined;
      case 'denied':
        return Icons.block_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  Color get color {
    switch (action) {
      case 'upload':
        return const Color(0xFF027A48);
      case 'sent':
        return AppColors.brandBlue;
      case 'download':
        return const Color(0xFF6941C6);
      case 'delete':
      case 'denied':
        return const Color(0xFFB42318);
      default:
        return const Color(0xFF475467);
    }
  }

  String get searchText {
    return [
      action,
      actorName,
      actorEmail,
      actorType,
      fileName,
      clientName,
      clientEmail,
      recipientEmail,
      shareId,
      requestId,
      fileId,
      surface,
    ].join(' ').toLowerCase();
  }
}
