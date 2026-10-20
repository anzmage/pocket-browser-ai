import 'dart:convert';
import '../core/agent_loop.dart';
import '../core/models.dart';
import 'browser_controller.dart';
import 'page_observer.dart';

class ActionExecutor implements AgentPage {
  final BrowserController browser;
  final PageObserver observer;
  ActionExecutor(this.browser, this.observer);
  @override
  Future<PageSnapshot> observe(RunToken token) => observer.observe(token);
  @override
  Future<void> settle(RunToken token) => browser.settle(token);
  @override
  Future<void> execute(
    AgentAction action,
    PageSnapshot snapshot,
    RunToken token,
  ) async {
    action.validate(snapshot);
    token.check();
    // All parameters JSON encoded, never executable model-generated JS.
    final result = await observer.evaluate(
      'JSON.stringify(window.__pocketPageV1.execute(${jsonEncode(action.data)}))',
      token,
    );
    token.check();
    if (result is! Map || result['ok'] != true) {
      throw const SafetyException(
        'Aksi diblokir: snapshot/elemen berubah atau tidak didukung. Run ulang untuk snapshot baru.',
      );
    }
    switch (action.kind) {
      case 'navigate':
        token.check();
        await browser.web.loadRequest(webUri(action.data['url'] as String));
      case 'back':
        token.check();
        await browser.back();
      case 'wait':
        await token.delay(action.data['milliseconds'] as int);
    }
  }
}
