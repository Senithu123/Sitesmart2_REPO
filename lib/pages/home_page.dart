import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/default_house_listings.dart';
import '../models/house_listing.dart';
import 'client_project_page.dart';
import 'house_detail_page.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}
// Implemented role based Navigation  control

class _HomePageState extends State<HomePage> {
  int selectedTab = 0;
  final TextEditingController searchCtrl = TextEditingController();

  String userName = "";
  String userRole = "";

  @override
  void initState() {
    super.initState();
    loadUserData();
    checkAndRedirectProjectFlow();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> loadUserData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        setState(() {
          userName = "User";
          userRole = "Client";
        });
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(currentUser.uid)
          .get();
      final data = (userDoc.data() as Map<String, dynamic>?) ?? {};
      final fallbackName = currentUser.email?.split("@").first ?? "User";

      if (!mounted) return;
      setState(() {
        userName = (data["fullName"] ?? data["name"] ?? fallbackName).toString();
        userRole = (data["role"] ?? "Client").toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        userName = "User";
        userRole = "Client";
      });
    }
  }

  Future<void> checkAndRedirectProjectFlow() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final firestore = FirebaseFirestore.instance;
      final snap = await firestore
          .collection("bookings")
          .where("userId", isEqualTo: currentUser.uid)
          .get();

      if (!mounted || snap.docs.isEmpty) return;

      QueryDocumentSnapshot? latestDoc;
      DateTime? latestDate;
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = data["createdAt"] as Timestamp?;
        final date = ts?.toDate() ?? DateTime(2000);
        if (latestDate == null || date.isAfter(latestDate)) {
          latestDate = date;
          latestDoc = doc;
        }
      }

      final latest = (latestDoc?.data() as Map<String, dynamic>?) ?? {};
      final accessGranted = latest["accessGranted"] == true;
      if (latestDoc == null || !accessGranted) {
        return;
      }

      final projectSnap = await firestore.collection('projects').doc(latestDoc.id).get();
      if (!projectSnap.exists) {
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const ClientProjectPage(),
        ),
      );
    } catch (_) {}
  }

  List<HouseListing> _filterListings(List<HouseListing> listings) {
    final query = searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      return listings;
    }

    return listings.where((listing) {
      final searchableText = [
        listing.houseName,
        listing.priceText,
        listing.detail,
        listing.location,
        listing.about,
        listing.bedrooms,
        listing.bathrooms,
        listing.sqft,
        listing.vrUrl,
        ...listing.features,
      ].join(' ').toLowerCase();

      return searchableText.contains(query);
    }).toList();
  }

  List<HouseListing> _mergeListings(List<HouseListing> firestoreListings) {
    final merged = <String, HouseListing>{
      for (final listing in defaultHouseListings) listing.id: listing,
    };

    for (final listing in firestoreListings) {
      merged[listing.id] = listing;
    }

    return merged.values.toList();
  }

  Widget _listingImage(HouseListing listing) {
    if (listing.galleryPaths.isNotEmpty) {
      final path = listing.galleryPaths.first;
      if (kIsWeb) {
        return Image.network(
          path,
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _imageFallback(),
        );
      }
      return Image.file(
        File(path),
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _imageFallback(),
      );
    }

    if (listing.hasNetworkImage) {
      return Image.network(
        listing.imageUrl,
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _imageFallback(),
      );
    }

    return Image.asset(
      listing.imagePath,
      height: 180,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _imageFallback(),
    );
  }

  Widget _imageFallback() {
    return Container(
      height: 180,
      width: double.infinity,
      color: const Color(0xFFE8ECF4),
      alignment: Alignment.center,
      child: const Icon(Icons.home_work_outlined, size: 42, color: Color(0xFF5B678D)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFF0),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(66),
        child: Container(
          padding: const EdgeInsets.only(top: 22, left: 16, right: 16, bottom: 6),
          decoration: const BoxDecoration(
            color: Color(0xFF1E2BFF),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Row(
            children: [
              const Icon(Icons.apartment, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Site Smart",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          userName.isEmpty ? "Loading..." : userName,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            userRole.isEmpty ? "..." : userRole,
                            style: const TextStyle(color: Colors.white, fontSize: 9),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfilePage()),
                  );
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_outline, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF1E2BFF), width: 2),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  const Icon(Icons.search, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: "Search for properties...",
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  Container(
                    height: 44,
                    width: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E2BFF),
                      borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
                    ),
                    child: const Icon(Icons.search, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('houses')
                  .orderBy('updatedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Unable to load house listings right now.'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final firestoreListings = (snapshot.data?.docs ?? [])
                    .map((doc) => HouseListing.fromMap(doc.id, doc.data()))
                    .where((listing) => listing.isPublished)
                    .toList();

                final sourceListings = _mergeListings(firestoreListings);
                final filteredListings = _filterListings(sourceListings);

                if (filteredListings.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'No houses match "${searchCtrl.text.trim()}".',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredListings.length,
                  itemBuilder: (context, index) {
                    final listing = filteredListings[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => HouseDetailPage(
                              houseId: listing.id,
                              imagePath: listing.imagePath,
                              imageUrl: listing.imageUrl,
                              galleryPaths: listing.galleryPaths,
                              houseName: listing.houseName,
                              priceText: listing.priceText,
                              vrUrl: listing.vrUrl,
                              detail: listing.detail,
                              location: listing.location,
                              bedrooms: listing.bedrooms,
                              bathrooms: listing.bathrooms,
                              sqft: listing.sqft,
                              about: listing.about,
                              features: listing.features,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _listingImage(listing),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              listing.houseName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${listing.priceText} - ${listing.detail}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.favorite_border),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
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
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "Profile"),
        ],
      ),
    );
  }
}
