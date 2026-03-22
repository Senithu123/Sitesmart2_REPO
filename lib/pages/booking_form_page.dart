import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'booking_confirmation_page.dart';

class BookingFormPage extends StatefulWidget {
  final String houseId;
  final String houseTitle;
  final String priceText;

  const BookingFormPage({
    super.key,
    required this.houseId,
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
  TimeOfDay? selectedTime;
  bool isSaving = false;
  String userEmail = "";
  final TextEditingController appointmentCtrl = TextEditingController();

  static const String _workingHoursLabel = "Work hours: Mon-Sat, 9:00 AM - 5:00 PM";

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
    appointmentCtrl.dispose();
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

  bool _isWorkingDay(DateTime date) {
    return date.weekday >= DateTime.monday && date.weekday <= DateTime.saturday;
  }

  DateTime _nextWorkingDate(DateTime from) {
    var candidate = DateTime(from.year, from.month, from.day).add(const Duration(days: 1));
    while (!_isWorkingDay(candidate)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  bool _isWithinWorkingHours(TimeOfDay time) {
    final totalMinutes = time.hour * 60 + time.minute;
    const startMinutes = 9 * 60;
    const endMinutes = 17 * 60;
    return totalMinutes >= startMinutes && totalMinutes <= endMinutes;
  }

  String _formatAppointmentDateTime(DateTime? date) {
    if (date == null) {
      return "Select appointment date and time";
    }

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
    final hour = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.day} ${months[date.month - 1]} ${date.year} at $hour:$minute $ampm';
  }

  Future<void> pickDateTime() async {
    // Let customer pick an appointment date and time within working hours.
    FocusScope.of(context).unfocus();

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final initialDate = selectedDate != null
          ? DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day)
          : _nextWorkingDate(now);

      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: today,
        lastDate: today.add(const Duration(days: 365)),
        selectableDayPredicate: _isWorkingDay,
      );
      if (picked == null) return;

      if (!_isWorkingDay(picked)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Appointments are available only from Monday to Saturday.")),
        );
        return;
      }

      final initialTime = selectedTime ??
          const TimeOfDay(
            hour: 9,
            minute: 0,
          );

      final pickedTime = await showTimePicker(
        context: context,
        initialTime: initialTime,
        helpText: 'Select appointment time',
      );

      if (pickedTime == null) return;

      if (!_isWithinWorkingHours(pickedTime)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please choose a time between 9:00 AM and 5:00 PM.")),
        );
        return;
      }

      setState(() {
        selectedTime = pickedTime;
        selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        appointmentCtrl.text = _formatAppointmentDateTime(selectedDate);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open date and time picker: $e")),
      );
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
      final bookingRef = await FirebaseFirestore.instance.collection("bookings").add({
        "userId": user.uid,
        "userEmail": userEmail,
        "customerName": nameCtrl.text.trim(),
        "houseId": widget.houseId,
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
        MaterialPageRoute(
          builder: (context) => BookingConfirmationPage(
            bookingId: bookingRef.id,
            meetingDate: selectedDate,
            houseTitle: widget.houseTitle,
            openWaitingPageOnDone: true,
          ),
        ),
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
    appointmentCtrl.text = _formatAppointmentDateTime(selectedDate);

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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE9F1FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFB8CBFF)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.access_time, color: Color(0xFF1E2BFF)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _workingHoursLabel,
                      style: TextStyle(
                        color: Color(0xFF17308A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: appointmentCtrl,
              readOnly: true,
              onTap: pickDateTime,
              decoration: const InputDecoration(
                labelText: "Appointment Date & Time *",
                hintText: "Select appointment date and time",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_month_outlined),
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
