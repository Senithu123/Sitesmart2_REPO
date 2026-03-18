import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ContractorProjectUpdatePage extends StatefulWidget {
  final String projectId;
  final String houseTitle;

  const ContractorProjectUpdatePage({
    super.key,
    required this.projectId,
    required this.houseTitle,
  });

  @override
  State<ContractorProjectUpdatePage> createState() =>
      _ContractorProjectUpdatePageState();
}

class _ContractorProjectUpdatePageState extends State<ContractorProjectUpdatePage> {
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
      'tasks': [
        {'name': 'Clear land and debris', 'done': false},
        {'name': 'Set temporary utilities', 'done': false},
        {'name': 'Mark layout lines', 'done': false},
      ],
      'imageUrls': [],
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
      'tasks': [
        {'name': 'Excavate foundation trenches', 'done': false},
        {'name': 'Place steel reinforcement', 'done': false},
        {'name': 'Pour concrete footing', 'done': false},
        {'name': 'Cure concrete base', 'done': false},
      ],
      'imageUrls': [],
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
      'tasks': [
        {'name': 'Build ground-floor columns', 'done': false},
        {'name': 'Cast beam framework', 'done': false},
        {'name': 'Install slab shuttering', 'done': false},
        {'name': 'Pour slab concrete', 'done': false},
        {'name': 'Cure slab', 'done': false},
      ],
      'imageUrls': [],
      'status': 'Not Started',
    },
  ];
  bool _initializing = true;
  bool _canEdit = false;
  String? _accessMessage;

  @override
  void initState() {
    super.initState();
    _initializeAccess();
  }

  Future<void> _initializeAccess() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _canEdit = false;
        _accessMessage = 'Please log in again';
      });
      return;
    }

    try {
      final projectRef =
          FirebaseFirestore.instance.collection('projects').doc(widget.projectId);
      final projectSnap = await projectRef.get();
      final projectData = projectSnap.data() ?? <String, dynamic>{};
      var contractorUid = (projectData['contractorUid'] ?? '').toString();

      if (contractorUid.isEmpty) {
        try {
          await projectRef.set({
            'contractorUid': currentUser.uid,
          }, SetOptions(merge: true));
          contractorUid = currentUser.uid;
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied') rethrow;
        }
      }

      if (contractorUid == currentUser.uid) {
        await _ensureTimelineDocs();
        if (!mounted) return;
        setState(() {
          _initializing = false;
          _canEdit = true;
          _accessMessage = null;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _initializing = false;
        _canEdit = false;
        _accessMessage = 'This project is not assigned to your contractor account';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _canEdit = false;
        _accessMessage = 'Unable to verify edit access for this project';
      });
    }
  }

  Future<void> _ensureTimelineDocs() async {
    try {
      final timelineRef =
          FirebaseFirestore.instance.collection('projects').doc(widget.projectId).collection('timeline');

      final existing = await timelineRef.limit(1).get();
      if (existing.docs.isNotEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final phase in _defaultPhases) {
        final id = phase['id'].toString();
        batch.set(timelineRef.doc(id), {
          ...phase,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        });
      }
      batch.set(
        FirebaseFirestore.instance.collection('projects').doc(widget.projectId),
        {
          'timelineLastUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
  }

  Future<void> _updatePhase(
    String phaseId, {
    int? percentage,
    int? tasksCompleted,
    int? totalTasks,
    int? imageCount,
    String? status,
    List<Map<String, dynamic>>? tasks,
    List<String>? imageUrls,
  }) async {
    if (!_canEdit) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have permission to edit this project')),
      );
      return;
    }
    try {
      final payload = <String, dynamic>{
        if (percentage != null) 'percentage': percentage,
        if (tasksCompleted != null) 'tasksCompleted': tasksCompleted,
        if (totalTasks != null) 'totalTasks': totalTasks,
        if (imageCount != null) 'imageCount': imageCount,
        if (status != null) 'status': status,
        if (tasks != null) 'tasks': tasks,
        if (imageUrls != null) 'imageUrls': imageUrls,
      };
      if (payload.isEmpty) return;

      await FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .collection('timeline')
          .doc(phaseId)
          .set(payload, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Progress saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Update: ${widget.houseTitle}'),
        backgroundColor: const Color(0xFF2537FF),
        foregroundColor: Colors.white,
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : !_canEdit
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _accessMessage ?? 'No edit access',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('projects')
            .doc(widget.projectId)
            .collection('timeline')
            .orderBy('order')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Firestore error: ${snapshot.error}'));
          }

          final phases = snapshot.data?.docs ?? [];
          if (phases.isEmpty) {
            return const Center(child: Text('Timeline phases not initialized'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: phases.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = phases[index];
              final data = doc.data();
              return _PhaseEditorCard(
                data: data,
                onChanged: ({
                  int? percentage,
                  int? tasksCompleted,
                  int? totalTasks,
                  int? imageCount,
                  String? status,
                  List<Map<String, dynamic>>? tasks,
                  List<String>? imageUrls,
                }) {
                  _updatePhase(
                    doc.id,
                    percentage: percentage,
                    tasksCompleted: tasksCompleted,
                    totalTasks: totalTasks,
                    imageCount: imageCount,
                    status: status,
                    tasks: tasks,
                    imageUrls: imageUrls,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _PhaseEditorCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final void Function({
    int? percentage,
    int? tasksCompleted,
    int? totalTasks,
    int? imageCount,
    String? status,
    List<Map<String, dynamic>>? tasks,
    List<String>? imageUrls,
  }) onChanged;

  const _PhaseEditorCard({required this.data, required this.onChanged});

  @override
  State<_PhaseEditorCard> createState() => _PhaseEditorCardState();
}

class _PhaseEditorCardState extends State<_PhaseEditorCard> {
  static const List<String> _statusOptions = [
    'Not Started',
    'Pending',
    'Active',
    'Done',
  ];
  late int _pendingPercentage;
  bool _showTasks = false;
  bool _showImages = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _pendingPercentage = ((widget.data['percentage'] ?? 0) as num)
        .toInt()
        .clamp(0, 100);
  }

  @override
  void didUpdateWidget(covariant _PhaseEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final latest = ((widget.data['percentage'] ?? 0) as num).toInt().clamp(0, 100);
    if (latest != _pendingPercentage) {
      _pendingPercentage = latest;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final title = (data['title'] ?? 'Phase').toString();
    final dateRange = (data['dateRange'] ?? '').toString();
    final percentage = ((data['percentage'] ?? 0) as num).toInt().clamp(0, 100);
    final tasks = _readTasks(data);
    final tasksCompleted = tasks.where((t) => (t['done'] ?? false) == true).length;
    final totalTasks = tasks.length;
    final imageUrls = _readImageUrls(data);
    final imageCount = imageUrls.length;
    final rawStatus = (data['status'] ?? 'Not Started').toString();
    final status = _statusOptions.contains(rawStatus) ? rawStatus : 'Not Started';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8DDE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
                  child: DropdownButtonFormField<String>(
                    value: status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: _statusOptions
                        .map(
                          (option) => DropdownMenuItem<String>(
                            value: option,
                            child: Text(
                              option,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      widget.onChanged(status: value);
                    },
                  ),
                ),
              ),
            ],
          ),
          if (dateRange.isNotEmpty) Text(dateRange),
          const SizedBox(height: 10),
          Text('Progress: $_pendingPercentage%'),
          Slider(
            value: _pendingPercentage.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            label: '$_pendingPercentage%',
            onChanged: (value) {
              setState(() {
                _pendingPercentage = value.round();
              });
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () => widget.onChanged(percentage: _pendingPercentage),
              child: const Text('Save Progress'),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _showTasks = !_showTasks),
                  child: Row(
                    children: [
                      Text('Tasks: $tasksCompleted / $totalTasks'),
                      const SizedBox(width: 6),
                      Icon(
                        _showTasks ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  if (tasks.isEmpty) return;
                  final updated = List<Map<String, dynamic>>.from(tasks)..removeLast();
                  _saveTasks(updated);
                },
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                onPressed: () => _addTaskDialog(tasks),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (_showTasks) ...[
            const SizedBox(height: 4),
            if (tasks.isEmpty)
              const Text(
                'No tasks yet',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              )
            else
              ...tasks.asMap().entries.map(
                (entry) => Row(
                  children: [
                    Checkbox(
                      value: (entry.value['done'] ?? false) == true,
                      onChanged: (checked) {
                        final updated = List<Map<String, dynamic>>.from(tasks);
                        final row = Map<String, dynamic>.from(updated[entry.key]);
                        row['done'] = checked == true;
                        updated[entry.key] = row;
                        _saveTasks(updated);
                      },
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => _editTaskNameDialog(tasks, entry.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            (entry.value['name'] ?? 'Task').toString(),
                            style: TextStyle(
                              decoration: (entry.value['done'] ?? false) == true
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _editTaskNameDialog(tasks, entry.key),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () {
                        final updated = List<Map<String, dynamic>>.from(tasks)..removeAt(entry.key);
                        _saveTasks(updated);
                      },
                    ),
                  ],
                ),
              ),
          ],
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _showImages = !_showImages),
                  child: Row(
                    children: [
                      Text('Images: $imageCount'),
                      const SizedBox(width: 6),
                      Icon(
                        _showImages ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  if (imageUrls.isEmpty) return;
                  final updated = List<String>.from(imageUrls)..removeLast();
                  _saveImages(updated);
                },
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                onPressed: () => _showImageSourceSheet(imageUrls),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (_showImages) ...[
            const SizedBox(height: 4),
            if (imageUrls.isEmpty)
              const Text(
                'No images yet',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              )
            else
              ...imageUrls.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      _buildImageThumb(entry.value),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () {
                          final updated = List<String>.from(imageUrls)..removeAt(entry.key);
                          _saveImages(updated);
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (percentage != _pendingPercentage)
            const Text(
              'Pending changes not saved',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _readTasks(Map<String, dynamic> data) {
    final raw = data['tasks'];
    if (raw is List) {
      final parsed = raw
          .whereType<Map>()
          .map(
            (e) => {
              'name': (e['name'] ?? 'Task').toString(),
              'done': e['done'] == true,
            },
          )
          .toList();
      if (parsed.isNotEmpty) return parsed;
    }

    final total = ((data['totalTasks'] ?? 0) as num).toInt();
    final done = ((data['tasksCompleted'] ?? 0) as num).toInt();
    if (total <= 0) return <Map<String, dynamic>>[];
    return List.generate(
      total,
      (i) => {
        'name': 'Task ${i + 1}',
        'done': i < done,
      },
    );
  }

  List<String> _readImageUrls(Map<String, dynamic> data) {
    final raw = data['imageUrls'];
    if (raw is List) {
      final parsed = raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      if (parsed.isNotEmpty) return parsed;
    }

    final count = ((data['imageCount'] ?? 0) as num).toInt();
    if (count <= 0) return <String>[];
    return List.generate(count, (i) => 'Image ${i + 1}');
  }

  Future<void> _addTaskDialog(List<Map<String, dynamic>> current) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Task name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final updated = List<Map<String, dynamic>>.from(current)
      ..add({'name': name, 'done': false});
    _saveTasks(updated);
    if (mounted) setState(() => _showTasks = true);
  }

  Future<void> _editTaskNameDialog(List<Map<String, dynamic>> current, int index) async {
    if (index < 0 || index >= current.length) return;
    final existingName = (current[index]['name'] ?? 'Task').toString();
    final controller = TextEditingController(text: existingName);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Task name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (edited == null || edited.isEmpty) return;

    final updated = List<Map<String, dynamic>>.from(current);
    final row = Map<String, dynamic>.from(updated[index]);
    row['name'] = edited;
    updated[index] = row;
    _saveTasks(updated);
  }

  Future<void> _showImageSourceSheet(List<String> current) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndAddImage(current, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose From Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndAddImage(current, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('Paste Image URL'),
              onTap: () {
                Navigator.pop(context);
                _addImageUrlDialog(current);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndAddImage(List<String> current, ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      final updated = List<String>.from(current)..add(picked.path);
      _saveImages(updated);
      if (mounted) setState(() => _showImages = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not pick image from device')),
      );
    }
  }

  Future<void> _addImageUrlDialog(List<String> current) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste Image URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    final updated = List<String>.from(current)..add(value);
    _saveImages(updated);
    if (mounted) setState(() => _showImages = true);
  }

  void _saveTasks(List<Map<String, dynamic>> tasks) {
    final completed = tasks.where((t) => (t['done'] ?? false) == true).length;
    widget.onChanged(
      tasks: tasks,
      totalTasks: tasks.length,
      tasksCompleted: completed,
    );
  }

  void _saveImages(List<String> imageUrls) {
    widget.onChanged(
      imageUrls: imageUrls,
      imageCount: imageUrls.length,
    );
  }

  bool _looksLikeUrl(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  Widget _buildImageThumb(String value) {
    final trimmed = value.trim();
    if (_looksLikeUrl(trimmed)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          trimmed,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    }

    final file = File(trimmed);
    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          file,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    }

    return const SizedBox(
      width: 44,
      height: 44,
      child: Icon(Icons.image_outlined),
    );
  }
}
