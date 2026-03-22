import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../data/default_house_listings.dart';
import '../models/house_listing.dart';
import '../services/vr_payment_service.dart';
import 'booking_confirmation_page.dart';
import 'bills_page.dart';
import 'profile_page.dart';
import 'timeline_page.dart';
import 'home_page.dart';
import 'project_waiting_page.dart';
import 'vr_view.dart';

class ClientProjectPage extends StatefulWidget {
  const ClientProjectPage({super.key});

  @override
  State<ClientProjectPage> createState() => _ClientProjectPageState();
}

class _ClientProjectPageState extends State<ClientProjectPage> {
  int _selectedIndex = 0;
  String _userName = 'User';
  String _projectTitle = 'Modern Family House';
  String _projectStatus = 'In Progress';
  String _projectLocation = '-';
  DateTime? _projectStartedAt;
  DateTime? _meetingDate;
  String? _approvedBookingId;
  HouseListing? _projectListing;
  bool _isVrAccessBusy = false;

  final List<_TeamMember> _teamMembers = const [
    _TeamMember(
      role: 'Contractor',
      name: 'Silva Constructions',
      icon: Icons.work_outline,
      phone: '+94 77 200 1001',
      detail: 'Main contractor handling site operations and labor.',
    ),
    _TeamMember(
      role: 'Architect',
      name: 'Design Studio LK',
      icon: Icons.design_services_outlined,
      phone: '+94 77 200 1002',
      detail: 'Responsible for design updates and technical drawings.',
    ),
    _TeamMember(
      role: 'Engineer',
      name: 'Nimal Perera',
      icon: Icons.person_outline,
      phone: '+94 77 200 1003',
      detail: 'Your primary communication contact for this project.',
    ),
    _TeamMember(
      role: 'Project Manager',
      name: 'Nimal Perera',
      icon: Icons.account_circle_outlined,
      phone: '+94 77 200 1004',
      detail: 'Oversees schedule, quality, and milestone tracking.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadProjectData();
  }

  Future<void> _loadUserName() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final authFallback = (currentUser.displayName?.trim().isNotEmpty ?? false)
        ? currentUser.displayName!.trim()
        : (currentUser.email?.split('@').first ?? 'Client');

    if (mounted) {
      setState(() => _userName = authFallback);
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      final data = doc.data() ?? <String, dynamic>{};
      final dbName = (data['fullName'] ??
              data['name'] ??
              data['full_name'] ??
              data['username'] ??
              authFallback)
          .toString()
          .trim();

      if (!mounted) return;
      setState(() => _userName = dbName.isEmpty ? authFallback : dbName);
    } catch (_) {
      // Keep auth fallback.
    }
  }

