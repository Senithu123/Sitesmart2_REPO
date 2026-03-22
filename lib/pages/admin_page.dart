import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_page.dart';
import 'login_page.dart';

class AdminPage extends StatefulWidget {
  final int initialIndex;

  const AdminPage({super.key, this.initialIndex = 0});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int selectedIndex = 0;
  bool isLoggingOut = false;
  String? _processingBookingId;
  String? _processingPaymentBookingId;
  String? _processingUserId;
  static const List<String> _roles = ['Client', 'Contractor', 'Architect', 'Admin'];

  static const List<Map<String, dynamic>> _defaultTimelinePhases = [
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
    selectedIndex = widget.initialIndex;
  }

  Future<void> _logout() async {
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logout failed')),
      );
      setState(() {
        isLoggingOut = false;
      });
    }
  }

  Future<void> _giveAccess(String bookingId) async {
    if (_processingBookingId == bookingId) return;

    if (!mounted) return;
    setState(() {
      _processingBookingId = bookingId;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final bookingRef = firestore.collection("bookings").doc(bookingId);
      final bookingSnap = await bookingRef.get();
      final bookingData = bookingSnap.data() ?? <String, dynamic>{};
      final projectRef = await _ensureProjectForBooking(
        firestore,
        bookingId: bookingId,
        bookingData: bookingData,
        startProject: true,
      );

      // Admin action: confirm payment and unlock client project interface.
      await bookingRef.update({
        "paymentConfirmed": true,
        "accessGranted": true,
        "status": "Access Granted",
        "accessGrantedAt": FieldValue.serverTimestamp(),
        "contractorUid": (bookingData['contractorUid'] ?? '').toString().trim(),
      });

      const firstBill = _FirstBillInput(title: 'Foundation', amount: 150000);
      await projectRef.collection('bills').doc('initial_payment').set(
        {
          'title': firstBill.title,
          'amount': firstBill.amount,
          'status': 'Paid',
          'projectName': (bookingData['houseTitle'] ?? 'Project').toString(),
          'clientEmail': (bookingData['userEmail'] ?? '').toString(),
          'description': 'Initial foundation payment',
          'createdAt': FieldValue.serverTimestamp(),
          'paidDate': FieldValue.serverTimestamp(),
          'source': 'admin_approval',
        },
        SetOptions(merge: true),
      );

      for (final phase in _defaultTimelinePhases) {
        await projectRef.collection('timeline').doc(phase['id']!.toString()).set({
          ...phase,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access granted and project started')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final message = e.message?.trim().isNotEmpty == true
          ? e.message!.trim()
          : 'Database error (${e.code})';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update booking/project: $message')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update booking/project: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingBookingId = null;
        });
      }
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> _ensureProjectForBooking(
    FirebaseFirestore firestore, {
    required String bookingId,
    required Map<String, dynamic> bookingData,
    bool startProject = false,
  }) async {
    final projectRef = firestore.collection('projects').doc(bookingId);
    final projectSnap = await projectRef.get();
    var contractorUid = (bookingData['contractorUid'] ?? '').toString().trim();
    if (contractorUid.isEmpty) {
      contractorUid = await _resolveDefaultContractorUid(
        firestore,
        contractorEmail: (bookingData['contractorEmail'] ?? '').toString(),
      );
    }
    bookingData['contractorUid'] = contractorUid;

    final payload = <String, dynamic>{
      'bookingId': bookingId,
      'houseTitle': (bookingData['houseTitle'] ?? 'Family House').toString(),
      'priceText': (bookingData['priceText'] ?? '').toString(),
      'location': (bookingData['location'] ?? 'Malabe').toString(),
      'clientEmail': (bookingData['userEmail'] ?? '').toString(),
      'clientUid': (bookingData['userId'] ?? '').toString(),
      'contractorUid': contractorUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!projectSnap.exists) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }

    if (startProject) {
      payload['startedConstruction'] = true;
      payload['status'] = 'In Progress';
      if (!projectSnap.exists) {
        payload['startedAt'] = FieldValue.serverTimestamp();
      }
    }

    await projectRef.set(payload, SetOptions(merge: true));
    return projectRef;
  }

  Future<void> _recordAppointmentPayment(
    String bookingId,
    Map<String, dynamic> bookingData,
  ) async {
    if (_processingPaymentBookingId == bookingId) return;

    final result = await _showAppointmentPaymentDialog(
      initialAmount: bookingData['visitPaymentAmount']?.toString() ?? '',
      initialPurpose: (bookingData['visitPaymentPurpose'] ?? '').toString(),
    );
    if (result == null) return;

    if (!mounted) return;
    setState(() => _processingPaymentBookingId = bookingId);

    try {
      final firestore = FirebaseFirestore.instance;
      final bookingRef = firestore.collection('bookings').doc(bookingId);
      final projectRef = await _ensureProjectForBooking(
        firestore,
        bookingId: bookingId,
        bookingData: bookingData,
      );

      final billId = 'appointment_payment_${DateTime.now().millisecondsSinceEpoch}';
      await bookingRef.set({
        'visitPaymentAmount': result.amount,
        'visitPaymentPurpose': result.purpose,
        'visitPaymentStatus': 'Paid',
        'visitPaymentUpdatedAt': FieldValue.serverTimestamp(),
        'lastBillId': billId,
      }, SetOptions(merge: true));

      await projectRef.collection('bills').doc(billId).set({
        'title': 'Appointment Visit Payment',
        'amount': result.amount,
        'status': 'Paid',
        'projectName': (bookingData['houseTitle'] ?? 'Project').toString(),
        'clientEmail': (bookingData['userEmail'] ?? '').toString(),
        'description': result.purpose,
        'billType': 'appointment_payment',
        'bookingId': bookingId,
        'createdAt': FieldValue.serverTimestamp(),
        'paidDate': FieldValue.serverTimestamp(),
        'source': 'appointment_visit',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Visit payment saved and added to bills')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save visit payment: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save visit payment: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingPaymentBookingId = null);
      }
    }
  }

  Future<_AppointmentPaymentResult?> _showAppointmentPaymentDialog({
    String initialAmount = '',
    String initialPurpose = '',
  }) async {
    final amountCtrl = TextEditingController(text: initialAmount);
    final purposeCtrl = TextEditingController(text: initialPurpose);
    String? errorText;

    return showDialog<_AppointmentPaymentResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Record Visit Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount Paid',
                  hintText: 'e.g. 50000',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: purposeCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Money For',
                  hintText: 'e.g. Site visit consultation, design revision fee',
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final normalizedAmount = amountCtrl.text.trim().replaceAll(',', '');
                final amount = num.tryParse(normalizedAmount) ?? 0;
                final purpose = purposeCtrl.text.trim();
                if (amount <= 0 || purpose.isEmpty) {
                  setLocal(() {
                    errorText = 'Enter a valid amount and what the money was for.';
                  });
                  return;
                }

                Navigator.pop(
                  context,
                  _AppointmentPaymentResult(amount: amount, purpose: purpose),
                );
              },
              child: const Text('Save Payment'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _resolveDefaultContractorUid(
    FirebaseFirestore firestore, {
    required String contractorEmail,
  }) async {
    final normalizedEmail = contractorEmail.trim().toLowerCase();
    final contractorSnap = await firestore
        .collection('users')
        .where('role', isEqualTo: 'Contractor')
        .get();
    if (contractorSnap.docs.isEmpty) {
      throw Exception('No contractor account found to assign this project');
    }

    if (normalizedEmail.isNotEmpty) {
      for (final doc in contractorSnap.docs) {
        final email = (doc.data()['email'] ?? '').toString().trim().toLowerCase();
        if (email == normalizedEmail) {
          return doc.id;
        }
      }
    }

    final sortedContractors = contractorSnap.docs.toList()
      ..sort((a, b) {
        final aCreatedAt = a.data()['createdAt'] as Timestamp?;
        final bCreatedAt = b.data()['createdAt'] as Timestamp?;
        final aDate = aCreatedAt?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = bCreatedAt?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    if (sortedContractors.isNotEmpty) {
      return sortedContractors.first.id;
    }

    throw Exception('No contractor account found to assign this project');
  }

  Future<void> _showCreateUserDialog() async {
    final result = await _showUserFormDialog(
      title: 'Create User Profile',
      actionText: 'Create',
    );
    if (result == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').add({
        'fullName': result.fullName,
        'email': result.email.toLowerCase(),
        'role': result.role,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User profile created')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create failed: ${e.message ?? e.code}')),
      );
    }
  }

  Future<void> _showEditUserDialog(
    String userId,
    Map<String, dynamic> data,
  ) async {
    final result = await _showUserFormDialog(
      title: 'Edit User',
      actionText: 'Save',
      initialName: (data['fullName'] ?? data['name'] ?? '').toString(),
      initialEmail: (data['email'] ?? '').toString(),
      initialRole: (data['role'] ?? 'Client').toString(),
    );
    if (result == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'fullName': result.fullName,
        'email': result.email.toLowerCase(),
        'role': result.role,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User updated')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: ${e.message ?? e.code}')),
      );
    }
  }

  Future<void> _deleteUser(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: const Text('Delete this user profile from Firestore?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (!mounted) return;
    setState(() => _processingUserId = userId);
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User deleted')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _processingUserId = null);
    }
  }

  Future<_UserFormResult?> _showUserFormDialog({
    required String title,
    required String actionText,
    String initialName = '',
    String initialEmail = '',
    String initialRole = 'Client',
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    final emailCtrl = TextEditingController(text: initialEmail);
    String role = _roles.contains(initialRole) ? initialRole : 'Client';

    return showDialog<_UserFormResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: role,
                items: _roles
                    .map((r) => DropdownMenuItem<String>(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setLocal(() => role = v);
                },
                decoration: const InputDecoration(labelText: 'Role'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                if (name.isEmpty || email.isEmpty) return;
                Navigator.pop(
                  context,
                  _UserFormResult(fullName: name, email: email, role: role),
                );
              },
              child: Text(actionText),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = const SizedBox();

    if (selectedIndex == 0) {
      content = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, usersSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('bookings').snapshots(),
            builder: (context, bookingsSnapshot) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('projects').snapshots(),
                builder: (context, projectsSnapshot) {
                  if (usersSnapshot.hasError ||
                      bookingsSnapshot.hasError ||
                      projectsSnapshot.hasError) {
                    return const Center(
                      child: Text('Unable to load the admin overview right now'),
                    );
                  }

                  final isLoading =
                      usersSnapshot.connectionState == ConnectionState.waiting ||
                      bookingsSnapshot.connectionState == ConnectionState.waiting ||
                      projectsSnapshot.connectionState == ConnectionState.waiting;

                  if (isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final userDocs = usersSnapshot.data?.docs ?? [];
                  final bookingDocs = bookingsSnapshot.data?.docs ?? [];
                  final projectDocs = projectsSnapshot.data?.docs ?? [];

                  final pendingBookings = bookingDocs
                      .where((doc) => doc.data()['accessGranted'] != true)
                      .length;
                  final approvedBookings = bookingDocs.length - pendingBookings;
                  final activeProjects = projectDocs
                      .where(
                        (doc) =>
                            (doc.data()['status'] ?? '').toString().toLowerCase() !=
                            'completed',
                      )
                      .length;
                  final contractors = userDocs
                      .where(
                        (doc) =>
                            (doc.data()['role'] ?? '').toString().trim() ==
                            'Contractor',
                      )
                      .length;

                  final recentBookings = bookingDocs.toList()
                    ..sort((a, b) {
                      final aDate = (a.data()['createdAt'] as Timestamp?)?.toDate() ??
                          DateTime.fromMillisecondsSinceEpoch(0);
                      final bDate = (b.data()['createdAt'] as Timestamp?)?.toDate() ??
                          DateTime.fromMillisecondsSinceEpoch(0);
                      return bDate.compareTo(aDate);
                    });

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Admin Dashboard',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                pendingBookings > 0
                                    ? '$pendingBookings booking requests still need your attention today.'
                                    : 'Everything looks calm right now. Your main admin tasks are under control.',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: Colors.blueGrey.shade700,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _overviewChip(
                                    icon: Icons.pending_actions_outlined,
                                    label: 'Pending approvals',
                                    value: '$pendingBookings',
                                    color: const Color(0xFFB45309),
                                  ),
                                  _overviewChip(
                                    icon: Icons.fact_check_outlined,
                                    label: 'Approved bookings',
                                    value: '$approvedBookings',
                                    color: const Color(0xFF0F766E),
                                  ),
                                  _overviewChip(
                                    icon: Icons.home_repair_service_outlined,
                                    label: 'Active projects',
                                    value: '$activeProjects',
                                    color: const Color(0xFF1D4ED8),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _infoPanel(
                                title: 'Platform Status',
                                subtitle:
                                    'A simple summary of the current admin workload.',
                                child: Column(
                                  children: [
                                    _metricRow('Total users', '${userDocs.length}'),
                                    _metricRow('Contractors available', '$contractors'),
                                    _metricRow('Total bookings', '${bookingDocs.length}'),
                                    _metricRow('Projects created', '${projectDocs.length}'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _infoPanel(
                          title: 'Recent Requests',
                          subtitle:
                              'The latest bookings appear here for quick review.',
                          child: recentBookings.isEmpty
                              ? Text(
                                  'No booking requests are available yet.',
                                  style: TextStyle(color: Colors.blueGrey.shade700),
                                )
                              : Column(
                                  children: recentBookings.take(3).map((doc) {
                                    final data = doc.data();
                                    final createdAt =
                                        (data['createdAt'] as Timestamp?)?.toDate();
                                    final isApproved = data['accessGranted'] == true;
                                    return Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF7F9FC),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (data['customerName'] ?? 'Customer').toString(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1F2937),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'House: ${(data['houseTitle'] ?? '-').toString()}',
                                            style: TextStyle(color: Colors.blueGrey.shade700),
                                          ),
                                          Text(
                                            'Status: ${isApproved ? 'Access granted' : 'Waiting for approval'}',
                                            style: TextStyle(color: Colors.blueGrey.shade700),
                                          ),
                                          Text(
                                            'Created: ${_formatShortDate(createdAt)}',
                                            style: TextStyle(color: Colors.blueGrey.shade700),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } else if (selectedIndex == 1) {
      content = Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Manage Users',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showCreateUserDialog,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Failed to load users: ${snapshot.error}'));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No users found'));
                }

                docs.sort((a, b) {
                  final aRole = (a.data()['role'] ?? '').toString();
                  final bRole = (b.data()['role'] ?? '').toString();
                  if (aRole != bRole) return aRole.compareTo(bRole);
                  final aName = (a.data()['fullName'] ?? a.data()['name'] ?? '').toString();
                  final bName = (b.data()['fullName'] ?? b.data()['name'] ?? '').toString();
                  return aName.compareTo(bName);
                });

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final name = (data['fullName'] ?? data['name'] ?? 'User').toString();
                    final email = (data['email'] ?? '-').toString();
                    final role = (data['role'] ?? '-').toString();
                    final deleting = _processingUserId == doc.id;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 3),
                          Text(email),
                          const SizedBox(height: 2),
                          Text('Role: $role'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _showEditUserDialog(doc.id, data),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('Edit'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: deleting ? null : () => _deleteUser(doc.id),
                                icon: deleting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.delete_outline, size: 16),
                                label: Text(deleting ? 'Deleting...' : 'Delete'),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      );
    } else if (selectedIndex == 2) {
      // Live list of all booking requests.
      content = StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection("bookings").snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('No bookings yet'),
            );
          }

          List<QueryDocumentSnapshot> docs = snapshot.data!.docs.toList();
          docs.sort((a, b) {
            Map<String, dynamic> da = a.data() as Map<String, dynamic>;
            Map<String, dynamic> db = b.data() as Map<String, dynamic>;
            Timestamp? ta = da["createdAt"] as Timestamp?;
            Timestamp? tb = db["createdAt"] as Timestamp?;
            DateTime aa = ta?.toDate() ?? DateTime(2000);
            DateTime bb = tb?.toDate() ?? DateTime(2000);
            return bb.compareTo(aa);
          });

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              Map<String, dynamic> data = docs[index].data() as Map<String, dynamic>;
              bool accessGranted = data["accessGranted"] == true;
              final bool isProcessing = _processingBookingId == docs[index].id;
              final bool isSavingPayment = _processingPaymentBookingId == docs[index].id;
              Timestamp? dateTs = data["appointmentDate"] as Timestamp?;
              String dateText = "No date";
              if (dateTs != null) {
                DateTime d = dateTs.toDate();
                final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
                final minute = d.minute.toString().padLeft(2, '0');
                final ampm = d.hour >= 12 ? 'PM' : 'AM';
                dateText = "${d.day}-${d.month}-${d.year} $hour:$minute $ampm";
              }
              final visitPaymentAmount = data['visitPaymentAmount'];
              final visitPaymentPurpose = (data['visitPaymentPurpose'] ?? '').toString().trim();
              final visitPaymentStatus = (data['visitPaymentStatus'] ?? 'Not added').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data["customerName"]?.toString() ?? "Customer",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F9FC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Appointment Details',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text("House: ${data["houseTitle"] ?? "-"}"),
                          Text("Phone: ${data["phone"] ?? "-"}"),
                          Text("Appointment Date: $dateText"),
                          Text("Status: ${data["status"] ?? "Pending Approval"}"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAF1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8C8)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Visit Payment',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            visitPaymentAmount == null
                                ? 'Amount Paid: Not recorded'
                                : 'Amount Paid: Rs.${visitPaymentAmount.toString()}',
                          ),
                          Text(
                            visitPaymentPurpose.isEmpty
                                ? 'Money For: Not recorded'
                                : 'Money For: $visitPaymentPurpose',
                          ),
                          Text('Payment Status: $visitPaymentStatus'),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: accessGranted && !isSavingPayment
                                  ? () => _recordAppointmentPayment(docs[index].id, data)
                                  : null,
                              icon: isSavingPayment
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.payments_outlined),
                              label: Text(
                                isSavingPayment
                                    ? 'Saving Payment...'
                                    : (visitPaymentAmount == null
                                        ? 'Add Visit Payment'
                                        : 'Update Visit Payment'),
                              ),
                            ),
                          ),
                          if (!accessGranted)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Grant access first to create the project bill for this appointment.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!accessGranted)
                      // Approve request and give access to customer.
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isProcessing ? null : () => _giveAccess(docs[index].id),
                          icon: isProcessing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.verified_user_outlined),
                          label: Text(
                            isProcessing
                                ? "Processing..."
                                : "Confirm Payment & Give Access",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "Access already given",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      );
    } else {
      content = const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFEFEFF0),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E2BFF),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.admin_panel_settings_outlined, color: Colors.white),
                  SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Site Smart',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Admin',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: content,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black54,
        backgroundColor: const Color(0xFFDADADA),
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
            return;
          }

          setState(() {
            selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: 'Users'),
          BottomNavigationBarItem(icon: Icon(Icons.event_note_outlined), label: 'Appointments'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _overviewChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoPanel({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Colors.blueGrey.shade700,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.blueGrey.shade700),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  String _formatShortDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _FirstBillInput {
  final String title;
  final num amount;

  const _FirstBillInput({
    required this.title,
    required this.amount,
  });
}

class _UserFormResult {
  final String fullName;
  final String email;
  final String role;

  _UserFormResult({
    required this.fullName,
    required this.email,
    required this.role,
  });
}

class _AppointmentPaymentResult {
  final num amount;
  final String purpose;

  const _AppointmentPaymentResult({
    required this.amount,
    required this.purpose,
  });
}
