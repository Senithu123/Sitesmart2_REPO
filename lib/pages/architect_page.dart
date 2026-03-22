import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/default_house_listings.dart';
import '../models/house_listing.dart';
import 'profile_page.dart';

class ArchitectPage extends StatefulWidget {
  const ArchitectPage({super.key});

  @override
  State<ArchitectPage> createState() => _ArchitectPageState();
}

class _ArchitectPageState extends State<ArchitectPage> {
  int selectedTab = 0;
  bool _saving = false;

  Future<void> _showHouseForm({
    HouseListing? listing,
    String? documentId,
  }) async {
    final result = await showDialog<_HouseFormResult>(
      context: context,
      builder: (context) => _HouseFormDialog(listing: listing),
    );

    if (result == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final createdListing = HouseListing(
      id: documentId ?? '',
      imagePath: listing?.imagePath ?? '',
      imageUrl: '',
      galleryPaths: result.galleryPaths,
      houseName: result.houseName,
      priceText: result.priceText,
      vrUrl: result.vrUrl,
      detail: '',
      location: result.location,
      bedrooms: result.bedrooms,
      bathrooms: result.bathrooms,
      sqft: result.sqft,
      about: result.about,
      features: result.features,
      isPublished: result.isPublished,
    );

    setState(() => _saving = true);
    try {
      final ref = documentId == null
          ? FirebaseFirestore.instance.collection('houses').doc()
          : FirebaseFirestore.instance.collection('houses').doc(documentId);
      await ref.set({
        ...createdListing.toMap(
          architectUid: user.uid,
          architectEmail: user.email ?? '',
        ),
        if (documentId == null) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            documentId == null
                ? 'House design added for clients.'
                : 'House design updated.',
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to save house design')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteHouse(String id) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete House Design'),
        content: const Text('Remove this house design from the app for clients?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await FirebaseFirestore.instance.collection('houses').doc(id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('House design deleted')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to delete house design')),
      );
    }
  }

  Widget _coverImage(HouseListing listing) {
    if (listing.galleryPaths.isNotEmpty) {
      final first = listing.galleryPaths.first;
      if (kIsWeb) {
        return Image.network(
          first,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _coverFallback(),
        );
      }
      return Image.file(
        File(first),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _coverFallback(),
      );
    }

    if (listing.hasNetworkImage) {
      return Image.network(
        listing.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _coverFallback(),
      );
    }

    if (listing.imagePath.trim().isNotEmpty) {
      return Image.asset(
        listing.imagePath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _coverFallback(),
      );
    }

    return _coverFallback();
  }

  Widget _coverFallback() {
    return Container(
      color: const Color(0xFFE7ECF8),
      alignment: Alignment.center,
      child: const Icon(Icons.architecture_outlined, size: 42, color: Color(0xFF1E2BFF)),
    );
  }

