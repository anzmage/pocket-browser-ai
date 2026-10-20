import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import '../core/agent_loop.dart';
import '../core/models.dart';
import 'browser_controller.dart';

class PageObserver {
  final BrowserController browser;
  String? _script;
  PageObserver(this.browser);
  Future<void> install(RunToken token) async {
    token.check();
    _script ??= await rootBundle.loadString('assets/observer.js');
    token.check();
    await browser.web.runJavaScript(_script!);
    token.check();
  }

  Future<dynamic> evaluate(String expression, RunToken token) async {
    token.check();
    final raw = await token.guard(
      browser.web.runJavaScriptReturningResult(expression),
    );
    token.check();
    dynamic value = raw;
    // Android returns string JSON; some platform versions double-encode it.
    for (var n = 0; n < 2 && value is String; n++) {
      value = jsonDecode(value);
    }
    return value;
  }

  Future<PageSnapshot> observe(RunToken token) async {
    await browser.settle(token);
    token.check();
    await install(token);
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
    final result = await evaluate(
      'JSON.stringify(window.__pocketPageV1.observe(${jsonEncode(id)}))',
      token,
    );
    return PageSnapshot.fromJson(Map<String, dynamic>.from(result as Map));
  }
}
