import 'package:flutter/material.dart';

const bool supportsVrEmbeddedWebView = false;

class VrEmbeddedWebView extends StatelessWidget {
  final String vrUrl;

  const VrEmbeddedWebView({
    super.key,
    required this.vrUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: const Text(
        'Embedded web view is not available on this platform. Use the VR link above in your browser or headset browser.',
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: Color(0xFF424A5C),
        ),
      ),
    );
  }
}
