import 'dart:async';
import 'dart:convert';
import '../lib/core/models.dart';
import '../lib/core/agent_loop.dart';

void check(bool ok, String label) {
  if (!ok) throw StateError(label);
}

void rejects(void Function() operation) {
  try {
    operation();
  } on SafetyException {
    return;
  }
  throw StateError('Expected SafetyException');
}

PageSnapshot snapshot([String id = 's1', String fp = 'same']) => PageSnapshot(
  id: id,
  url: 'https://example.com',
  title: 'Fixture',
  text: 'hello',
  fingerprint: fp,
  elements: [
    PageElement(
      id: 'e0',
      role: 'input',
      type: 'text',
      label: 'Name',
      enabled: true,
      sensitive: false,
    ),
    PageElement(
      id: 'e1',
      role: 'input',
      type: 'password',
      label: 'Password',
      enabled: true,
      sensitive: true,
    ),
    PageElement(
      id: 'e2',
      role: 'button',
      type: 'button',
      label: 'Disabled',
      enabled: false,
      sensitive: false,
    ),
    PageElement(
      id: 'e3',
      role: 'select',
      type: 'select-one',
      label: 'Color',
      enabled: true,
      sensitive: false,
      options: ['blue'],
    ),
  ],
);
String action(
  String kind, [
  Map<String, dynamic> fields = const {},
  String sid = 's1',
]) => jsonEncode({'action': kind, 'snapshotId': sid, ...fields});

class MockProvider implements AiProvider {
  int calls = 0;
  final Future<String> Function(PageSnapshot, RunToken, int) respond;
  MockProvider(this.respond);
  @override
  Future<String> next(
    String goal,
    PageSnapshot page,
    List<String> history,
    RunToken token,
  ) {
    calls++;
    return respond(page, token, calls);
  }
}

class MockPage implements AgentPage {
  int executions = 0, observations = 0, settles = 0;
  bool progress = false;
  Future<void> Function(RunToken)? onExecute, onObserve, onSettle;
  @override
  Future<PageSnapshot> observe(RunToken token) async {
    observations++;
    await onObserve?.call(token);
    return snapshot('s$observations', progress ? '$executions' : 'same');
  }

  @override
  Future<void> execute(
    AgentAction action,
    PageSnapshot page,
    RunToken token,
  ) async {
    token.check();
    executions++;
    await onExecute?.call(token);
  }

  @override
  Future<void> settle(RunToken token) async {
    settles++;
    await onSettle?.call(token);
  }
}

