import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_reports_page.dart';
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
    {
      'id': 'finishing_work',
      'order': 4,
      'title': 'Finishing Work',
      'dateRange': 'Jan 1 - Jan 20',
      'percentage': 0,
      'tasksCompleted': 0,
      'totalTasks': 4,
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
      'houseId': (bookingData['houseId'] ?? '').toString(),
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

  Widget _buildAdminOverview() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

                return _buildAdminOverviewContent(
                  userDocs: userDocs,
                  bookingDocs: bookingDocs,
                  projectDocs: projectDocs,
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = const SizedBox();

    if (selectedIndex == 0) {
      content = _buildAdminOverview();
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
    } else if (selectedIndex == 3) {
      content = const AdminReportsPage();
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
          if (index == 4) {
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
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
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

  Future<_AdminOverviewData> _loadAdminOverviewData({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> userDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> bookingDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> projectDocs,
  }) async {
    final bookingsById = <String, Map<String, dynamic>>{
      for (final doc in bookingDocs) doc.id: doc.data(),
    };
    final usersByUid = <String, Map<String, dynamic>>{
      for (final doc in userDocs) doc.id: doc.data(),
    };

    final reports = await Future.wait(
      projectDocs.map(
        (projectDoc) async {
          final data = projectDoc.data();
          final bookingId = (data['bookingId'] ?? projectDoc.id).toString();
          final bookingData = bookingsById[bookingId] ?? <String, dynamic>{};
          final clientUid = (data['clientUid'] ?? bookingData['userId'] ?? '').toString();
          final userData = usersByUid[clientUid] ?? <String, dynamic>{};

          final billsSnap = await projectDoc.reference.collection('bills').get();
          final timelineSnap = await projectDoc.reference.collection('timeline').get();

          num paidAmount = 0;
          DateTime? lastPaymentAt;
          for (final billDoc in billsSnap.docs) {
            final billData = billDoc.data();
            final status = (billData['status'] ?? '').toString().toLowerCase();
            if (status != 'paid') continue;

            final amount = (billData['amount'] is num)
                ? billData['amount'] as num
                : num.tryParse((billData['amount'] ?? '0').toString()) ?? 0;
            paidAmount += amount;

            final paidDate = _readDate(billData['paidDate'] ?? billData['createdAt']);
            if (lastPaymentAt == null || (paidDate != null && paidDate.isAfter(lastPaymentAt))) {
              lastPaymentAt = paidDate;
            }
          }

          int progressSum = 0;
          int phaseCount = 0;
          int completedPhases = 0;
          int totalImages = 0;
          for (final timelineDoc in timelineSnap.docs) {
            final timelineData = timelineDoc.data();
            final percentage = ((timelineData['percentage'] ?? 0) as num).toInt();
            final imageCount = ((timelineData['imageCount'] ?? 0) as num).toInt();
            final phaseStatus = (timelineData['status'] ?? '').toString().toLowerCase();

            progressSum += percentage;
            phaseCount += 1;
            totalImages += imageCount;
            if (phaseStatus == 'done' || percentage >= 100) {
              completedPhases += 1;
            }
          }

          final clientName = (bookingData['customerName'] ??
                  userData['fullName'] ??
                  userData['name'] ??
                  'Customer')
              .toString();
          final clientEmail =
              (data['clientEmail'] ?? bookingData['userEmail'] ?? userData['email'] ?? '-').toString();
          final houseTitle = (data['houseTitle'] ?? bookingData['houseTitle'] ?? 'Project').toString();
          final location = (data['location'] ?? bookingData['location'] ?? '-').toString();
          final houseValue = _parseMoneyValue(data['priceText'] ?? bookingData['priceText']);
          final outstandingAmount = (houseValue - paidAmount) < 0 ? 0 : (houseValue - paidAmount);
          final progressPercent = phaseCount == 0 ? 0 : (progressSum / phaseCount).round();

          return _AdminProjectReport(
            projectId: projectDoc.id,
            clientName: clientName,
            clientEmail: clientEmail,
            houseTitle: houseTitle,
            location: location,
            status: (data['status'] ?? 'In Progress').toString(),
            houseValue: houseValue,
            paidAmount: paidAmount,
            outstandingAmount: outstandingAmount,
            progressPercent: progressPercent,
            completedPhases: completedPhases,
            totalPhases: phaseCount == 0 ? _defaultTimelinePhases.length : phaseCount,
            totalImages: totalImages,
            startedAt: _readDate(data['startedAt'] ?? bookingData['accessGrantedAt']),
            lastUpdatedAt: _readDate(data['timelineLastUpdatedAt'] ?? data['updatedAt'] ?? data['createdAt']),
            lastPaymentAt: lastPaymentAt,
          );
        },
      ),
    );

    reports.sort((a, b) {
      final aDate = a.lastUpdatedAt ?? a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.lastUpdatedAt ?? b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    final totalCollected = reports.fold<num>(0, (sum, report) => sum + report.paidAmount);
    final totalOutstanding = reports.fold<num>(0, (sum, report) => sum + report.outstandingAmount);
    final averageProgress = reports.isEmpty
        ? 0
        : (reports.fold<int>(0, (sum, report) => sum + report.progressPercent) / reports.length).round();
    final paidCustomers = reports.where((report) => report.paidAmount > 0).length;
    final completedProjects = reports
        .where((report) => report.status.toLowerCase() == 'completed' || report.progressPercent >= 100)
        .length;
    final halfwayProjects = reports
        .where((report) => report.progressPercent >= 50 && report.progressPercent < 100)
        .length;

    return _AdminOverviewData(
      totalCollected: totalCollected,
      totalOutstanding: totalOutstanding,
      averageProgress: averageProgress,
      paidCustomers: paidCustomers,
      completedProjects: completedProjects,
      halfwayProjects: halfwayProjects,
      reports: reports,
    );
  }

  Widget _buildAdminOverviewContent({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> userDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> bookingDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> projectDocs,
  }) {
    final pendingBookings = bookingDocs.where((doc) => doc.data()['accessGranted'] != true).length;
    final approvedBookings = bookingDocs.length - pendingBookings;
    final activeProjects = projectDocs
        .where((doc) => (doc.data()['status'] ?? '').toString().toLowerCase() != 'completed')
        .length;
    final contractors = userDocs
        .where((doc) => (doc.data()['role'] ?? '').toString().trim() == 'Contractor')
        .length;

    final recentBookings = bookingDocs.toList()
      ..sort((a, b) {
        final aDate = _readDate(a.data()['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = _readDate(b.data()['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
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
          _infoPanel(
            title: 'Platform Status',
            subtitle: 'A simple summary of the current admin workload.',
            child: Column(
              children: [
                _metricRow('Total users', '${userDocs.length}'),
                _metricRow('Contractors available', '$contractors'),
                _metricRow('Total bookings', '${bookingDocs.length}'),
                _metricRow('Projects created', '${projectDocs.length}'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _infoPanel(
            title: 'Recent Requests',
            subtitle: 'The latest bookings appear here for quick review.',
            child: recentBookings.isEmpty
                ? Text(
                    'No booking requests are available yet.',
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  )
                : Column(
                    children: recentBookings.take(3).map((doc) {
                      final data = doc.data();
                      final createdAt = _readDate(data['createdAt']);
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
  }

  Widget _buildAdminReportsPage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  return const Center(child: Text('Unable to load reports right now'));
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

                return FutureBuilder<_AdminOverviewData>(
                  future: _loadAdminOverviewData(
                    userDocs: userDocs,
                    bookingDocs: bookingDocs,
                    projectDocs: projectDocs,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Unable to load reports right now\n${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    return _buildAdminReportsContent(snapshot.data!);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAdminReportsContent(_AdminOverviewData overview) {
    final progressLeaders = overview.reports.toList()
      ..sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
    final paymentLeaders = overview.reports.toList()
      ..sort((a, b) => b.paidAmount.compareTo(a.paidAmount));
    final collectionMax = [
      overview.totalCollected,
      overview.totalOutstanding,
    ].fold<num>(1, (max, value) => value > max ? value : max);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoPanel(
            title: 'Reports',
            subtitle: 'Visual dashboards for customer payments, construction progress, and overall portfolio health.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _overviewChip(
                  icon: Icons.payments_outlined,
                  label: 'Total collected',
                  value: _formatCurrency(overview.totalCollected),
                  color: const Color(0xFF166534),
                ),
                _overviewChip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Outstanding',
                  value: _formatCurrency(overview.totalOutstanding),
                  color: const Color(0xFFB45309),
                ),
                _overviewChip(
                  icon: Icons.trending_up_outlined,
                  label: 'Average progress',
                  value: '${overview.averageProgress}%',
                  color: const Color(0xFF1D4ED8),
                ),
                _overviewChip(
                  icon: Icons.verified_outlined,
                  label: 'Completed projects',
                  value: '${overview.completedProjects}',
                  color: const Color(0xFF0F766E),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _infoPanel(
            title: 'Collections Graph',
            subtitle: 'Compare received payments against the value that is still outstanding.',
            child: Column(
              children: [
                _graphBarRow(
                  label: 'Collected',
                  valueLabel: _formatCurrency(overview.totalCollected),
                  ratio: collectionMax == 0 ? 0 : overview.totalCollected / collectionMax,
                  color: const Color(0xFF15803D),
                ),
                _graphBarRow(
                  label: 'Outstanding',
                  valueLabel: _formatCurrency(overview.totalOutstanding),
                  ratio: collectionMax == 0 ? 0 : overview.totalOutstanding / collectionMax,
                  color: const Color(0xFFB45309),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _infoPanel(
            title: 'Progress Graph',
            subtitle: 'Top customer projects by construction completion.',
            child: progressLeaders.isEmpty
                ? Text(
                    'No active project data yet.',
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  )
                : Column(
                    children: progressLeaders
                        .take(6)
                        .map(
                          (report) => _graphBarRow(
                            label: report.houseTitle,
                            caption: report.clientName,
                            valueLabel: '${report.progressPercent}%',
                            ratio: report.progressPercent / 100,
                            color: const Color(0xFF1D4ED8),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 14),
          _infoPanel(
            title: 'Payments By Customer',
            subtitle: 'See which customers have paid the most relative to their project value.',
            child: paymentLeaders.isEmpty
                ? Text(
                    'No payment records yet.',
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  )
                : Column(
                    children: paymentLeaders
                        .take(6)
                        .map(
                          (report) => _graphBarRow(
                            label: report.clientName,
                            caption: report.houseTitle,
                            valueLabel: _formatCurrency(report.paidAmount),
                            ratio: report.houseValue <= 0 ? 0 : (report.paidAmount / report.houseValue).clamp(0, 1),
                            color: const Color(0xFF7C3AED),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 14),
          _infoPanel(
            title: 'Detailed Customer Reports',
            subtitle: 'Drill into the exact amount paid, remaining balance, progress, and recent activity for each project.',
            child: overview.reports.isEmpty
                ? Text(
                    'No project reports are available yet.',
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  )
                : Column(
                    children: overview.reports.map((report) => _projectReportCard(report)).toList(),
                  ),
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

  Widget _graphBarRow({
    required String label,
    required String valueLabel,
    required num ratio,
    required Color color,
    String? caption,
  }) {
    final safeRatio = ratio.clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    if (caption != null && caption.isNotEmpty)
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                valueLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: safeRatio,
              minHeight: 12,
              backgroundColor: const Color(0xFFE4E8F1),
              color: color,
            ),
          ),
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

  Widget _projectReportCard(_AdminProjectReport report) {
    final statusColor = report.status.toLowerCase() == 'completed'
        ? const Color(0xFF15803D)
        : (report.progressPercent >= 50 ? const Color(0xFF1D4ED8) : const Color(0xFFB45309));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.clientName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      report.clientEmail,
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  report.status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            report.houseTitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Location: ${report.location}',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: report.progressPercent / 100,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: const Color(0xFFDCE3F2),
            color: statusColor,
          ),
          const SizedBox(height: 8),
          Text(
            'Progress: ${report.progressPercent}%  •  Completed phases: ${report.completedPhases}/${report.totalPhases}',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _reportStatPill(
                icon: Icons.payments_outlined,
                label: 'Paid',
                value: _formatCurrency(report.paidAmount),
                color: const Color(0xFF166534),
              ),
              _reportStatPill(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Remaining',
                value: _formatCurrency(report.outstandingAmount),
                color: const Color(0xFFB45309),
              ),
              _reportStatPill(
                icon: Icons.home_work_outlined,
                label: 'House Value',
                value: _formatCurrency(report.houseValue),
                color: const Color(0xFF1D4ED8),
              ),
              _reportStatPill(
                icon: Icons.photo_library_outlined,
                label: 'Timeline Photos',
                value: '${report.totalImages}',
                color: const Color(0xFF7C3AED),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              _metricRow('Project ID', report.projectId),
              _metricRow('Started', _formatShortDate(report.startedAt)),
              _metricRow('Last payment', _formatShortDate(report.lastPaymentAt)),
              _metricRow('Last update', _formatShortDate(report.lastUpdatedAt)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reportStatPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _readDate(dynamic value) {
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

  num _parseMoneyValue(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return 0;
    final sanitized = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    return num.tryParse(sanitized) ?? 0;
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

  String _formatShortDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _AdminProjectReport {
  final String projectId;
  final String clientName;
  final String clientEmail;
  final String houseTitle;
  final String location;
  final String status;
  final num houseValue;
  final num paidAmount;
  final num outstandingAmount;
  final int progressPercent;
  final int completedPhases;
  final int totalPhases;
  final int totalImages;
  final DateTime? startedAt;
  final DateTime? lastUpdatedAt;
  final DateTime? lastPaymentAt;

  const _AdminProjectReport({
    required this.projectId,
    required this.clientName,
    required this.clientEmail,
    required this.houseTitle,
    required this.location,
    required this.status,
    required this.houseValue,
    required this.paidAmount,
    required this.outstandingAmount,
    required this.progressPercent,
    required this.completedPhases,
    required this.totalPhases,
    required this.totalImages,
    required this.startedAt,
    required this.lastUpdatedAt,
    required this.lastPaymentAt,
  });
}

class _AdminOverviewData {
  final num totalCollected;
  final num totalOutstanding;
  final int averageProgress;
  final int paidCustomers;
  final int completedProjects;
  final int halfwayProjects;
  final List<_AdminProjectReport> reports;

  const _AdminOverviewData({
    required this.totalCollected,
    required this.totalOutstanding,
    required this.averageProgress,
    required this.paidCustomers,
    required this.completedProjects,
    required this.halfwayProjects,
    required this.reports,
  });
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
