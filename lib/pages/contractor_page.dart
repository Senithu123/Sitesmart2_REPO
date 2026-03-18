import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'contractor_project_update_page.dart';
import 'profile_page.dart';

class ContractorPage extends StatefulWidget {
  const ContractorPage({super.key});

  @override
  State<ContractorPage> createState() => _ContractorPageState();
}

class _ContractorPageState extends State<ContractorPage> {
  int selectedTab = 0;
  bool _creatingDemo = false;

  Future<void> _createDemoProject() async {
    if (_creatingDemo) return;
    setState(() => _creatingDemo = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('You must be logged in');
      }
      final now = DateTime.now();
      final ref = await FirebaseFirestore.instance.collection('projects').add({
        'houseTitle': 'Modern Family House',
        'location': 'Malabe',
        'clientEmail': 'client@gmail.com',
        'clientUid': '',
        'contractorUid': currentUser.uid,
        'startedConstruction': true,
        'startedAt': Timestamp.fromDate(now),
        'status': 'In Progress',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final batch = FirebaseFirestore.instance.batch();
      final timeline =
          FirebaseFirestore.instance.collection('projects').doc(ref.id).collection('timeline');

      final phases = [
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

      for (final p in phases) {
        batch.set(timeline.doc(p['id']!.toString()), {
          ...p,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        });
      }
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo started house created in backend')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create demo project: $e')),
      );
    } finally {
      if (mounted) setState(() => _creatingDemo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: currentUser == null
              ? const Center(child: Text('Please log in again'))
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('projects')
                .where('startedConstruction', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Started Houses',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE5E5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFB3B3)),
                      ),
                      child: Text('Firestore error: ${snapshot.error}'),
                    ),
                  ],
                );
              }

              final projects = snapshot.data?.docs ?? [];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Started Houses',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select a house and update timeline progress',
                    style: TextStyle(color: Color(0xFF5E667D)),
                  ),
                  const SizedBox(height: 10),
                  if (projects.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFE69C)),
                      ),
                      child: const Text(
                        'No started houses in backend. Create one and update it.',
                      ),
                    ),
                  if (projects.isEmpty) const SizedBox(height: 8),
                  if (projects.isEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _creatingDemo ? null : _createDemoProject,
                        icon: const Icon(Icons.add_home_work_outlined),
                        label: Text(_creatingDemo
                            ? 'Creating...'
                            : 'Create Started House (Backend)'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: projects.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final doc = projects[index];
                        final data = doc.data();
                        final title = (data['houseTitle'] ?? 'House').toString();
                        final location = (data['location'] ?? '-').toString();
                        final status = (data['status'] ?? 'In Progress').toString();
                        final clientEmail = (data['clientEmail'] ?? '-').toString();

                        return InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ContractorProjectUpdatePage(
                                  projectId: doc.id,
                                  houseTitle: title,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFD8DDE8)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('Location: $location'),
                                Text('Client: $clientEmail'),
                                Text('Status: $status'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFFDADADA),
        currentIndex: selectedTab,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black54,
        onTap: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfilePage()),
            );
            return;
          }
          setState(() {
            selectedTab = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
