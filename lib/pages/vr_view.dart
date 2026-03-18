import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_smart2/pages/vr_webview.dart';

class VrViewPage extends StatefulWidget {
  final String title;
  final String imagePath;
  final String vrUrl;

  const VrViewPage({
    super.key,
    required this.title,
    required this.imagePath,
    required this.vrUrl,
  });

  @override
  State<VrViewPage> createState() => _VrViewPageState();
}

class _VrViewPageState extends State<VrViewPage> {
  int _selectedImageIndex = 0;
  bool get _supportsEmbeddedView => supportsVrEmbeddedWebView;

  List<String> get _galleryImages => _buildGalleryImages(widget.imagePath);

  @override
  void initState() {
    super.initState();
    final initialIndex = _galleryImages.indexOf(widget.imagePath);
    _selectedImageIndex = initialIndex >= 0 ? initialIndex : 0;
  }

  List<String> _buildGalleryImages(String imagePath) {
    if (imagePath == 'assets/home1_imgs/1.png') {
      return List<String>.generate(
        6,
        (index) => 'assets/home1_imgs/${index + 1}.png',
      );
    }
    if (imagePath == 'assets/home2_imgs/h2_1.png') {
      return List<String>.generate(
        6,
        (index) => 'assets/home2_imgs/h2_${index + 1}.png',
      );
    }
    return [imagePath];
  }

  Future<void> _copyVrLink() async {
    await Clipboard.setData(ClipboardData(text: widget.vrUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('VR link copied')));
  }

  void _openWebView() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _VrWebViewScreen(vrUrl: widget.vrUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2BFF),
        foregroundColor: Colors.white,
        title: const Text('VR View'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroCard(
                      title: widget.title,
                      imagePath: _galleryImages[_selectedImageIndex],
                    ),
                    const SizedBox(height: 16),
                    _InfoCard(
                      title: 'Property photos',
                      child: SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _galleryImages.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final isSelected = index == _selectedImageIndex;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedImageIndex = index;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 112,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF1E2BFF)
                                        : const Color(0xFFE1E5F0),
                                    width: isSelected ? 2 : 1,
                                  ),
                                  boxShadow: isSelected
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x221E2BFF),
                                            blurRadius: 14,
                                            offset: Offset(0, 6),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.asset(
                                        _galleryImages[index],
                                        fit: BoxFit.cover,
                                      ),
                                      if (isSelected)
                                        Align(
                                          alignment: Alignment.topRight,
                                          child: Container(
                                            margin: const EdgeInsets.all(6),
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF1E2BFF),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.check,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoCard(
                      title: 'View options',
                      child: Column(
                        children: [
                          _ModeTile(
                            icon: Icons.view_in_ar_outlined,
                            title: 'Meta Quest / Oculus',
                            subtitle:
                                'Open this VR link in the headset browser for an immersive 360 experience.',
                          ),
                          const SizedBox(height: 10),
                          _ModeTile(
                            icon: Icons.language_outlined,
                            title: 'In-app web view',
                            subtitle: _supportsEmbeddedView
                                ? 'Preview the VR tour directly inside the app.'
                                : 'Embedded web view is not available on Flutter web in this screen.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoCard(
                      title: 'VR link',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            widget.vrUrl,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1E2BFF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _copyVrLink,
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            label: const Text('Copy VR Link'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _supportsEmbeddedView
                                ? _openWebView
                                : _copyVrLink,
                            icon: Icon(
                              _supportsEmbeddedView
                                  ? Icons.open_in_browser_outlined
                                  : Icons.copy_outlined,
                            ),
                            label: Text(
                              _supportsEmbeddedView
                                  ? 'Open Web View'
                                  : 'Copy VR Link',
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoCard(
                      title: 'How to use with Oculus / Meta Quest',
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _GuideLine(
                            '1. Copy or share the VR link to the headset.',
                          ),
                          SizedBox(height: 8),
                          _GuideLine(
                            '2. Open the link in the Meta Quest Browser.',
                          ),
                          SizedBox(height: 8),
                          _GuideLine(
                            '3. Use the headset controls to look around the property in 360 view.',
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
    );
  }
}

class _VrWebViewScreen extends StatelessWidget {
  final String vrUrl;

  const _VrWebViewScreen({required this.vrUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2BFF),
        foregroundColor: Colors.white,
        title: const Text('Web View'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: VrEmbeddedWebView(vrUrl: vrUrl),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String title;
  final String imagePath;

  const _HeroCard({required this.title, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Image.asset(
              imagePath,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Container(
                  height: 220,
                  color: const Color(0xFFE1E5F8),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.home_work_outlined,
                    size: 56,
                    color: Color(0xFF1E2BFF),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Immersive Property Tour',
                    style: TextStyle(
                      color: Color(0xFF1E2BFF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF181C2A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Step inside the property, explore each space, and switch between headset viewing and browser-based preview.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xFF5E6474),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF181C2A),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF1E2BFF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Color(0xFF5E6474),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideLine extends StatelessWidget {
  final String text;

  const _GuideLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(
            Icons.check_circle_outline,
            size: 16,
            color: Color(0xFF1E2BFF),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Color(0xFF424A5C),
            ),
          ),
        ),
      ],
    );
  }
}