  List<HouseListing> _mergeListings(List<HouseListing> firestoreListings) {
    final merged = <String, HouseListing>{
      for (final listing in defaultHouseListings) listing.id: listing,
    };

    for (final listing in firestoreListings) {
      merged[listing.id] = listing;
    }

    return merged.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFF0),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF1E2BFF),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.architecture_outlined, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Architect Studio',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Create house details and VR-ready listings for clients.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : () => _showHouseForm(),
                    icon: const Icon(Icons.add_home_outlined, size: 18),
                    label: const Text('Add House'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1E2BFF),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('houses')
                    .orderBy('updatedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final message = snapshot.error.toString();
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.lock_outline,
                              size: 42,
                              color: Color(0xFF5B678D),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Architect access to house listings is blocked by Firestore rules.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              message.contains('permission-denied')
                                  ? 'Deploy the new Firestore rules so Architects and Admins can manage the houses collection.'
                                  : 'Failed to load architect listings: $message',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final firestoreListings = (snapshot.data?.docs ?? [])
                      .map((doc) => HouseListing.fromMap(doc.id, doc.data()))
                      .toList();
                  final firestoreIds = (snapshot.data?.docs ?? [])
                      .map((doc) => doc.id)
                      .toSet();
                  final listings = _mergeListings(firestoreListings);

                  return ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _ArchitectStat(
                                label: 'Designs',
                                value: '${listings.length}',
                              ),
                            ),
                            Expanded(
                              child: _ArchitectStat(
                                label: 'Visible',
                                value: '${listings.where((item) => item.isPublished).length}',
                              ),
                            ),
                            Expanded(
                              child: _ArchitectStat(
                                label: 'With VR',
                                value: '${listings.where((item) => item.vrUrl.trim().isNotEmpty).length}',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (listings.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.home_work_outlined, size: 42, color: Color(0xFF5B678D)),
                              SizedBox(height: 10),
                              Text(
                                'No house designs yet. Add a house here and it will appear in the client login home page.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        ...listings.map((listing) {
                          final hasFirestoreRecord = firestoreIds.contains(listing.id);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                  child: SizedBox(
                                    height: 180,
                                    width: double.infinity,
                                    child: _coverImage(listing),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              listing.houseName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: listing.isPublished
                                                  ? const Color(0xFFE9F8EE)
                                                  : const Color(0xFFF3F4F6),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              listing.isPublished ? 'Visible' : 'Hidden',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: listing.isPublished
                                                    ? const Color(0xFF1F8B4C)
                                                    : const Color(0xFF6B7280),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${listing.priceText} - ${listing.detail}',
                                        style: TextStyle(color: Colors.blueGrey.shade700),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        listing.location.isEmpty ? '-' : listing.location,
                                        style: TextStyle(color: Colors.blueGrey.shade700),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        listing.about,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(height: 1.4),
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          Chip(
                                            avatar: const Icon(Icons.view_in_ar_outlined, size: 16),
                                            label: Text(
                                              listing.vrUrl.trim().isEmpty ? 'No VR URL' : 'VR Added',
                                            ),
                                          ),
                                          ActionChip(
                                            avatar: const Icon(Icons.edit_outlined, size: 16),
                                            label: const Text('Edit'),
                                            onPressed: _saving
                                                ? null
                                                : () => _showHouseForm(
                                                      listing: listing,
                                                      documentId: listing.id,
                                                    ),
                                          ),
                                          if (hasFirestoreRecord)
                                            ActionChip(
                                              avatar: const Icon(Icons.delete_outline, size: 16),
                                              label: const Text('Delete'),
                                              onPressed: _saving ? null : () => _deleteHouse(listing.id),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFFDADADA),
        currentIndex: selectedTab,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black54,
        onTap: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfilePage()),
            );
            return;
          }
          setState(() {
            selectedTab = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _ArchitectStat extends StatelessWidget {
  final String label;
  final String value;

  const _ArchitectStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E2BFF),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
        ),
      ],
    );
  }
}

class _HouseFormResult {
  final String houseName;
  final String priceText;
  final List<String> galleryPaths;
  final String location;
  final String bedrooms;
  final String bathrooms;
  final String sqft;
  final String vrUrl;
  final String about;
  final List<String> features;
  final bool isPublished;

  const _HouseFormResult({
    required this.houseName,
    required this.priceText,
    required this.galleryPaths,
    required this.location,
    required this.bedrooms,
    required this.bathrooms,
    required this.sqft,
    required this.vrUrl,
    required this.about,
    required this.features,
    required this.isPublished,
  });
}

class _HouseFormDialog extends StatefulWidget {
  final HouseListing? listing;

  const _HouseFormDialog({this.listing});

  @override
  State<_HouseFormDialog> createState() => _HouseFormDialogState();
}

