import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TimelinePage extends StatefulWidget {
  final String projectName;
  final String projectStatus;
  final String startedText;

  const TimelinePage({
    super.key,
    required this.projectName,
    required this.projectStatus,
    required this.startedText,
  });

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  String? _projectId;
  String _projectName = '';
  String _projectStatus = '';
  String _startedText = '';
  bool _loading = true;

  static const List<Map<String, dynamic>> _defaultPhases = [
    {
      'id': 'site_preparation',
      'order': 1,
      'title': 'Site Preparation',
      'dateRange': 'Nov 1 - 10',
      'percentage': 0,
      'tasksCompleted': 0,
      'totalTasks': 3,
      'imageCount': 0,
      'status': 'Not Started',
    },
    {
      'id': 'foundation_work',
      'order': 2,
      'title': 'Foundation Work',
      'dateRange': 'Nov 11 - 30',
      'percentage': 0,
      'tasksCompleted': 0,
      'totalTasks': 4,
      'imageCount': 0,
      'status': 'Not Started',
    },
    {
      'id': 'structural_work',
      'order': 3,
      'title': 'Structural Work',
      'dateRange': 'Nov 30 - Dec 30',
      'percentage': 0,
      'tasksCompleted': 0,
      'totalTasks': 5,
      'imageCount': 0,
      'status': 'Not Started',
    },
  ];

  @override
  void initState() {
    super.initState();
    _projectName = widget.projectName;
    _projectStatus = widget.projectStatus;
    _startedText = widget.startedText;
    _loadProject();
  }

  Future<void> _loadProject() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final email = currentUser.email ?? '';
      final snap = await FirebaseFirestore.instance
          .collection('projects')
          .where('startedConstruction', isEqualTo: true)
          .get();

      if (!mounted) return;

      if (snap.docs.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      QueryDocumentSnapshot<Map<String, dynamic>>? latest;
      DateTime? latestDate;
      for (final doc in snap.docs) {
        final data = doc.data();
        final clientUid = (data['clientUid'] ?? '').toString();
        final clientEmail = (data['clientEmail'] ?? '').toString().toLowerCase();
        final matchesClient =
            clientUid == currentUser.uid || (email.isNotEmpty && clientEmail == email.toLowerCase());
        if (!matchesClient) {
          continue;
        }
        final d = _parseDate(data['timelineLastUpdatedAt'] ?? data['startedAt']) ?? DateTime(2000);
        if (latestDate == null || d.isAfter(latestDate)) {
          latestDate = d;
          latest = doc;
        }
      }

      if (latest == null) {
        setState(() => _loading = false);
        return;
      }

      final data = latest.data();
      final started = _parseDate(data['startedAt']);

      setState(() {
        _projectId = latest!.id;
        _projectName = (data['houseTitle'] ?? _projectName).toString();
        _projectStatus = (data['status'] ?? _projectStatus).toString();
        _startedText = started == null ? _startedText : _formatDate(started);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      if (value > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value > 1000000000) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Timeline'),
        backgroundColor: const Color(0xFF2537FF),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text(
                  'Project Timeline',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const Text(
                  'Construction schedules and milestones',
                  style: TextStyle(fontSize: 13, color: Color(0xFF5C6479)),
                ),
                const SizedBox(height: 10),
                _ProjectHeader(
                  projectName: _projectName,
                  startedText: _startedText,
                  statusText: _projectStatus,
                ),
                const SizedBox(height: 10),
                if (_projectId == null)
                  ..._defaultPhases.map((e) => _PhaseCard(data: e))
                else
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('projects')
                        .doc(_projectId)
                        .collection('timeline')
                        .orderBy('order')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return Column(
                          children: _defaultPhases
                              .map((e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _PhaseCard(data: e),
                                  ))
                              .toList(),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Column(
                          children: _defaultPhases
                              .map((e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _PhaseCard(data: e),
                                  ))
                              .toList(),
                        );
                      }

                      return Column(
                        children: docs
                            .map(
                              (d) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _PhaseCard(data: d.data()),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  final String projectName;
  final String startedText;
  final String statusText;

  const _ProjectHeader({
    required this.projectName,
    required this.startedText,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9DEE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(projectName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Started: $startedText', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text('Status: $statusText', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _PhaseCard extends StatefulWidget {
  final Map<String, dynamic> data;

  const _PhaseCard({required this.data});

  @override
  State<_PhaseCard> createState() => _PhaseCardState();
}

class _PhaseCardState extends State<_PhaseCard> {
  bool _showTasks = false;
  bool _showPhotos = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final title = (data['title'] ?? 'Phase').toString();
    final dateRange = (data['dateRange'] ?? '').toString();
    final status = (data['status'] ?? 'Active').toString();
    final percentage = ((data['percentage'] ?? 0) as num).toInt().clamp(0, 100);
    final tasks = _readTasks(data);
    final tasksCompleted = tasks.where((t) => t.done).length;
    final totalTasks = tasks.length;
    final photos = _readPhotos(data);
    final imageCount = photos.length;

    final bool isDone = status.toLowerCase() == 'done';
    final Color accent = isDone ? const Color(0xFF56BD62) : const Color(0xFF2D75F3);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9DEE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isDone ? const Color(0xFFD9F1DC) : const Color(0xFFDCE7FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: isDone ? const Color(0xFF2F8B3A) : const Color(0xFF2E62B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (dateRange.isNotEmpty) Text(dateRange, style: const TextStyle(color: Color(0xFF5B6378))),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: percentage / 100,
                      strokeWidth: 6,
                      backgroundColor: const Color(0xFFE7EAF2),
                      color: accent,
                    ),
                    Center(
                      child: Text(
                        '$percentage%',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Progress', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: percentage / 100,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE4E8F1),
                      color: const Color(0xFF27304A),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 15, color: Color(0xFF4D566D)),
                        const SizedBox(width: 6),
                        Text(
                          '$tasksCompleted of $totalTasks tasks completed',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const Spacer(),
                        const Icon(Icons.camera_alt_outlined, size: 15, color: Color(0xFF4D566D)),
                        const SizedBox(width: 4),
                        Text('$imageCount images', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _showTasks = !_showTasks),
                icon: Icon(_showTasks ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                label: const Text('Tasks'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => setState(() => _showPhotos = !_showPhotos),
                icon: Icon(_showPhotos ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                label: const Text('Photos'),
              ),
            ],
          ),
          if (_showTasks) ...[
            const SizedBox(height: 6),
            if (tasks.isEmpty)
              const Text('No task details available', style: TextStyle(fontSize: 12, color: Colors.black54))
            else
              ...tasks.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        entry.value.done ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 18,
                        color: entry.value.done ? const Color(0xFF2F8B3A) : const Color(0xFF6A738A),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value.name,
                          style: TextStyle(
                            fontSize: 13,
                            decoration: entry.value.done ? TextDecoration.lineThrough : TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (_showPhotos) ...[
            const SizedBox(height: 6),
            if (photos.isEmpty)
              const Text('No photos available', style: TextStyle(fontSize: 12, color: Colors.black54))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: photos
                    .map(
                      (p) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _looksLikeUrl(p)
                            ? Image.network(
                                p,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _photoFallback(p),
                              )
                            : _photoFallback(p),
                      ),
                    )
                    .toList(),
              ),
          ],
        ],
      ),
    );
  }

  List<_TimelineTask> _readTasks(Map<String, dynamic> data) {
    final raw = data['tasks'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map(
            (e) => _TimelineTask(
              name: (e['name'] ?? 'Task').toString(),
              done: e['done'] == true,
            ),
          )
          .toList();
    }

    final total = ((data['totalTasks'] ?? 0) as num).toInt();
    final done = ((data['tasksCompleted'] ?? 0) as num).toInt();
    return List.generate(
      total.clamp(0, 100),
      (i) => _TimelineTask(name: 'Task ${i + 1}', done: i < done),
    );
  }

  List<String> _readPhotos(Map<String, dynamic> data) {
    final raw = data['imageUrls'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    final count = ((data['imageCount'] ?? 0) as num).toInt();
    return List.generate(count.clamp(0, 100), (i) => 'Image ${i + 1}');
  }

  bool _looksLikeUrl(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  Widget _photoFallback(String label) {
    return Container(
      width: 72,
      height: 72,
      color: const Color(0xFFE7EAF2),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: Color(0xFF5B6378)),
    );
  }
}

class _TimelineTask {
  final String name;
  final bool done;

  _TimelineTask({required this.name, required this.done});
}