Future<void> runCoreChecks() async {
  var passed = 0;
  Future<void> test(String name, FutureOr<void> Function() fn) async {
    await fn();
    passed++;
    print('PASS $name');
  }

  await test('all allowed schemas parse and validate', () {
    for (final raw in [
      action('observe'),
      action('click', {'elementId': 'e0'}),
      action('type', {'elementId': 'e0', 'text': 'Pocket'}),
      action('select', {'elementId': 'e3', 'value': 'blue'}),
      action('scroll', {'direction': 'down', 'amount': 500}),
      action('navigate', {'url': 'https://example.com'}),
      action('back'),
      action('wait', {'milliseconds': 5000}),
      action('finish', {'summary': 'done'}),
      action('ask_user', {'question': 'manual please'}),
    ]) {
      AgentAction.parse(raw).validate(snapshot());
    }
  });
  await test('strict unknown, extra, missing and incorrectly typed fields', () {
    for (final raw in [
      action('execute_javascript', {'script': 'alert(1)'}),
      action('click'),
      action('observe', {'extra': true}),
      '[]',
      '{}',
      '```json\n{}\n```',
      action('type', {'elementId': 'e0', 'text': 3}),
      action('wait', {'milliseconds': 1.0}),
      action('scroll', {'direction': 'left', 'amount': 1}),
      action('wait', {'milliseconds': 5001}),
      action('scroll', {'direction': 'down', 'amount': 1201}),
      '{',
      'x' * 12001,
    ]) {
      rejects(() => AgentAction.parse(raw));
    }
  });
  await test(
    'stale references and missing/disabled/sensitive elements blocked',
    () {
      rejects(
        () => AgentAction.parse(
          action('observe', {}, 'old'),
        ).validate(snapshot()),
      );
      for (final id in ['old', 'e1', 'e2']) {
        rejects(
          () => AgentAction.parse(
            action('click', {'elementId': id}),
          ).validate(snapshot()),
        );
      }
      rejects(
        () => AgentAction.parse(
          action('type', {'elementId': 'e3', 'text': 'x'}),
        ).validate(snapshot()),
      );
      rejects(
        () => AgentAction.parse(
          action('select', {'elementId': 'e3', 'value': 'red'}),
        ).validate(snapshot()),
      );
    },
  );
  await test('URL and HTTPS provider policy', () {
    const defaults = AiSettings();
    check(
      defaults.baseUrl == 'https://api.deepseek.com',
      'DeepSeek default endpoint',
    );
    check(defaults.model == 'deepseek-v4-pro', 'Pro default model');
    check(defaults.apiKey.isEmpty, 'No bundled API key');
    check(
      defaults.endpoint.toString() ==
          'https://api.deepseek.com/chat/completions',
      'Default request URL',
    );
    rejects(defaults.validate);
    for (final u in [
      'javascript:alert(1)',
      'file:///x',
      'https://user:pass@example.com',
      'intent://x',
    ]) {
      rejects(() => webUri(u));
    }
    for (final u in [
      'mailto:user@example.com',
      'tel:1234',
      'sms:1234',
      'javascript:alert(1)',
      'custom:abc',
    ]) {
      rejects(() => browserAddress(u));
    }
    check(
      browserAddress('example.com').toString() == 'https://example.com',
      'address defaults HTTPS',
    );
    for (final u in ['http://example.com/v1', 'https://example.com/v1?key=x']) {
      rejects(() => AiSettings(baseUrl: u).endpoint);
    }
    check(
      const AiSettings(baseUrl: 'https://example.com/v1/').endpoint.path ==
          '/v1/chat/completions',
      'base endpoint',
    );
    check(
      const AiSettings(
            baseUrl: 'https://example.com/custom/chat/completions',
          ).endpoint.path ==
          '/custom/chat/completions',
      'full endpoint',
    );
  });
  await test('sensitive redaction and URL query removal', () {
    final value = redact(
      'password=hunter2 token=abc Bearer xyz sk-example_secret',
    );
    for (final s in ['hunter2', 'abc', 'xyz', 'sk-example_secret']) {
      check(!value.contains(s), 'redacted $s');
    }
    check(
      !safeUrl('https://example.com/a?token=secret#otp').contains('secret'),
      'url stripped',
    );
    final j = snapshot().elements[1].toJson();
    check(j['label'] == '[manual only]', 'sensitive label');
  });
  await test('bounded steps with mock provider, no paid API', () async {
    final page = MockPage()..progress = true;
    final logs = <String>[];
    final provider = MockProvider(
      (s, t, n) async =>
          action('scroll', {'direction': 'down', 'amount': 1}, s.id),
    );
    await AgentLoop(
      provider: provider,
      page: page,
      confirm: (_, __) async => true,
      onEvent: logs.add,
      maxSteps: 2,
    ).run('test');
    check(page.executions == 2 && provider.calls == 2, 'step limit');
    check(logs.last.contains('Batas 2'), 'step report');
  });
  await test('bounded retries, invalid output never executed', () async {
    final page = MockPage(), logs = <String>[];
    final provider = MockProvider((s, t, n) async => 'not JSON');
    await AgentLoop(
      provider: provider,
      page: page,
      confirm: (_, __) async => true,
      onEvent: logs.add,
      maxRetries: 2,
    ).run('test');
    check(provider.calls == 3 && page.executions == 0, 'retry limit');
    check(logs.last.contains('Batas retry'), 'retry report');
  });
  await test('retry obtains a fresh snapshot', () async {
    final page = MockPage();
    final ids = <String>[];
    final provider = MockProvider((s, t, n) async {
      ids.add(s.id);
      return n == 1 ? 'invalid' : action('finish', {'summary': 'done'}, s.id);
    });
    await AgentLoop(
      provider: provider,
      page: page,
      confirm: (_, __) async => true,
      onEvent: (_) {},
      maxRetries: 1,
    ).run('test');
    check(
      ids.length == 2 && ids[0] != ids[1] && page.executions == 0,
      'fresh retry',
    );
  });
  await test('repeated actions without progress stop after three', () async {
    final page = MockPage(), logs = <String>[];
    await AgentLoop(
      provider: MockProvider((s, t, n) async => action('observe', {}, s.id)),
      page: page,
      confirm: (_, __) async => true,
      onEvent: logs.add,
    ).run('test');
    check(
      page.executions == 3 && logs.last.contains('tanpa kemajuan'),
      'no progress guard',
    );
  });
  await test('confirmation denied never executes', () async {
    final page = MockPage();
    var confirms = 0;
    await AgentLoop(
      provider: MockProvider(
        (s, t, n) async => action('click', {'elementId': 'e0'}, s.id),
      ),
      page: page,
      confirm: (_, __) async {
        confirms++;
        return false;
      },
      onEvent: (_) {},
    ).run('test');
    check(confirms == 1 && page.executions == 0, 'denial');
  });
  for (final stage in [
    'observe',
    'request',
    'confirmation',
    'execute',
    'settle',
  ]) {
    await test('Stop during $stage prevents following actions', () async {
      final page = MockPage();
      final entered = Completer<void>();
      final release = Completer<void>();
      Future<void> block(RunToken t) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }

      if (stage == 'observe') page.onObserve = block;
      if (stage == 'execute') page.onExecute = block;
      if (stage == 'settle') page.onSettle = block;
      final provider = MockProvider((s, t, n) async {
        if (stage == 'request') await block(t);
        return action('click', {'elementId': 'e0'}, s.id);
      });
      final loop = AgentLoop(
        provider: provider,
        page: page,
        confirm: (_, __) async {
          if (stage == 'confirmation') await block(RunToken());
          return true;
        },
        onEvent: (_) {},
      );
      final run = loop.run('test');
      await entered.future.timeout(const Duration(seconds: 2));
      loop.stop();
      await run.timeout(const Duration(seconds: 2));
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      check(
        page.executions == (['execute', 'settle'].contains(stage) ? 1 : 0),
        'no action after stop',
      );
      check(!loop.running, 'stopped');
    });
  }
  await test('execution error not retried (uncertain mutation)', () async {
    final page = MockPage()
      ..onExecute = (_) async => throw const SafetyException('stale');
    final provider = MockProvider(
      (s, t, n) async => action('click', {'elementId': 'e0'}, s.id),
    );
    await AgentLoop(
      provider: provider,
      page: page,
      confirm: (_, __) async => true,
      onEvent: (_) {},
    ).run('test');
    check(page.executions == 1 && provider.calls == 1, 'no mutation retry');
  });
  await test('finish and ask_user stop without executor', () async {
    for (final kind in ['finish', 'ask_user']) {
      final page = MockPage();
      await AgentLoop(
        provider: MockProvider(
          (s, t, n) async => action(kind, {
            kind == 'finish' ? 'summary' : 'question': 'manual',
          }, s.id),
        ),
        page: page,
        confirm: (_, __) async => true,
        onEvent: (_) {},
      ).run('test');
      check(page.executions == 0, 'terminal action');
    }
  });
  await test('takeover then Run observes anew', () async {
    final page = MockPage();
    final ids = <String>[];
    final loop = AgentLoop(
      provider: MockProvider((s, t, n) async {
        ids.add(s.id);
        return action('finish', {'summary': 'done'}, s.id);
      }),
      page: page,
      confirm: (_, __) async => true,
      onEvent: (_) {},
    );
    await loop.run('first');
    loop.stop();
    await loop.run('resume');
    check(ids.length == 2 && ids[0] != ids[1], 'fresh run');
  });
  print('$passed core checks passed.');
}

Future<void> main() => runCoreChecks();
