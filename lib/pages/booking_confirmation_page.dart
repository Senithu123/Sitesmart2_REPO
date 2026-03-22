import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'project_waiting_page.dart';

class BookingConfirmationPage extends StatefulWidget {
  final String? bookingId;
  final DateTime? meetingDate;
  final String houseTitle;
  final bool openWaitingPageOnDone;

  const BookingConfirmationPage({
    super.key,
    this.bookingId,
    required this.meetingDate,
    required this.houseTitle,
    this.openWaitingPageOnDone = false,
  });

  @override
  State<BookingConfirmationPage> createState() => _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<BookingConfirmationPage> {
  DateTime? _meetingDate;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _meetingDate = widget.meetingDate;
  }

  String _formatMeetingDate(DateTime? date) {
    if (date == null) return 'Your booked meeting time will be shared by our team.';
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
    return '${date.day} ${months[date.month - 1]} ${date.year}, $hour:$minute $ampm';
  }

  void _handleDone(BuildContext context) {
    if (widget.openWaitingPageOnDone) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ProjectWaitingPage()),
        (route) => false,
      );
      return;
    }

    Navigator.pop(context);
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

  Future<void> _editBookingTime() async {
    if (widget.bookingId == null || _updating) return;

    FocusScope.of(context).unfocus();

    late final DateTime scheduledAt;
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final initialDate = _meetingDate != null
          ? DateTime(_meetingDate!.year, _meetingDate!.month, _meetingDate!.day)
          : _nextWorkingDate(now);

      final date = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: today,
        lastDate: today.add(const Duration(days: 365)),
        selectableDayPredicate: _isWorkingDay,
      );
      if (date == null) return;

      final initialTime = _meetingDate != null
          ? TimeOfDay.fromDateTime(_meetingDate!)
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
      setState(() {
        _meetingDate = scheduledAt;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking time updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update booking time: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Booking Confirmation'),
        backgroundColor: const Color(0xFF1E2BFF),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDCE1EE)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8ECF8),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.event_available_outlined,
                    size: 34,
                    color: Color(0xFF1E2BFF),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Booking Confirmed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF171C2C),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your meeting for ${widget.houseTitle} has been arranged. You may meet our team on the scheduled time below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Meeting Time',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5B678D),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatMeetingDate(_meetingDate),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF171C2C),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (widget.bookingId != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _updating ? null : _editBookingTime,
                      icon: _updating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_calendar),
                      label: Text(_updating ? 'Updating...' : 'Edit Booking Time'),
                    ),
                  ),
                if (widget.bookingId != null) const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _handleDone(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E2BFF),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 46),
                    ),
                    child: const Text('Done'),
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
