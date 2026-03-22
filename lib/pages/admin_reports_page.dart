import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminReportsPage extends StatelessWidget {
  const AdminReportsPage({super.key});

  static const List<Map<String, dynamic>> _defaultTimelinePhases = [
    {'id': 'site_preparation'},
    {'id': 'foundation_work'},
    {'id': 'structural_work'},
    {'id': 'finishing_work'},
  ];

  @override
  Widget build(BuildContext context) {
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

                    return _buildReportsContent(context, snapshot.data!);
                  },
                );
              },
            );
          },
        );
      },
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
      projectDocs.map((projectDoc) async {
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
      }),
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

  Widget _buildReportsContent(BuildContext context, _AdminOverviewData overview) {
    final progressLeaders = overview.reports.toList()
      ..sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
    final paymentLeaders = overview.reports.toList()
      ..sort((a, b) => b.paidAmount.compareTo(a.paidAmount));
    final collectionMax = [overview.totalCollected, overview.totalOutstanding]
        .fold<num>(1, (max, value) => value > max ? value : max);

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
                    children: overview.reports.map(_projectReportCard).toList(),
                  ),
          ),
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
