import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_page.dart';
import 'login_page.dart';

class AdminPage extends StatefulWidget {
  final int initialIndex;

  const AdminPage({super.key, this.initialIndex = 2});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int selectedIndex = 2;
  bool isLoggingOut = false;
  String? _processingBookingId;
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

    const firstBill = _FirstBillInput(title: 'Foundation', amount: 150000);

    if (!mounted) return;
    setState(() {
      _processingBookingId = bookingId;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final bookingRef = firestore.collection("bookings").doc(bookingId);
      final bookingSnap = await bookingRef.get();
      final bookingData = bookingSnap.data() ?? <String, dynamic>{};
      final projectRef = firestore.collection('projects').doc(bookingId);
      var contractorUid = (bookingData['contractorUid'] ?? '').toString().trim();
      if (contractorUid.isEmpty) {
        contractorUid = await _resolveDefaultContractorUid(
          firestore,
          contractorEmail: (bookingData['contractorEmail'] ?? '').toString(),
        );
      }

      // Admin action: confirm payment and unlock client project interface.
      await bookingRef.update({
        "paymentConfirmed": true,
        "accessGranted": true,
        "status": "Access Granted",
        "accessGrantedAt": FieldValue.serverTimestamp(),
        "contractorUid": contractorUid,
      });

      await projectRef.set({
        'bookingId': bookingId,
        'houseTitle': (bookingData['houseTitle'] ?? 'Family House').toString(),
        'priceText': (bookingData['priceText'] ?? '').toString(),
        'location': (bookingData['location'] ?? 'Malabe').toString(),
        'clientEmail': (bookingData['userEmail'] ?? '').toString(),
        'clientUid': (bookingData['userId'] ?? '').toString(),
        'contractorUid': contractorUid,
        'startedConstruction': true,
        'startedAt': FieldValue.serverTimestamp(),
        'status': 'In Progress',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await projectRef.collection('bills').doc('initial_payment').set(
        {
          'title': firstBill.title,
          'amount': firstBill.amount,
          'status': 'Paid',
          'projectName': (bookingData['houseTitle'] ?? 'Project').toString(),
          'clientEmail': (bookingData['userEmail'] ?? '').toString(),
          'createdAt': FieldValue.serverTimestamp(),
          'paidDate': FieldValue.serverTimestamp(),
          'source': 'admin_approval',
        },
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
      content = const SizedBox.shrink();
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
              Timestamp? dateTs = data["appointmentDate"] as Timestamp?;
              String dateText = "No date";
              if (dateTs != null) {
                DateTime d = dateTs.toDate();
                dateText = "${d.day}-${d.month}-${d.year}";
              }

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
                    const SizedBox(height: 4),
                    Text("House: ${data["houseTitle"] ?? "-"}"),
                    Text("Phone: ${data["phone"] ?? "-"}"),
                    Text("Appointment Date: $dateText"),
                    Text("Status: ${data["status"] ?? "Pending Approval"}"),
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
      content = Center(
        child: SizedBox(
          width: 220,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: isLoggingOut ? null : _logout,
                icon: const Icon(Icons.logout),
                label: Text(isLoggingOut ? 'Logging out...' : 'Logout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 45),
                ),
              ),
            ],
          ),
        ),
      );
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

  Widget _card(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(text),
    );
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
