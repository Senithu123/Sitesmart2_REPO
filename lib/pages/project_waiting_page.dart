import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'client_project_page.dart';

class ProjectWaitingPage extends StatefulWidget {
  const ProjectWaitingPage({super.key});

  @override
  State<ProjectWaitingPage> createState() => _ProjectWaitingPageState();
}

class _ProjectWaitingPageState extends State<ProjectWaitingPage> {
  bool checking = false;

  Future<void> refreshStatus() async {
    // Re-check latest booking status to see if admin granted access.
    if (checking) return;
    setState(() {
      checking = true;
    });

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      QuerySnapshot snap = await FirebaseFirestore.instance
          .collection("bookings")
          .where("userId", isEqualTo: currentUser.uid)
          .get();

      if (snap.docs.isEmpty) return;

      QueryDocumentSnapshot? latestDoc;
      DateTime? latestDate;
      for (var doc in snap.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        Timestamp? ts = data["createdAt"] as Timestamp?;
        DateTime d = ts?.toDate() ?? DateTime(2000);
        if (latestDate == null || d.isAfter(latestDate)) {
          latestDate = d;
          latestDoc = doc;
        }
      }

      Map<String, dynamic> latest =
          (latestDoc?.data() as Map<String, dynamic>?) ?? {};
      bool accessGranted = latest["accessGranted"] == true;

      if (!mounted) return;
      if (accessGranted) {
        // If approved, move to project interface.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ClientProjectPage()),
        );
      } else {
        // Still waiting for admin approval.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Still waiting for admin approval")),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to refresh status")),
      );
    } finally {
      if (mounted) {
        setState(() {
          checking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFF0),
      appBar: AppBar(
        title: const Text("Project Started"),
        backgroundColor: const Color(0xFF1E2BFF),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.handshake_outlined,
                  size: 62,
                  color: Color(0xFF1E2BFF),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Thank You For Choosing Us",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Your booking was submitted successfully.\nPlease visit us on the appointment day. After payment confirmation by the admin team, access to the rest of the project features will be enabled.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: checking ? null : refreshStatus,
                    icon: const Icon(Icons.refresh),
                    label: Text(checking ? "Checking..." : "Refresh Status"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
