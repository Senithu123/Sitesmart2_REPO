import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'project_waiting_page.dart';

class BookingFormPage extends StatefulWidget {
  final String houseTitle;
  final String priceText;

  const BookingFormPage({
    super.key,
    required this.houseTitle,
    required this.priceText,
  });

  @override
  State<BookingFormPage> createState() => _BookingFormPageState();
}

class _BookingFormPageState extends State<BookingFormPage> {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();

  DateTime? selectedDate;
  bool isSaving = false;
  String userEmail = "";

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  Future<void> loadUserData() async {
    try {
      // Prefill customer name/email from logged-in account.
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      userEmail = user.email ?? "";
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection("users").doc(user.uid).get();
      Map<String, dynamic> data = (userDoc.data() as Map<String, dynamic>?) ?? {};

      String fallbackName = user.email?.split("@").first ?? "Customer";
      String fullName = (data["fullName"] ?? data["name"] ?? fallbackName).toString();

      if (!mounted) return;
      setState(() {
        nameCtrl.text = fullName;
      });
    } catch (_) {}
  }

  Future<void> pickDate() async {
    // Let customer pick an appointment date.
    DateTime now = DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Future<void> submitBooking() async {
    // Basic form validation.
    if (nameCtrl.text.trim().isEmpty ||
        phoneCtrl.text.trim().isEmpty ||
        selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required details")),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not logged in");
      }

      // Save booking with "pending" status until admin approves.
      await FirebaseFirestore.instance.collection("bookings").add({
        "userId": user.uid,
        "userEmail": userEmail,
        "customerName": nameCtrl.text.trim(),
        "phone": phoneCtrl.text.trim(),
        "houseTitle": widget.houseTitle,
        "priceText": widget.priceText,
        "appointmentDate": Timestamp.fromDate(selectedDate!),
        "notes": notesCtrl.text.trim(),
        "status": "Pending Approval",
        "paymentConfirmed": false,
        "accessGranted": false,
        "createdAt": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Booking added successfully")),
      );

      Navigator.pushAndRemoveUntil(
        context,
        // After booking, move customer to waiting interface.
        MaterialPageRoute(builder: (context) => const ProjectWaitingPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save booking: $e")),
      );
      setState(() {
        isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String dateText = selectedDate == null
        ? "Select appointment date"
        : "${selectedDate!.day}-${selectedDate!.month}-${selectedDate!.year}";

    return Scaffold(
      backgroundColor: const Color(0xFFEFEFF0),
      appBar: AppBar(
        title: const Text("Book Appointment"),
        backgroundColor: const Color(0xFF1E2BFF),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.houseTitle,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.priceText,
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: "Full Name *",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "Phone Number *",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined),
                    const SizedBox(width: 8),
                    Text(dateText),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: "Extra notes (optional)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: isSaving ? null : submitBooking,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(isSaving ? "Saving..." : "Submit Booking"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
