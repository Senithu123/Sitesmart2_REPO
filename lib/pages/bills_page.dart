import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'profile_page.dart';
import 'timeline_page.dart';

class BillsPage extends StatefulWidget {
  const BillsPage({super.key});

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  int _selectedIndex = 2;
  String _userName = 'Client';
  String? _projectId;
  num _projectHouseValue = 0;
  bool _loadingProject = true;
  String? _projectLoadError;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadProject();
  }

  Future<void> _loadUserName() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final fallback = currentUser.email?.split('@').first ?? 'Client';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final data = doc.data() ?? <String, dynamic>{};
      final name = (data['fullName'] ?? data['name'] ?? fallback).toString();
      if (!mounted) return;
      setState(() => _userName = name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _userName = fallback);
    }
  }

  Future<void> _loadProject() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      setState(() => _loadingProject = false);
      return;
    }

    try {
      final approvedBookingId = await _loadLatestApprovedBookingId(currentUser.uid);
      final projectId = await _resolveProjectId(
        currentUser.uid,
        approvedBookingId: approvedBookingId,
      );
      final projectHouseValue = await _loadProjectHouseValue(
        projectId: projectId,
        bookingId: approvedBookingId,
      );

      if (!mounted) return;
      setState(() {
        _projectId = projectId ?? approvedBookingId;
        _projectHouseValue = projectHouseValue;
        _loadingProject = false;
        _projectLoadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProject = false;
        _projectLoadError = e.toString();
      });
    }
  }

  Future<String?> _loadLatestApprovedBookingId(String uid) async {
    final firestore = FirebaseFirestore.instance;
    final bookingSnap = await firestore
        .collection('bookings')
        .where('userId', isEqualTo: uid)
        .get();
    return _findLatestApprovedBooking(bookingSnap.docs)?.id;
  }

  Future<num> _loadProjectHouseValue({
    required String? projectId,
    required String? bookingId,
  }) async {
    if (projectId == null && bookingId == null) return 0;

    final firestore = FirebaseFirestore.instance;
    DocumentSnapshot<Map<String, dynamic>>? projectDoc;
    Map<String, dynamic> projectData = <String, dynamic>{};
    if (projectId != null) {
      try {
        projectDoc = await firestore.collection('projects').doc(projectId).get();
        projectData = projectDoc.data() ?? <String, dynamic>{};
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }

    final fromProject = _parseMoneyValue(projectData['priceText']);
    if (fromProject > 0) {
      return fromProject;
    }

    final resolvedBookingId =
        bookingId ?? (projectData['bookingId'] ?? projectId).toString();
    if (resolvedBookingId.isEmpty) return 0;
    final bookingDoc = await firestore.collection('bookings').doc(resolvedBookingId).get();
    final bookingData = bookingDoc.data() ?? <String, dynamic>{};
    final fromBooking = _parseMoneyValue(bookingData['priceText']);

    if (fromBooking > 0 && projectDoc?.exists == true && projectId != null) {
      try {
        await firestore.collection('projects').doc(projectId).update({
          'priceText': (bookingData['priceText'] ?? '').toString(),
        });
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }

    return fromBooking;
  }

  Future<String?> _resolveProjectId(
    String uid, {
    required String? approvedBookingId,
  }) async {
    final firestore = FirebaseFirestore.instance;

    final bookingSnap = await firestore
        .collection('bookings')
        .where('userId', isEqualTo: uid)
        .get();
    final latestApprovedBooking = _findLatestApprovedBooking(bookingSnap.docs);
    if (latestApprovedBooking != null) {
      return latestApprovedBooking.id;
    }

    final fallbackBooking = _findLatestBooking(bookingSnap.docs);
    final fallbackBookingId = approvedBookingId ?? fallbackBooking?.id;
    return fallbackBookingId;
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _findLatestApprovedBooking(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    QueryDocumentSnapshot<Map<String, dynamic>>? latest;
    DateTime? latestDate;

    for (final doc in docs) {
      final data = doc.data();
      final accessValue = data['accessGranted'];
      final accessGranted = accessValue == true ||
          (accessValue is String && accessValue.toLowerCase() == 'true');
      final paymentValue = data['paymentConfirmed'];
      final paymentConfirmed = paymentValue == true ||
          (paymentValue is String && paymentValue.toLowerCase() == 'true');
      final status = (data['status'] ?? '').toString().toLowerCase();
      final isApproved =
          accessGranted || paymentConfirmed || status.contains('access granted') || status.contains('approved');
      if (!isApproved) continue;

      final dt = _parseDate(
            data['accessGrantedAt'] ?? data['createdAt'] ?? data['appointmentDate'],
          ) ??
          DateTime(2000);
      if (latestDate == null || dt.isAfter(latestDate)) {
        latestDate = dt;
        latest = doc;
      }
    }

    return latest;
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _findLatestBooking(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    QueryDocumentSnapshot<Map<String, dynamic>>? latest;
    DateTime? latestDate;

    for (final doc in docs) {
      final data = doc.data();
      final dt = _parseDate(
            data['createdAt'] ?? data['appointmentDate'],
          ) ??
          DateTime(2000);
      if (latestDate == null || dt.isAfter(latestDate)) {
        latestDate = dt;
        latest = doc;
      }
    }
    return latest;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
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

  void _onTabTap(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) {
      Navigator.pop(context);
      return;
    }
    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const TimelinePage(
            projectName: 'Project',
            projectStatus: 'In Progress',
            startedText: 'Started',
          ),
        ),
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

  String _formatCurrency(num amount) {
    final value = amount.round().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < value.length; i++) {
      final reverseIndex = value.length - i;
      buffer.write(value[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(',');
      }
    }
    return 'Rs.${buffer.toString()}';
  }

  num _parseMoneyValue(dynamic rawValue) {
    final normalized = rawValue
        ?.toString()
        .trim()
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .replaceAll(RegExp(r'lkr|rs\.?', caseSensitive: false), '') ??
        '';
    if (normalized.isEmpty) return 0;
    return num.tryParse(normalized) ?? 0;
  }

  IconData _statusIcon(String title) {
    final value = title.toLowerCase();
    if (value.contains('total bill')) return Icons.attach_money_rounded;
    if (value.contains('pending payments')) return Icons.pending_actions_outlined;
    if (value.contains('payments made')) return Icons.payments_outlined;
    if (value.contains('paid')) return Icons.verified_outlined;
    return Icons.receipt_long_outlined;
  }

  String _formatShortDate(Timestamp? ts) {
    if (ts == null) return 'Pending';
    final d = ts.toDate();
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
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F6),
      body: Column(
        children: [
          _BillsTopBar(userName: _userName),
          Expanded(
            child: _loadingProject
                ? const Center(child: CircularProgressIndicator())
                : _projectLoadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Could not load bills.\n$_projectLoadError',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _projectId == null
                ? const Center(child: Text('No bill data available'))
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('projects')
                        .doc(_projectId)
                        .collection('bills')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              'Failed to read bills.\n${snapshot.error}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];
                      final bills = docs.map((d) => d.data()).toList();
                      final paidBills = bills
                          .where((bill) => (bill['status'] ?? '').toString().toLowerCase() == 'paid')
                          .toList();
                      final paidAmount = paidBills.fold<num>(
                        0,
                        (total, bill) => total + ((bill['amount'] ?? 0) as num),
                      );
                      final pendingBills = bills
                          .where((bill) => (bill['status'] ?? '').toString().toLowerCase() != 'paid')
                          .toList();

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                        children: [
                          const Text(
                            'Bill Management',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Track all outstanding and paid vendor invoices across project',
                            style: TextStyle(fontSize: 13, color: Color(0xFF687189)),
                          ),
                          const SizedBox(height: 14),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.45,
                            children: [
                              _StatCard(
                                title: 'Total Bill Value',
                                value: _formatCurrency(_projectHouseValue),
                                accent: const Color(0xFF3CC96C),
                                icon: _statusIcon('Total Bill Value'),
                              ),
                              _StatCard(
                                title: 'Payments Made',
                                value: _formatCurrency(paidAmount),
                                accent: const Color(0xFFFF8B2B),
                                icon: _statusIcon('Payments Made'),
                              ),
                              _StatCard(
                                title: 'Total Paid Bills',
                                value: '${paidBills.length} Bills',
                                accent: const Color(0xFF2E52FF),
                                icon: _statusIcon('Total Paid Bills'),
                              ),
                              _StatCard(
                                title: 'Total Pending Bills',
                                value: '${pendingBills.length} Bills',
                                accent: const Color(0xFFFF4D3B),
                                icon: _statusIcon('Total Pending Bills'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Invoice List',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          if (bills.isEmpty)
                            const Text('No invoices yet')
                          else
                            ...bills.map(
                              (bill) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _InvoiceCard(
                                  title: (bill['title'] ?? 'Invoice').toString(),
                                  amount: _formatCurrency((bill['amount'] ?? 0) as num),
                                  projectName: (bill['projectName'] ?? 'Project').toString(),
                                  paidDate: _formatShortDate(bill['paidDate'] as Timestamp?),
                                  status: (bill['status'] ?? 'Pending').toString(),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFE1E2E6),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: Icons.dashboard_outlined,
                label: 'Home',
                selected: _selectedIndex == 0,
                onTap: () => _onTabTap(0),
              ),
              _BottomNavItem(
                icon: Icons.article_outlined,
                label: 'Timeline',
                selected: _selectedIndex == 1,
                onTap: () => _onTabTap(1),
              ),
              _BottomNavItem(
                icon: Icons.receipt_long_outlined,
                label: 'Bills',
                selected: _selectedIndex == 2,
                onTap: () => _onTabTap(2),
              ),
              _BottomNavItem(
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

class _BillsTopBar extends StatelessWidget {
  final String userName;

  const _BillsTopBar({required this.userName});

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
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
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
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              Row(
                children: [
                  Text(userName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Client', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2_outlined, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color accent;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6E758A)),
                ),
              ),
              Icon(icon, size: 14, color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final String title;
  final String amount;
  final String projectName;
  final String paidDate;
  final String status;

  const _InvoiceCard({
    required this.title,
    required this.amount,
    required this.projectName,
    required this.paidDate,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = status.toLowerCase() == 'paid';
    final bg = isPaid ? const Color(0xFFD9F4D8) : const Color(0xFFFFE8D7);
    final fg = isPaid ? const Color(0xFF2E9342) : const Color(0xFFFF8C2D);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                child: Text(status, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(amount, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 2),
          Text(projectName, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 2),
          Text('Paid date: $paidDate', style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BottomNavItem({
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
            Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