class _HouseFormDialogState extends State<_HouseFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _bedroomsCtrl;
  late final TextEditingController _bathroomsCtrl;
  late final TextEditingController _sqftCtrl;
  late final TextEditingController _vrUrlCtrl;
  late final TextEditingController _aboutCtrl;
  late final TextEditingController _featuresCtrl;
  late bool _isPublished;
  final ImagePicker _picker = ImagePicker();
  late List<String> _galleryPaths;

  @override
  void initState() {
    super.initState();
    final listing = widget.listing;
    _nameCtrl = TextEditingController(text: listing?.houseName ?? '');
    _priceCtrl = TextEditingController(text: listing?.priceText ?? '');
    _locationCtrl = TextEditingController(text: listing?.location ?? '');
    _bedroomsCtrl = TextEditingController(text: listing?.bedrooms ?? '');
    _bathroomsCtrl = TextEditingController(text: listing?.bathrooms ?? '');
    _sqftCtrl = TextEditingController(text: listing?.sqft ?? '');
    _vrUrlCtrl = TextEditingController(text: listing?.vrUrl ?? '');
    _aboutCtrl = TextEditingController(text: listing?.about ?? '');
    _featuresCtrl = TextEditingController(text: listing?.features.join('\n') ?? '');
    _isPublished = listing?.isPublished ?? true;
    _galleryPaths = List<String>.from(listing?.galleryPaths ?? const []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _locationCtrl.dispose();
    _bedroomsCtrl.dispose();
    _bathroomsCtrl.dispose();
    _sqftCtrl.dispose();
    _vrUrlCtrl.dispose();
    _aboutCtrl.dispose();
    _featuresCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;
      setState(() {
        _galleryPaths = [
          ..._galleryPaths,
          ...picked.map((file) => file.path),
        ];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to pick photos right now.')),
      );
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty ||
        _priceCtrl.text.trim().isEmpty ||
        _aboutCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill house name, price, and description.'),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      _HouseFormResult(
        houseName: _nameCtrl.text.trim(),
        priceText: _priceCtrl.text.trim(),
        galleryPaths: List<String>.from(_galleryPaths),
        location: _locationCtrl.text.trim(),
        bedrooms: _bedroomsCtrl.text.trim(),
        bathrooms: _bathroomsCtrl.text.trim(),
        sqft: _sqftCtrl.text.trim(),
        vrUrl: _vrUrlCtrl.text.trim(),
        about: _aboutCtrl.text.trim(),
        features: _featuresCtrl.text
            .split('\n')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
        isPublished: _isPublished,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.listing == null ? 'Add House Design' : 'Edit House Design'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(controller: _nameCtrl, label: 'House Name'),
            const SizedBox(height: 10),
            _field(controller: _priceCtrl, label: 'Price'),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickPhotos,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  _galleryPaths.isEmpty ? 'Add House Photos' : 'Add More Photos',
                ),
              ),
            ),
            if (_galleryPaths.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_galleryPaths.length} photo(s) selected',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _galleryPaths.asMap().entries.map((entry) {
                  final index = entry.key;
                  return InputChip(
                    avatar: const Icon(Icons.image_outlined, size: 16),
                    label: Text('Photo ${index + 1}'),
                    onDeleted: () {
                      setState(() {
                        _galleryPaths.removeAt(index);
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            _field(controller: _locationCtrl, label: 'Location'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _field(
                    controller: _bedroomsCtrl,
                    label: 'Bedrooms',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    controller: _bathroomsCtrl,
                    label: 'Bathrooms',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _field(
              controller: _sqftCtrl,
              label: 'Square Feet',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            _field(
              controller: _vrUrlCtrl,
              label: 'VR View URL',
              hint: 'https://...',
            ),
            const SizedBox(height: 10),
            _field(
              controller: _aboutCtrl,
              label: 'House Description',
              maxLines: 4,
            ),
            const SizedBox(height: 10),
            _field(
              controller: _featuresCtrl,
              label: 'Features',
              hint: 'One feature per line',
              maxLines: 5,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isPublished,
              onChanged: (value) => setState(() => _isPublished = value),
              contentPadding: EdgeInsets.zero,
              title: const Text('Visible to clients'),
              subtitle: const Text('Turn this off to hide the design from client logins.'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.listing == null ? 'Save' : 'Update'),
        ),
      ],
    );
  }
}
