import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const bool supportsVrEmbeddedWebView = true;

class VrEmbeddedWebView extends StatefulWidget {
  final String vrUrl;

  const VrEmbeddedWebView({
    super.key,
    required this.vrUrl,
  });

  @override
  State<VrEmbeddedWebView> createState() => _VrEmbeddedWebViewState();
}

class _VrEmbeddedWebViewState extends State<VrEmbeddedWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.vrUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: WebViewWidget(controller: _controller),
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF1E2BFF),
              ),
            ),
        ],
      ),
    );
  }
}
