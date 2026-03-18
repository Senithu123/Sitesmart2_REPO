import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'house_detail_page.dart';
import 'profile_page.dart';
import 'client_project_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedTab = 0;
  TextEditingController searchCtrl = TextEditingController();

  String userName = "";
  String userRole = "";

  final List<_HouseListing> listings = const [
    _HouseListing(
      imagePath: "assets/home1_imgs/1.png",
      houseName: "Lakeside Modern Retreat",
      priceText: "Rs.35,000,000",
      vrUrl: "https://site-smart-2.web.app/house1/",
      detail: "1 Bed | 1 Bath | 1800 sqft",
      location: "Malabe",
      bedrooms: "1",
      bathrooms: "1",
      sqft: "1800",
      about:
          "A low-profile waterfront design with wide timber decks, a central lounge, and large glass openings that keep the living spaces connected to the outdoor view.",
      features: [
        "Waterfront entertainment deck",
        "Open-plan living and dining area",
        "Panoramic glass frontage",
        "Outdoor fire-pit seating zone",
        "Compact modern kitchen layout",
        "Bright bedrooms with natural light",
      ],
    ),
    _HouseListing(
      imagePath: "assets/home2_imgs/h2_1.png",
      houseName: "Cliffside Pool House",
      priceText: "Rs.28,000,000",
      vrUrl: "https://site-smart-2.web.app/house2/",
      detail: "2 Beds | 1 Bath | 2100 sqft",
      location: "Nugegoda",
      bedrooms: "2",
      bathrooms: "1",
      sqft: "2100",
      about:
          "A striking modern pool house with dramatic glazing, elevated terraces, and a resort-style outdoor living area designed for relaxed evenings and private weekend stays.",
      features: [
        "Infinity-edge pool with timber deck",
        "Double-height glass living area",
        "Upper lounge with panoramic views",
        "Open indoor-outdoor entertainment zone",
        "Private main bedroom suite",
        "Ambient exterior lighting design",
      ],
    ),
    _HouseListing(
      imagePath: "assets/images/real_house_3.jpg",
      houseName: "Hillside Glass Residence",
      priceText: "Rs.32,000,000",
      vrUrl:
          "https://momento360.com/e/u/0d4f7f2e7b3e4cb8a64f3f1f6f4b1234?utm_campaign=embed&utm_source=other&heading=-18.89&pitch=0.77&field-of-view=75&size=medium",
      detail: "5 Beds | 3 Baths | 2400 sqft",
      location: "Athurugiriya",
      bedrooms: "5",
      bathrooms: "3",
      sqft: "2400",
      about:
          "A bold hillside home with strong horizontal lines, broad terraces, and expansive glazing that gives the design a bright and elevated feel.",
      features: [
        "Elevated terrace views",
        "Full-height glass sections",
        "Large shared living space",
        "Private upper-level rooms",
        "Modern stair and balcony detailing",
        "Indoor-outdoor flow for gatherings",
      ],
    ),
    _HouseListing(
      imagePath: "assets/images/real_house_4.jpg",
      houseName: "Urban Smart Residence",
      priceText: "Rs.40,000,000",
      vrUrl:
          "https://momento360.com/e/u/0d4f7f2e7b3e4cb8a64f3f1f6f4b1234?utm_campaign=embed&utm_source=other&heading=-18.89&pitch=0.77&field-of-view=75&size=medium",
      detail: "4 Beds | 4 Baths | 2600 sqft",
      location: "Battaramulla",
      bedrooms: "4",
      bathrooms: "4",
      sqft: "2600",
      about:
          "A polished city home with a sleek exterior, layered lighting, and a spacious interior arrangement focused on comfort, privacy, and modern convenience.",
      features: [
        "Smart-ready lighting layout",
        "Generous front elevation",
        "Multi-car parking area",
        "Large bedroom suites",
        "Contemporary facade lighting",
        "Flexible lounge and work areas",
      ],
    ),
  ];

  List<_HouseListing> get filteredListings {
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
        ...listing.features,
      ].join(' ').toLowerCase();

      return searchableText.contains(query);
    }).toList();
  }

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
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        setState(() {
          userName = "User";
          userRole = "Client";
        });
        return;
      }

      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection("users").doc(currentUser.uid).get();
      Map<String, dynamic> data = (userDoc.data() as Map<String, dynamic>?) ?? {};
      String fallbackName = currentUser.email?.split("@").first ?? "User";

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
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final firestore = FirebaseFirestore.instance;
      QuerySnapshot snap = await firestore
          .collection("bookings")
          .where("userId", isEqualTo: currentUser.uid)
          .get();

      if (!mounted || snap.docs.isEmpty) return;

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
      if (latestDoc == null || !accessGranted) {
        return;
      }

      final projectSnap =
          await firestore.collection('projects').doc(latestDoc.id).get();
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
            child: filteredListings.isEmpty
                ? Center(
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
                  )
                : ListView.builder(
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
                                imagePath: listing.imagePath,
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
                                child: Image.asset(
                                  listing.imagePath,
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
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
                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
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

class _HouseListing {
  final String imagePath;
  final String houseName;
  final String priceText;
  final String vrUrl;
  final String detail;
  final String location;
  final String bedrooms;
  final String bathrooms;
  final String sqft;
  final String about;
  final List<String> features;

  const _HouseListing({
    required this.imagePath,
    required this.houseName,
    required this.priceText,
    required this.vrUrl,
    required this.detail,
    required this.location,
    required this.bedrooms,
    required this.bathrooms,
    required this.sqft,
    required this.about,
    required this.features,
  });
}
