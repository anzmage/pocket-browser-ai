import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/agent_loop.dart';
import '../core/models.dart';

class BrowserController extends ChangeNotifier {
  late final WebViewController web;
  int progress = 0;
  bool loading = false, canBack = false, canForward = false;
  String url = '', error = '';
  bool _disposed = false;
  final void Function(String) onBlocked;
  BrowserController({required this.onBlocked}) {
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null &&
                ['http', 'https'].contains(uri.scheme) &&
                uri.userInfo.isEmpty) {
              return NavigationDecision.navigate;
            }
            // Only app-selected bundled asset is allowed; never arbitrary file://.
            if (request.url ==
                    'file:///android_asset/flutter_assets/assets/fixture.html' ||
                request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            onBlocked(
              'Skema diblokir: ${uri?.scheme ?? 'unknown'}. Tidak membuka aplikasi eksternal otomatis.',
            );
            return NavigationDecision.prevent;
          },
          onPageStarted: (value) {
            url = value;
            loading = true;
            error = '';
            _notify();
          },
          onProgress: (value) {
            progress = value;
            _notify();
          },
          onUrlChange: (change) {
            if (change.url != null) url = change.url!;
            _notify();
          },
          onPageFinished: (value) {
            url = value;
            loading = false;
            _refreshHistory();
          },
          onSslAuthError: (request) async {
            await request.cancel();
            error = 'Sertifikat TLS ditolak. Tidak ada opsi bypass.';
            loading = false;
            _notify();
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true) {
              error =
                  'Halaman gagal dimuat (kode ${e.errorCode}). TLS tidak dilewati.';
              loading = false;
              _notify();
            }
          },
        ),
      );
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _refreshHistory() async {
    canBack = await web.canGoBack();
    canForward = await web.canGoForward();
    _notify();
  }

  Future<void> open(String value) async {
    await web.loadRequest(browserAddress(value));
  }

  Future<void> fixture() => web.loadFlutterAsset('assets/fixture.html');
  Future<void> back() async {
    if (await web.canGoBack()) await web.goBack();
  }

  Future<void> forward() async {
    if (await web.canGoForward()) await web.goForward();
  }

  Future<void> settle(RunToken token) async {
    // Bounded loading wait, then a brief render interval. DOM observer verifies
    // snapshot freshness; asynchronous sites can still require another wait.
    await token.delay(450);
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (loading) {
      token.check();
      if (DateTime.now().isAfter(end)) throw TimeoutException('Page loading');
      await token.delay(150);
    }
    await token.delay(250);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
