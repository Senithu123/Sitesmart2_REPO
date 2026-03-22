import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
    {
      'id': 'finishing_work',
      'order': 4,
      'title': 'Finishing Work',
      'dateRange': 'Jan 1 - Jan 20',
      'percentage': 0,
      'tasksCompleted': 0,
      'totalTasks': 4,
      'imageCount': 0,
      'tasks': [
        {'name': 'Install doors and windows', 'done': false},
        {'name': 'Complete interior plastering', 'done': false},
        {'name': 'Apply paint and surface finishes', 'done': false},
        {'name': 'Final quality inspection', 'done': false},
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

      final existing = await timelineRef.get();
      final existingIds = existing.docs.map((doc) => doc.id).toSet();

      final batch = FirebaseFirestore.instance.batch();
      var addedAny = false;
      for (final phase in _defaultPhases) {
        final id = phase['id'].toString();
        if (existingIds.contains(id)) {
          continue;
        }
        batch.set(timelineRef.doc(id), {
          ...phase,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        });
        addedAny = true;
      }
      if (!addedAny) return;

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

  List<Map<String, dynamic>> _mergePhasesWithDefaults(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final merged = <String, Map<String, dynamic>>{
      for (final phase in _defaultPhases) phase['id'].toString(): Map<String, dynamic>.from(phase),
    };

    for (final doc in docs) {
      merged[doc.id] = {
        ...(merged[doc.id] ?? <String, dynamic>{}),
        'id': doc.id,
        ...doc.data(),
      };
    }

    final phases = merged.values.toList();
    phases.sort(
      (a, b) => ((a['order'] ?? 999) as num).toInt().compareTo(((b['order'] ?? 999) as num).toInt()),
    );
    return phases;
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

          final docs = snapshot.data?.docs ?? [];
          final phases = _mergePhasesWithDefaults(docs);

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: phases.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = phases[index];
              final phaseId = (data['id'] ?? '').toString().trim();
              return _PhaseEditorCard(
                projectId: widget.projectId,
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
                    phaseId,
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
  final String projectId;
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

  const _PhaseEditorCard({
    required this.projectId,
    required this.data,
    required this.onChanged,
  });

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
  late List<String> _localImageUrls;
  bool _showTasks = false;
  bool _showImages = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _pendingPercentage = ((widget.data['percentage'] ?? 0) as num)
        .toInt()
        .clamp(0, 100);
    _localImageUrls = _readImageUrls(widget.data);
  }

  @override
  void didUpdateWidget(covariant _PhaseEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final latest = ((widget.data['percentage'] ?? 0) as num).toInt().clamp(0, 100);
    if (latest != _pendingPercentage) {
      _pendingPercentage = latest;
    }
    final latestImages = _readImageUrls(widget.data);
    if (latestImages.length != _localImageUrls.length ||
        !_sameStringList(latestImages, _localImageUrls)) {
      _localImageUrls = latestImages;
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
    final imageUrls = _localImageUrls;
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
                      GestureDetector(
                        onTap: _canPreviewImage(entry.value) ? () => _showImagePreview(entry.value) : null,
                        child: _buildImageThumb(entry.value),
                      ),
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
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 45,
        maxWidth: 960,
        maxHeight: 960,
      );
      if (picked == null) return;
      String? imageValue;
      String successMessage = 'Image saved successfully';

      try {
        imageValue = await _inlineImageDataUrl(picked);
        successMessage = 'Image saved in app fallback mode';
      } catch (_) {
        imageValue = await _uploadPickedImage(picked);
        successMessage = 'Image uploaded successfully';
      }

      if (imageValue == null || imageValue.isEmpty) return;
      final updated = List<String>.from(current)..add(imageValue);
      _saveImages(updated);
      if (mounted) {
        setState(() => _showImages = true);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(successMessage)),
          );
      }
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_describeUploadError(error))),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not upload image: $error')),
        );
    }
  }

  Future<String?> _uploadPickedImage(XFile picked) async {
    final phaseId = (widget.data['id'] ?? 'phase').toString().trim();
    final normalizedPhaseId = phaseId.isEmpty ? 'phase' : phaseId;
    final extension = _fileExtension(picked.name);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance.ref().child(
      'projects/${widget.projectId}/timeline/$normalizedPhaseId/$timestamp$extension',
    );
    final metadata = SettableMetadata(
      contentType: _contentTypeForExtension(extension),
    );

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Uploading image...')),
        );
    }

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      await ref.putData(bytes, metadata);
    } else {
      await ref.putFile(File(picked.path), metadata);
    }

    return ref.getDownloadURL();
  }

  Future<String?> _inlineImageDataUrl(XFile picked) async {
    final bytes = await picked.readAsBytes();
    if (bytes.length > 350000) {
      throw Exception(
        'Image is too large for fallback upload. Please choose a smaller image or enable Firebase Storage.',
      );
    }

    final extension = _fileExtension(picked.name);
    final contentType = _contentTypeForExtension(extension);
    final encoded = base64Encode(bytes);
    return 'data:$contentType;base64,$encoded';
  }

  String _describeUploadError(FirebaseException error) {
    final code = error.code.trim();
    final message = error.message?.trim() ?? '';
    if (code == 'permission-denied' || code == 'unauthorized') {
      return 'Upload blocked by Firebase Storage rules. Deploy storage.rules, then try again.';
    }
    if (code == 'object-not-found' || code == 'bucket-not-found') {
      return 'Firebase Storage bucket is not ready for this project yet.';
    }
    if (code == 'no-app') {
      return 'Firebase Storage is not initialized for this app.';
    }
    if (message.isNotEmpty) {
      return 'Image upload failed: $message';
    }
    return code.isEmpty ? 'Image upload failed' : 'Image upload failed: $code';
  }

  String _fileExtension(String name) {
    final trimmed = name.trim();
    final dotIndex = trimmed.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == trimmed.length - 1) {
      return '.jpg';
    }
    return trimmed.substring(dotIndex).toLowerCase();
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
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
    setState(() {
      _localImageUrls = List<String>.from(imageUrls);
      _showImages = true;
    });
    widget.onChanged(
      imageUrls: imageUrls,
      imageCount: imageUrls.length,
    );
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _looksLikeUrl(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  bool _isInlineImageData(String value) {
    return value.trim().toLowerCase().startsWith('data:image/');
  }

  bool _canPreviewImage(String value) {
    final trimmed = value.trim();
    return _looksLikeUrl(trimmed) || _isInlineImageData(trimmed);
  }

  void _showImagePreview(String value) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: _buildPreviewImage(value),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 18,
                right: 18,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Uint8List? _decodeInlineImage(String value) {
    final trimmed = value.trim();
    final commaIndex = trimmed.indexOf(',');
    if (commaIndex < 0 || commaIndex == trimmed.length - 1) return null;
    try {
      return base64Decode(trimmed.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
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

    if (_isInlineImageData(trimmed)) {
      final bytes = _decodeInlineImage(trimmed);
      if (bytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            bytes,
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

  Widget _buildPreviewImage(String value) {
    final trimmed = value.trim();
    if (_looksLikeUrl(trimmed)) {
      return Image.network(
        trimmed,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _previewFallback(),
      );
    }

    if (_isInlineImageData(trimmed)) {
      final bytes = _decodeInlineImage(trimmed);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _previewFallback(),
        );
      }
    }

    return _previewFallback();
  }

  Widget _previewFallback() {
    return Container(
      color: const Color(0xFF111111),
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
    );
  }
}
