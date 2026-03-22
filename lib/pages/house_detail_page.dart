import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'home_page.dart';
import 'profile_page.dart';
import 'booking_form_page.dart';
import '../services/vr_payment_service.dart';
import 'vr_view.dart';

class HouseDetailPage extends StatefulWidget {
  final String imagePath;
  final String imageUrl;
  final List<String> galleryPaths;
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

  const HouseDetailPage({
    super.key,
    required this.imagePath,
    this.imageUrl = '',
    this.galleryPaths = const [],
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

  @override
  State<HouseDetailPage> createState() => _HouseDetailPageState();
}

class _HouseDetailPageState extends State<HouseDetailPage> {
  static const double _bottomNavigationBarHeight = 64;
  final PageController _galleryController = PageController(viewportFraction: 1);
  int _selectedImageIndex = 0;
  String userName = "";
  String userRole = "Client";
  bool _isVrAccessBusy = false;

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  @override
  void dispose() {
    _galleryController.dispose();
    super.dispose();
  }

  Future<void> loadUserData() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        setState(() {
          userName = "User";
        });
        return;
      }

      String uid = currentUser.uid;
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection("users").doc(uid).get();
      Map<String, dynamic> data =
          (userDoc.data() as Map<String, dynamic>?) ?? {};
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

  Future<void> _handleVrAccess() async {
    if (widget.vrUrl.trim().isEmpty) {
      _showBottomSafeSnackBar('VR view is not available for this house yet.');
      return;
    }
    if (_isVrAccessBusy) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showBottomSafeSnackBar('Please sign in to unlock VR access.');
      return;
    }

    setState(() {
      _isVrAccessBusy = true;
    });

    try {
      final hasAccess = await VrPaymentService.hasVrAccess(
        houseTitle: widget.houseName,
      );
      if (!mounted) return;

      if (hasAccess) {
        _openVrView();
        return;
      }

      if (!VrPaymentService.supportsNativeVrPayments) {
        _showBottomSafeSnackBar(VrPaymentService.unsupportedPlatformMessage);
        return;
      }

      final shouldContinue = await _showVrPaymentDialog();
      if (!mounted || !shouldContinue) return;

      await VrPaymentService.payForVrAccess(
        houseTitle: widget.houseName,
        customerName: _resolveCustomerName(currentUser),
        email: currentUser.email ?? '',
      );
      if (!mounted) return;

      _showBottomSafeSnackBar('Payment successful. VR access unlocked.');
      _openVrView();
    } catch (error) {
      if (!mounted) return;
      _showBottomSafeSnackBar(VrPaymentService.describeError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isVrAccessBusy = false;
        });
      }
    }
  }

  void _showBottomSafeSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    final safeBottom = MediaQuery.of(context).padding.bottom;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            _bottomNavigationBarHeight + safeBottom + 12,
          ),
        ),
      );
  }

  void _openVrView() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VrViewPage(
          title: widget.houseName,
          imagePath: widget.imagePath,
          vrUrl: widget.vrUrl,
        ),
      ),
    );
  }

  String _resolveCustomerName(User user) {
    final candidate = userName.trim();
    if (candidate.isNotEmpty && candidate.toLowerCase() != 'user') {
      return candidate;
    }

    final displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }

    final emailPrefix = user.email?.split('@').first.trim() ?? '';
    return emailPrefix.isEmpty ? 'Site Smart Customer' : emailPrefix;
  }

  Future<bool> _showVrPaymentDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Unlock VR Tour'),
          content: Text(
            'This account needs a one-time ${VrPaymentService.vrPriceLabel} Stripe payment to unlock all VR tours.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('Pay ${VrPaymentService.vrPriceLabel}'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  List<String> _buildGalleryImages(String imagePath) {
    if (widget.galleryPaths.isNotEmpty) {
      return widget.galleryPaths;
    }
    if (widget.imageUrl.trim().isNotEmpty) {
      return [widget.imageUrl.trim()];
    }
    if (imagePath == 'assets/home1_imgs/1.png') {
      return List<String>.generate(6, (index) => 'assets/home1_imgs/${index + 1}.png');
    }
    if (imagePath == 'assets/home2_imgs/h2_1.png') {
      return List<String>.generate(6, (index) => 'assets/home2_imgs/h2_${index + 1}.png');
    }
    return [imagePath];
  }

  List<String> get galleryImages => _buildGalleryImages(widget.imagePath);

  String get displayBedrooms {
    if (widget.imagePath == 'assets/home1_imgs/1.png') {
      return '1';
    }
    return widget.bedrooms;
  }

  String get displayBathrooms {
    if (widget.imagePath == 'assets/home1_imgs/1.png') {
      return '1';
    }
    return widget.bathrooms;
  }

  Widget _buildGalleryImage(String source) {
    final isNetwork = source.startsWith('http://') || source.startsWith('https://');
    if (isNetwork) {
      return Image.network(
        source,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _imageFallback(),
      );
    }
    final isLocalFile = source.contains('\\') || source.startsWith('/');
    if (!kIsWeb && isLocalFile) {
      return Image.file(
        File(source),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _imageFallback(),
      );
    }
    return Image.asset(
      source,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _imageFallback(),
    );
  }

  Widget _imageFallback() {
    return Container(
      color: const Color(0xFFE8ECF4),
      alignment: Alignment.center,
      child: const Icon(
        Icons.home_work_outlined,
        size: 48,
        color: Color(0xFF5B678D),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFF0),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF1E2BFF),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.apartment, color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Site Smart',
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
                              userName.isEmpty ? 'Loading...' : userName,
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.all(Radius.circular(10)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                child: Text(
                                  userRole.isEmpty ? '...' : userRole,
                                  style: const TextStyle(color: Colors.white, fontSize: 9),
                                ),
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
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_circle_left_outlined),
                        ),
                        Expanded(
                          child: Text(
                            widget.houseName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 240,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PageView.builder(
                              controller: _galleryController,
                              itemCount: galleryImages.length,
                              onPageChanged: (index) {
                                setState(() {
                                  _selectedImageIndex = index;
                                });
                              },
                              itemBuilder: (context, index) {
                                return _buildGalleryImage(galleryImages[index]);
                              },
                            ),
                            if (galleryImages.length > 1)
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(
                                    galleryImages.length,
                                    (index) => AnimatedContainer(
                                      duration: const Duration(milliseconds: 220),
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      height: 8,
                                      width: _selectedImageIndex == index ? 22 : 8,
                                      decoration: BoxDecoration(
                                        color: _selectedImageIndex == index
                                            ? Colors.white
                                            : Colors.white70,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.priceText,
                                style: const TextStyle(
                                  color: Color(0xFF56A561),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Available',
                                  style: TextStyle(fontSize: 10, color: Colors.green),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 14),
                              const SizedBox(width: 4),
                              Text(widget.location, style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _MiniInfo(
                                icon: Icons.bed_outlined,
                                value: displayBedrooms,
                                label: 'Bedrooms',
                              ),
                              _MiniInfo(
                                icon: Icons.bathtub_outlined,
                                value: displayBathrooms,
                                label: 'Bathrooms',
                              ),
                              _MiniInfo(
                                icon: Icons.square_foot_outlined,
                                value: widget.sqft,
                                label: 'Sq.Ft',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('About this home', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                            widget.about,
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Features', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ...widget.features.map(
                            (feature) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('- $feature'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Construction Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 16, color: Colors.blue),
                              SizedBox(width: 8),
                              Expanded(child: Text('Estimated time duration', style: TextStyle(fontSize: 12))),
                              Text('7-8 Months', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.home_repair_service_outlined, size: 16, color: Colors.blue),
                              SizedBox(width: 8),
                              Expanded(child: Text('Construction type', style: TextStyle(fontSize: 12))),
                              Text('Custom Build', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD6DEFF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.view_in_ar_outlined,
                                size: 18,
                                color: Color(0xFF1E2BFF),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'VR Tour Ready',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E2BFF),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.vrUrl.trim().isEmpty
                                ? 'VR tour has not been added for this house yet.'
                                : 'Open the immersive 360 property tour now. Works with Meta Quest browser or in-app preview. One-time access fee: ${VrPaymentService.vrPriceLabel} and it unlocks all VR tours.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: widget.vrUrl.trim().isEmpty || _isVrAccessBusy
                                ? null
                                : _handleVrAccess,
                            icon: _isVrAccessBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.view_in_ar_outlined, size: 16),
                            label: Text(_isVrAccessBusy ? 'Preparing...' : 'View VR'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => BookingFormPage(
                                    houseTitle: widget.houseName,
                                    priceText: widget.priceText,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.check_circle, size: 16),
                            label: const Text('Start Project'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8D8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customization Available! Our home designs can be customized to fit your specific needs and preferences.',
                            style: TextStyle(fontSize: 11, color: Colors.black87),
                          ),
                          SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Contact us',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 11,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: _bottomNavigationBarHeight,
        color: const Color(0xFFDADADA),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _BottomItem(
              icon: Icons.grid_view,
              label: 'Home',
              active: true,
              onTap: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const HomePage()),
                  (route) => false,
                );
              },
            ),
            _BottomItem(
              icon: Icons.person_outline,
              label: 'Profile',
              active: false,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfilePage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MiniInfo({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.black54)),
      ],
    );
  }
}

class _BottomItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BottomItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: active ? Colors.black : Colors.black54),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.black : Colors.black54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