  void _onTabTap(int index) {
    setState(() => _selectedIndex = index);

    if (index == 1) {
      _openTimeline();
      return;
    }
    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BillsPage()),
      );
      return;
    }
    if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      );
    }
  }

  void _openTimeline() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TimelinePage(
          projectName: _projectTitle,
          projectStatus: _projectStatus,
          startedText: _formatStartedDate(_projectStartedAt),
        ),
      ),
    );
  }

  Future<void> _loadProjectData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      if (snap.docs.isEmpty) {
        _redirectToClientHome();
        return;
      }

      QueryDocumentSnapshot<Map<String, dynamic>>? latestDoc;
      DateTime? latestDate;
      QueryDocumentSnapshot<Map<String, dynamic>>? latestApprovedDoc;
      DateTime? latestApprovedDate;

      for (final doc in snap.docs) {
        final data = doc.data();
        final ts = data['createdAt'] as Timestamp?;
        final date = ts?.toDate() ?? DateTime(2000);
        if (latestDate == null || date.isAfter(latestDate)) {
          latestDate = date;
          latestDoc = doc;
        }

        if (_isApproved(data)) {
          final approvedDate =
              _extractApprovalDate(data) ??
              _parseAnyDate(data['appointmentDate']) ??
              _parseAnyDate(data['createdAt']) ??
              date;
          if (latestApprovedDate == null || approvedDate.isAfter(latestApprovedDate)) {
            latestApprovedDate = approvedDate;
            latestApprovedDoc = doc;
          }
        }
      }

      if (latestDoc == null) {
        _redirectToClientHome();
        return;
      }
      final latest = latestDoc.data();
      final approvedData = latestApprovedDoc?.data();
      final approvedBookingId = latestApprovedDoc?.id;
      if (approvedData == null || approvedBookingId == null) {
        _redirectToWaitingPage();
        return;
      }

      final projectDoc = await FirebaseFirestore.instance
          .collection('projects')
          .doc(approvedBookingId)
          .get();
      if (!projectDoc.exists) {
        _redirectToWaitingPage();
        return;
      }

      final startedDate =
          _extractApprovalDate(approvedData) ??
          _parseAnyDate(approvedData['appointmentDate']) ??
          _parseAnyDate(approvedData['createdAt']);
      final meetingDate =
          _parseAnyDate(approvedData['appointmentDate']) ??
          _parseAnyDate(latest['appointmentDate']);
      final projectData = projectDoc.data() ?? <String, dynamic>{};
      final resolvedHouseId = (projectData['houseId'] ??
              approvedData['houseId'] ??
              latest['houseId'])
          .toString()
          .trim();
      final resolvedTitle =
          (projectData['houseTitle'] ??
                  approvedData['houseTitle'] ??
                  latest['houseTitle'])
              .toString()
              .trim();
      final resolvedListing = await _resolveHouseListing(
        houseId: resolvedHouseId,
        title: resolvedTitle,
      );
      final resolvedLocation = (projectData['location'] ??
              approvedData['location'] ??
              latest['location'] ??
              resolvedListing?.location ??
              '-')
          .toString()
          .trim();

      if (!mounted) return;
      setState(() {
        if (resolvedTitle.isNotEmpty) {
          _projectTitle = resolvedTitle;
        }

        final status =
            (projectData['status'] ?? approvedData['status'] ?? latest['status'])
                .toString()
                .trim();
        if (status.isNotEmpty) {
          _projectStatus = status;
        }
        _projectLocation = resolvedLocation.isEmpty ? '-' : resolvedLocation;
        _projectStartedAt = startedDate;
        _meetingDate = meetingDate;
        _approvedBookingId = approvedBookingId;
        _projectListing = resolvedListing;
      });
    } catch (_) {
      // Keep UI defaults when data is unavailable.
    }
  }

  Future<HouseListing?> _resolveHouseListing({
    String? houseId,
    required String title,
  }) async {
    final normalizedHouseId = houseId?.trim() ?? '';
    final normalizedTitle = title.trim().toLowerCase();
    if (normalizedHouseId.isEmpty && normalizedTitle.isEmpty) return null;

    HouseListing? defaultFallbackForTitle() {
      if (normalizedTitle.contains('lakeside') || normalizedTitle.contains('retreat')) {
        return defaultHouseListings.firstWhere(
          (listing) => listing.id == 'default-house-1',
        );
      }
      if (normalizedTitle.contains('cliffside') || normalizedTitle.contains('pool house')) {
        return defaultHouseListings.firstWhere(
          (listing) => listing.id == 'default-house-2',
        );
      }
      if (normalizedTitle.contains('hillside') || normalizedTitle.contains('glass residence')) {
        return defaultHouseListings.firstWhere(
          (listing) => listing.id == 'default-house-3',
        );
      }
      if (normalizedTitle.contains('urban') || normalizedTitle.contains('smart residence')) {
        return defaultHouseListings.firstWhere(
          (listing) => listing.id == 'default-house-4',
        );
      }
      return null;
    }

    bool matches(String candidate) {
      final normalizedCandidate = candidate.trim().toLowerCase();
      if (normalizedCandidate.isEmpty) return false;
      return normalizedCandidate == normalizedTitle ||
          normalizedCandidate.contains(normalizedTitle) ||
          normalizedTitle.contains(normalizedCandidate);
    }

    if (normalizedHouseId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('houses')
            .doc(normalizedHouseId)
            .get();
        if (doc.exists) {
          return HouseListing.fromMap(doc.id, doc.data()!);
        }
      } catch (_) {}

      for (final listing in defaultHouseListings) {
        if (listing.id == normalizedHouseId) {
          return listing;
        }
      }
    }

    if (normalizedTitle.isEmpty) {
      return null;
    }

    try {
      final snap = await FirebaseFirestore.instance.collection('houses').get();
      for (final doc in snap.docs) {
        final listing = HouseListing.fromMap(doc.id, doc.data());
        if (matches(listing.houseName)) {
          return listing;
        }
      }
    } catch (_) {}

    for (final listing in defaultHouseListings) {
      if (matches(listing.houseName)) {
        return listing;
      }
    }

    return defaultFallbackForTitle();
  }

  void _redirectToClientHome() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  void _redirectToWaitingPage() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const ProjectWaitingPage()),
      (route) => false,
    );
  }

  DateTime? _extractApprovalDate(Map<String, dynamic> data) {
    final keys = [
      'accessGrantedAt',
      'approvedAt',
      'approvalDate',
    ];

    for (final key in keys) {
      final value = data[key];
      final parsed = _parseAnyDate(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool _isApproved(Map<String, dynamic> data) {
    final access = data['accessGranted'];
    if (access == true) return true;
    if (access is String && access.toLowerCase() == 'true') return true;

    final status = data['status']?.toString().toLowerCase() ?? '';
    if (status.contains('access granted') || status.contains('approved')) {
      return true;
    }
    return false;
  }

  DateTime? _parseAnyDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      // Accept epoch milliseconds or seconds.
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  String _formatStartedDate(DateTime? date) {
    if (date == null) return 'N/A';
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

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openBookingConfirmation() {
    Navigator.push(
      context,
        MaterialPageRoute(
          builder: (_) => BookingConfirmationPage(
            bookingId: _approvedBookingId,
            meetingDate: _meetingDate,
            houseTitle: _projectTitle,
          ),
      ),
    );
  }

  Future<void> _openProjectVr() async {
    final listing = _projectListing;
    if (listing == null || listing.vrUrl.trim().isEmpty) {
      _showSnackBar('VR view is not available for this project yet.');
      return;
    }
    if (_isVrAccessBusy) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showSnackBar('Please sign in to unlock VR access.');
      return;
    }

    setState(() {
      _isVrAccessBusy = true;
    });

    try {
      final hasAccess = await VrPaymentService.hasVrAccess(
        houseTitle: listing.houseName,
      );
      if (!mounted) return;

      if (hasAccess) {
        _navigateToProjectVr(listing);
        return;
      }

      if (!VrPaymentService.supportsNativeVrPayments) {
        _showSnackBar(VrPaymentService.unsupportedPlatformMessage);
        return;
      }

      final shouldContinue = await _showVrPaymentDialog(listing.houseName);
      if (!mounted || !shouldContinue) return;

      await VrPaymentService.payForVrAccess(
        houseTitle: listing.houseName,
        customerName: _resolveCustomerName(currentUser),
        email: currentUser.email ?? '',
      );
      if (!mounted) return;

      _showSnackBar('Payment successful. VR access unlocked.');
      _navigateToProjectVr(listing);
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(VrPaymentService.describeError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isVrAccessBusy = false;
        });
      }
    }
  }

  void _navigateToProjectVr(HouseListing listing) {
    final imagePath = listing.galleryPaths.isNotEmpty
        ? listing.galleryPaths.first
        : (listing.imagePath.trim().isNotEmpty ? listing.imagePath : '');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VrViewPage(
          title: listing.houseName,
          imagePath: imagePath,
          vrUrl: listing.vrUrl,
        ),
      ),
    );
  }

  String _resolveCustomerName(User user) {
    final candidate = _userName.trim();
    if (candidate.isNotEmpty && candidate.toLowerCase() != 'user') {
      return candidate;
    }

    final displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }

    final emailPrefix = user.email?.split('@').first.trim() ?? '';
    return emailPrefix.isEmpty ? 'Site Smart Customer' : emailPrefix;
  }

  Future<bool> _showVrPaymentDialog(String houseTitle) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Unlock VR Tour'),
        content: Text(
          '$houseTitle requires a one-time ${VrPaymentService.vrPriceLabel} Stripe payment to unlock all VR tours on this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Pay ${VrPaymentService.vrPriceLabel}'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  void _showTeamMemberDetails(_TeamMember member) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(member.role),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(member.detail),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.phone, size: 18),
                const SizedBox(width: 8),
                Text(member.phone),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Column(
        children: [
          _TopBar(userName: _userName),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Current Project'),
                  const SizedBox(height: 10),
                  _ProjectCard(
                    title: _projectTitle,
                    listing: _projectListing,
                    location: _projectLocation,
                    startedText: _formatStartedDate(_projectStartedAt),
                    statusText: _projectStatus,
                    onTap: _openTimeline,
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle('Quick Actions'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.calendar_today_outlined,
                          title: 'Booking',
                          onTap: _openBookingConfirmation,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle('Engineer'),
                  const SizedBox(height: 4),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: _teamMembers.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.35,
                    ),
                    itemBuilder: (context, index) {
                      final member = _teamMembers[index];
                      return _TeamCard(
                        member: member,
                        onTap: () => _showTeamMemberDetails(member),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _HotlineCard(
                    onTapVrew: _isVrAccessBusy ? null : _openProjectVr,
                    isBusy: _isVrAccessBusy,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFE6E7EB),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomItem(
                icon: Icons.dashboard_outlined,
                label: 'Home',
                selected: _selectedIndex == 0,
                onTap: () => _onTabTap(0),
              ),
              _BottomItem(
                icon: Icons.article_outlined,
                label: 'Timeline',
                selected: _selectedIndex == 1,
                onTap: () => _onTabTap(1),
              ),
              _BottomItem(
                icon: Icons.receipt_long_outlined,
                label: 'Bills',
                selected: _selectedIndex == 2,
                onTap: () => _onTabTap(2),
              ),
              _BottomItem(
                icon: Icons.account_circle_outlined,
                label: 'Profile',
                selected: _selectedIndex == 3,
                onTap: () => _onTabTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String userName;

  const _TopBar({required this.userName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 44, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E32FF), Color(0xFF1F17F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.apartment_rounded, color: Colors.white, size: 32),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Site Smart',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    userName,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Client',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Color(0xFF171C2C),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final String title;
  final HouseListing? listing;
  final String location;
  final String startedText;
  final String statusText;
  final VoidCallback onTap;

  const _ProjectCard({
    required this.title,
    required this.listing,
    required this.location,
    required this.startedText,
    required this.statusText,
    required this.onTap,
  });

  Widget _buildProjectImage() {
    if (listing != null) {
      if (listing!.galleryPaths.isNotEmpty) {
        final path = listing!.galleryPaths.first;
        if (kIsWeb) {
          return Image.network(
            path,
            width: 128,
            height: 108,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _imageFallback(),
          );
        }
        return Image.file(
          File(path),
          width: 128,
          height: 108,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imageFallback(),
        );
      }

      if (listing!.imageUrl.trim().isNotEmpty) {
        return Image.network(
          listing!.imageUrl,
          width: 128,
          height: 108,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imageFallback(),
        );
      }

      if (listing!.imagePath.trim().isNotEmpty) {
        return Image.asset(
          listing!.imagePath,
          width: 128,
          height: 108,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imageFallback(),
        );
      }
    }

    return _imageFallback();
  }

  Widget _imageFallback() {
    return Container(
      width: 128,
      height: 108,
      color: const Color(0xFFE2E6F0),
      child: const Icon(Icons.home_work_outlined),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDCE1EE)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0D1A33),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: _buildProjectImage(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Location: $location', style: const TextStyle(color: Color(0xFF30364A))),
                    Text('Started: $startedText', style: const TextStyle(color: Color(0xFF30364A))),
                    Text('Status: $statusText', style: const TextStyle(color: Color(0xFF30364A))),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.chevron_right, color: Color(0xFF5B678D), size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: const Color(0xFFE8ECF8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD6DDF2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF2B3B76), size: 24),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final _TeamMember member;
  final VoidCallback onTap;

  const _TeamCard({required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD8DDEA)),
        ),
        child: Row(
          children: [
            Icon(member.icon, color: const Color(0xFF2C3A61)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.role, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(member.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotlineCard extends StatelessWidget {
  final VoidCallback? onTapVrew;
  final bool isBusy;

  const _HotlineCard({
    required this.onTapVrew,
    required this.isBusy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFDFE7FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Explore Your House',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  isBusy ? 'Preparing your VR payment sheet' : 'Call our hotline for project support',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 2),
                const Text(
                  '+94 77 123 4567',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onTapVrew,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2C47F8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      '🥽',
                      style: TextStyle(fontSize: 24),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BottomItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: selected ? Colors.black : Colors.black54),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamMember {
  final String role;
  final String name;
  final IconData icon;
  final String phone;
  final String detail;

  const _TeamMember({
    required this.role,
    required this.name,
    required this.icon,
    required this.phone,
    required this.detail,
  });
}
