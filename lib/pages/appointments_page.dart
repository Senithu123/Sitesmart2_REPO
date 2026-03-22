import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AppointmentsPage extends StatefulWidget {
  final String? bookingId;
  final String projectName;
  final DateTime? appointmentDate;
  final String status;

  const AppointmentsPage({
    super.key,
    required this.bookingId,
    required this.projectName,
    required this.appointmentDate,
    required this.status,
  });

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  bool _updating = false;
  static const String _workingHoursLabel = 'Work hours: Mon-Sat, 9:00 AM - 5:00 PM';

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

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not scheduled';
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

    final h = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.day} ${months[date.month - 1]} ${date.year}, $h:$minute $ampm';
  }

  Future<void> _reschedule() async {
    if (widget.bookingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No booking found to update.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    late final DateTime scheduledAt;
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final initialDate = widget.appointmentDate != null
          ? DateTime(
              widget.appointmentDate!.year,
              widget.appointmentDate!.month,
              widget.appointmentDate!.day,
            )
          : _nextWorkingDate(now);

      final date = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: today,
        lastDate: today.add(const Duration(days: 365)),
        selectableDayPredicate: _isWorkingDay,
      );

      if (date == null) return;

      final initialTime = widget.appointmentDate != null
          ? TimeOfDay.fromDateTime(widget.appointmentDate!)
          : const TimeOfDay(hour: 9, minute: 0);

      final time = await showTimePicker(
        context: context,
        initialTime: initialTime,
        helpText: 'Select appointment time',
      );

      if (time == null) return;

      if (!_isWithinWorkingHours(time)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose a time between 9:00 AM and 5:00 PM.')),
        );
        return;
      }

      scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open date and time picker: $e")),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _updating = true);

    try {
      await FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId).update({
        'appointmentDate': Timestamp.fromDate(scheduledAt),
        'status': 'Rescheduled',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment rescheduled successfully.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reschedule appointment: $e')),
      );
      setState(() => _updating = false);
    }
  }

  Future<void> _cancelAppointment() async {
    if (widget.bookingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No booking found to cancel.')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _updating = true);

    try {
      await FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId).update({
        'status': 'Cancelled',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment cancelled successfully.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel appointment: $e')),
      );
      setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        backgroundColor: const Color(0xFF2537FF),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD9E0EF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.projectName,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_formatDate(widget.appointmentDate))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Status: ${widget.status}')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.access_time, size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text(_workingHoursLabel)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _updating ? null : _reschedule,
                icon: const Icon(Icons.edit_calendar),
                label: Text(_updating ? 'Updating...' : 'Reschedule Appointment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C42F2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _updating ? null : _cancelAppointment,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel Appointment'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
