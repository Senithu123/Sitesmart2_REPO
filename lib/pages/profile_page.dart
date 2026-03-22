import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login_page.dart';
// Improving profile management (validation and UI handling)
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool isLoggingOut = false;
  late Future<_ProfileBundle?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<_ProfileBundle?> _loadProfile() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;

    final firestore = FirebaseFirestore.instance;
    final userDoc = await firestore.collection('users').doc(currentUser.uid).get();
    final userData = userDoc.data() ?? <String, dynamic>{};

    final role = (userData['role'] ?? 'Client').toString().trim();
    final fullName = (userData['fullName'] ??
            userData['name'] ??
            currentUser.displayName ??
            currentUser.email?.split('@').first ??
            'User')
        .toString()
        .trim();
    final email = (userData['email'] ?? currentUser.email ?? '-').toString().trim();
    final phone = (userData['phone'] ?? userData['mobile'] ?? '-').toString().trim();

    final baseInfo = _ProfileBundle(
      name: fullName.isEmpty ? 'User' : fullName,
      email: email.isEmpty ? '-' : email,
      role: role.isEmpty ? 'Client' : role,
      phone: phone.isEmpty ? '-' : phone,
      joinedAt: _readDate(userData['createdAt']),
      lastLoginAt: _readDate(userData['lastLogin']),
      stats: const [],
      detailItems: const [],
      roleSummaryTitle: 'Profile',
      roleSummaryMessage: 'Your account details are ready.',
    );

    if (role == 'Client') {
      final bookings = await firestore
          .collection('bookings')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? latestBooking;
      DateTime? latestBookingDate;
      QueryDocumentSnapshot<Map<String, dynamic>>? latestApprovedBooking;
      DateTime? latestApprovedDate;

      for (final doc in bookings.docs) {
        final data = doc.data();
        final createdAt = _readDate(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (latestBookingDate == null || createdAt.isAfter(latestBookingDate)) {
          latestBookingDate = createdAt;
          latestBooking = doc;
        }

        if (_isApproved(data)) {
          final approvalDate =
              _readDate(data['accessGrantedAt']) ??
              _readDate(data['appointmentDate']) ??
              createdAt;
          if (latestApprovedDate == null || approvalDate.isAfter(latestApprovedDate)) {
            latestApprovedDate = approvalDate;
            latestApprovedBooking = doc;
          }
        }
      }

      final latestBookingData = latestBooking?.data() ?? <String, dynamic>{};
      final projectId = latestApprovedBooking?.id;
      DocumentSnapshot<Map<String, dynamic>>? projectDoc;
      if (projectId != null) {
        projectDoc = await firestore.collection('projects').doc(projectId).get();
      }
      final projectData = projectDoc?.data() ?? <String, dynamic>{};

      return baseInfo.copyWith(
        stats: [
          _StatItem('Bookings', '${bookings.docs.length}', Icons.event_note_outlined),
          _StatItem(
            'Access',
            latestApprovedBooking != null ? 'Granted' : 'Pending',
            latestApprovedBooking != null ? Icons.verified_user_outlined : Icons.hourglass_bottom,
          ),
          _StatItem(
            'Project',
            projectDoc?.exists == true ? 'Active' : 'Not Started',
            projectDoc?.exists == true ? Icons.home_work_outlined : Icons.schedule_outlined,
          ),
        ],
        roleSummaryTitle: 'Client Overview',
        roleSummaryMessage: latestApprovedBooking != null
            ? 'Your project access has been approved. You can follow progress and billing from the client area.'
            : 'Your booking is still waiting for approval. Once payment is confirmed, project tools will unlock.',
        detailItems: [
          _DetailItem('Latest House', (latestBookingData['houseTitle'] ?? '-').toString()),
          _DetailItem('Booking Status', (latestBookingData['status'] ?? 'No booking yet').toString()),
          _DetailItem(
            'Appointment Date',
            _formatDate(_readDate(latestBookingData['appointmentDate']), includeTime: true),
          ),
          _DetailItem('Project Status', (projectData['status'] ?? 'Not started').toString()),
          _DetailItem('Project Location', (projectData['location'] ?? latestBookingData['location'] ?? '-').toString()),
        ],
      );
    }

    if (role == 'Contractor') {
      final assignedProjects = await firestore
          .collection('projects')
          .where('contractorUid', isEqualTo: currentUser.uid)
          .get();

      final inProgress = assignedProjects.docs
          .where((doc) => (doc.data()['status'] ?? '').toString().toLowerCase() != 'completed')
          .length;

      final latestProject = _findLatestByCreatedAt(assignedProjects.docs);
      final latestProjectData = latestProject?.data() ?? <String, dynamic>{};

      return baseInfo.copyWith(
        stats: [
          _StatItem('Projects', '${assignedProjects.docs.length}', Icons.home_repair_service_outlined),
          _StatItem('Active', '$inProgress', Icons.construction_outlined),
          _StatItem(
            'Latest Status',
            (latestProjectData['status'] ?? 'No Project').toString(),
            Icons.timeline_outlined,
          ),
        ],
        roleSummaryTitle: 'Contractor Overview',
        roleSummaryMessage:
            'This profile focuses on assigned project work so you can quickly see your current construction workload.',
        detailItems: [
          _DetailItem('Latest Project', (latestProjectData['houseTitle'] ?? '-').toString()),
          _DetailItem('Client Email', (latestProjectData['clientEmail'] ?? '-').toString()),
          _DetailItem('Location', (latestProjectData['location'] ?? '-').toString()),
          _DetailItem('Started', _formatDate(_readDate(latestProjectData['startedAt']))),
          _DetailItem('Status', (latestProjectData['status'] ?? '-').toString()),
        ],
      );
    }

    if (role == 'Admin') {
      final users = await firestore.collection('users').get();
      final bookings = await firestore.collection('bookings').get();
      final projects = await firestore.collection('projects').get();

      final pendingApprovals = bookings.docs
          .where((doc) => doc.data()['accessGranted'] != true)
          .length;

      return baseInfo.copyWith(
        stats: [
          _StatItem('Users', '${users.docs.length}', Icons.group_outlined),
          _StatItem('Bookings', '${bookings.docs.length}', Icons.event_note_outlined),
          _StatItem('Pending', '$pendingApprovals', Icons.pending_actions_outlined),
        ],
        roleSummaryTitle: 'Admin Overview',
        roleSummaryMessage:
            'You have system-wide visibility. Use this profile as a quick snapshot of platform activity and approvals.',
        detailItems: [
          _DetailItem('Active Projects', '${projects.docs.length}'),
          _DetailItem(
            'Contractors',
            '${users.docs.where((doc) => (doc.data()['role'] ?? '').toString() == 'Contractor').length}',
          ),
          _DetailItem(
            'Architects',
            '${users.docs.where((doc) => (doc.data()['role'] ?? '').toString() == 'Architect').length}',
          ),
          _DetailItem(
            'Clients',
            '${users.docs.where((doc) => (doc.data()['role'] ?? '').toString() == 'Client').length}',
          ),
          _DetailItem('Last Login', _formatDate(baseInfo.lastLoginAt, fallback: 'Not recorded')),
        ],
      );
    }

    final projects = await firestore.collection('projects').get();
    final activeProjects = projects.docs
        .where((doc) => doc.data()['startedConstruction'] == true)
        .length;

    return baseInfo.copyWith(
      stats: [
        _StatItem('Role', role, Icons.badge_outlined),
        _StatItem('Active Projects', '$activeProjects', Icons.architecture_outlined),
        _StatItem('Status', 'Available', Icons.verified_outlined),
      ],
      roleSummaryTitle: 'Architect Overview',
      roleSummaryMessage:
          'This profile highlights your design-side role in the system. You can extend this later with drawings and review requests.',
      detailItems: [
        _DetailItem('Design Role', role),
        _DetailItem('Email', email),
        _DetailItem('Phone', phone.isEmpty ? '-' : phone),
        _DetailItem('Joined', _formatDate(baseInfo.joinedAt)),
        _DetailItem('Last Login', _formatDate(baseInfo.lastLoginAt, fallback: 'Not recorded')),
      ],
    );
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _findLatestByCreatedAt(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    QueryDocumentSnapshot<Map<String, dynamic>>? latest;
    DateTime? latestDate;
    for (final doc in docs) {
      final createdAt = _readDate(doc.data()['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (latestDate == null || createdAt.isAfter(latestDate)) {
        latestDate = createdAt;
        latest = doc;
      }
    }
    return latest;
  }

  DateTime? _readDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) {
      if (value > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value > 1000000000) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    return null;
  }

  bool _isApproved(Map<String, dynamic> data) {
    if (data['accessGranted'] == true) return true;
    final status = (data['status'] ?? '').toString().toLowerCase();
    return status.contains('approved') || status.contains('access granted');
  }

  String _formatDate(
    DateTime? date, {
    String fallback = '-',
    bool includeTime = false,
  }) {
    if (date == null) return fallback;
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
    final base = '${date.day} ${months[date.month - 1]} ${date.year}';
    if (!includeTime) return base;
    final hour = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return '$base, $hour:$minute $ampm';
  }

  Future<void> logout() async {
    if (isLoggingOut) return;
    setState(() {
      isLoggingOut = true;
    });

    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logout failed')),
      );
      setState(() {
        isLoggingOut = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: const Color(0xFF1E2BFF),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<_ProfileBundle?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load profile: ${snapshot.error}'),
              ),
            );
          }

          final profile = snapshot.data;
          if (profile == null) {
            return const Center(child: Text('Please log in again'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              final nextFuture = _loadProfile();
              setState(() {
                _profileFuture = nextFuture;
              });
              await nextFuture;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeroCard(profile: profile),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Account Details',
                  child: Column(
                    children: [
                      _InfoRow(label: 'Full Name', value: profile.name),
                      _InfoRow(label: 'Email', value: profile.email),
                      _InfoRow(label: 'Phone', value: profile.phone),
                      _InfoRow(label: 'Role', value: profile.role),
                      _InfoRow(label: 'Joined', value: _formatDate(profile.joinedAt)),
                      _InfoRow(
                        label: 'Last Login',
                        value: _formatDate(profile.lastLoginAt, fallback: 'Not recorded'),
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Role Specific Details',
                  child: Column(
                    children: [
                      for (int i = 0; i < profile.detailItems.length; i++)
                        _InfoRow(
                          label: profile.detailItems[i].label,
                          value: profile.detailItems[i].value,
                          isLast: i == profile.detailItems.length - 1,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isLoggingOut ? null : logout,
                    icon: const Icon(Icons.logout),
                    label: Text(isLoggingOut ? 'Logging out...' : 'Logout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final _ProfileBundle profile;

  const _HeroCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2433FF), Color(0xFF1D7FF2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white24,
            child: Text(
              profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'U',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.email,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    profile.role,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE2F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFE8ECF6)),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF69738E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF171C2C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final _StatItem item;

  const _StatCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E1F4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: const Color(0xFF2444C2)),
          const SizedBox(height: 8),
          Text(
            item.value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF5A6482),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBundle {
  final String name;
  final String email;
  final String role;
  final String phone;
  final DateTime? joinedAt;
  final DateTime? lastLoginAt;
  final List<_StatItem> stats;
  final List<_DetailItem> detailItems;
  final String roleSummaryTitle;
  final String roleSummaryMessage;

  const _ProfileBundle({
    required this.name,
    required this.email,
    required this.role,
    required this.phone,
    required this.joinedAt,
    required this.lastLoginAt,
    required this.stats,
    required this.detailItems,
    required this.roleSummaryTitle,
    required this.roleSummaryMessage,
  });

  _ProfileBundle copyWith({
    String? name,
    String? email,
    String? role,
    String? phone,
    DateTime? joinedAt,
    DateTime? lastLoginAt,
    List<_StatItem>? stats,
    List<_DetailItem>? detailItems,
    String? roleSummaryTitle,
    String? roleSummaryMessage,
  }) {
    return _ProfileBundle(
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      joinedAt: joinedAt ?? this.joinedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      stats: stats ?? this.stats,
      detailItems: detailItems ?? this.detailItems,
      roleSummaryTitle: roleSummaryTitle ?? this.roleSummaryTitle,
      roleSummaryMessage: roleSummaryMessage ?? this.roleSummaryMessage,
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem(this.label, this.value, this.icon);
}

class _DetailItem {
  final String label;
  final String value;

  const _DetailItem(this.label, this.value);
}
