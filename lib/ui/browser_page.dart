import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../ai/openai_provider.dart';
import '../browser/action_executor.dart';
import '../browser/browser_controller.dart';
import '../browser/page_observer.dart';
import '../core/agent_loop.dart';
import '../core/models.dart';
import '../settings/settings_store.dart';
import 'settings_page.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with WidgetsBindingObserver {
  late final BrowserController browser;
  final address = TextEditingController();
  final goal = TextEditingController();
  final addressFocus = FocusNode();
  final events = <String>[];
  AiSettings settings = const AiSettings();
  AgentLoop? agent;
  bool panel = false, ready = false, exiting = false;
  BuildContext? confirmationContext;
  bool get running => agent?.running ?? false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    browser = BrowserController(onBlocked: event)..addListener(refresh);
    unawaited(initialize());
  }

  Future<void> initialize() async {
    try {
      settings = await SettingsStore().load();
    } catch (_) {
      event(
        'Secure storage tidak dapat dibaca; buka Pengaturan dan simpan ulang.',
      );
    }
    if (!mounted) return;
    setState(() => ready = true);
    await manual(browser.fixture);
  }

  void event(String text) {
    if (!mounted) return;
    setState(() {
      events.add(redact(text));
      if (events.length > 150) events.removeAt(0);
    });
  }

  void refresh() {
    if (!mounted) return;
    setState(() {
      if (!addressFocus.hasFocus) address.text = browser.url;
    });
  }

  void stop([String? message]) {
    agent?.stop();
    final dialog = confirmationContext;
    if (dialog != null && dialog.mounted) {
      confirmationContext = null;
      Navigator.of(dialog).pop(false);
    }
    if (message != null) event(message);
  }

  Future<void> manual(Future<void> Function() action) async {
    stop();
    try {
      await action();
    } on SafetyException catch (e) {
      event(e.message);
    } catch (_) {
      event('Operasi browser gagal.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed)
      stop('Aplikasi tidak di foreground: agent dihentikan.');
  }

  Future<bool> confirm(AgentAction action, PageSnapshot snapshot) async {
    if (!mounted || !running) return false;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        confirmationContext = ctx;
        final element = snapshot.elements.where(
          (e) => e.id == action.data['elementId'],
        );
        return AlertDialog(
          title: const Text('Izinkan satu aksi?'),
          content: SingleChildScrollView(
            child: Text(
              '${action.description}\n${snapshot.url}\n'
              '${element.isEmpty ? '' : element.first.label}\n'
              '${action.kind == 'type' ? 'Teks: ${redact(action.data['text'] as String)}\n' : ''}'
              '${action.kind == 'select' ? 'Pilihan: ${redact(action.data['value'] as String)}\n' : ''}'
              '${action.kind == 'navigate' ? 'Tujuan: ${safeUrl(action.data['url'] as String)}\n' : ''}'
              '\nAksi dapat mengirim form, transaksi, pesan, menghapus atau menyimpan data (termasuk autosave). '
              'Periksa halaman di belakang dialog. Login, OTP, CAPTCHA dan data sensitif wajib manual. '
              'Persetujuan ini hanya untuk satu aksi, bukan seluruh tugas.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tolak / Take over'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Izinkan sekali'),
            ),
          ],
        );
      },
    );
    confirmationContext = null;
    return approved ?? false;
  }

  Future<void> run() async {
    if (running || !ready || goal.text.trim().isEmpty) return;
    try {
      settings.validate();
    } on SafetyException catch (e) {
      event(e.message);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final executor = ActionExecutor(browser, PageObserver(browser));
    agent = AgentLoop(
      provider: OpenAiProvider(settings),
      page: executor,
      confirm: confirm,
      onEvent: event,
      maxSteps: settings.maxSteps,
    );
    event(
      'Run: snapshot baru. Konteks ringkas dikirim ke ${settings.endpoint.host}.',
    );
    final future = agent!.run(goal.text.trim());
    setState(() {});
    await future;
    if (mounted) setState(() {});
  }

  Future<void> settingsPage() async {
    stop();
    final result = await Navigator.push<AiSettings>(
      context,
      MaterialPageRoute(builder: (_) => SettingsPage(settings: settings)),
    );
    if (result != null && mounted) setState(() => settings = result);
  }

  Future<void> androidBack() async {
    if (running) {
      stop('Back: agent dihentikan.');
      return;
    }
    if (panel) {
      setState(() => panel = false);
      return;
    }
    if (await browser.web.canGoBack()) {
      await browser.back();
      return;
    }
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar browser?'),
        content: const Text('Cookie website tidak dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      exiting = true;
      await SystemNavigator.pop();
    }
  }

  @override
  void dispose() {
    agent?.stop();
    WidgetsBinding.instance.removeObserver(this);
    browser.removeListener(refresh);
    browser.dispose();
    address.dispose();
    goal.dispose();
    addressFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: exiting,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(androidBack());
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Pocket Browser AI'),
        actions: [
          IconButton(
            tooltip: 'Fixture lokal',
            onPressed: () => manual(browser.fixture),
            icon: const Icon(Icons.science_outlined),
          ),
          IconButton(
            tooltip: 'Pengaturan AI',
            onPressed: settingsPage,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Buka/tutup chat',
            onPressed: () => setState(() => panel = !panel),
            icon: const Icon(Icons.chat_bubble_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: browser.canBack
                        ? () => manual(browser.back)
                        : null,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  IconButton(
                    tooltip: 'Forward',
                    onPressed: browser.canForward
                        ? () => manual(browser.forward)
                        : null,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  Expanded(
                    child: TextField(
                      controller: address,
                      focusNode: addressFocus,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) =>
                          manual(() => browser.open(address.text)),
                      decoration: const InputDecoration(
                        hintText: 'https://example.com',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Go',
                    onPressed: () => manual(() => browser.open(address.text)),
                    icon: const Icon(Icons.arrow_circle_right_outlined),
                  ),
                  IconButton(
                    tooltip: 'Reload',
                    onPressed: () => manual(browser.web.reload),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (browser.loading)
                LinearProgressIndicator(value: browser.progress / 100),
              if (browser.error.isNotEmpty)
                Text(browser.error, style: const TextStyle(color: Colors.red)),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: WebViewWidget(controller: browser.web),
                    ),
                    // Prevent manual touches racing AI. Take over unlocks immediately;
                    // the same WebView/controller remains mounted throughout.
                    if (running)
                      Positioned.fill(
                        child: AbsorbPointer(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.04),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (running)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Agent aktif'),
                    TextButton(
                      onPressed: () => stop(),
                      child: const Text('Stop'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => stop(
                        'Take over: kontrol manual. Run berikutnya memakai snapshot baru.',
                      ),
                      child: const Text('Take over'),
                    ),
                  ],
                ),
              if (panel)
                SizedBox(
                  height:
                      constraints.maxHeight *
                      (MediaQuery.viewInsetsOf(context).bottom > 0
                          ? 0.66
                          : 0.40),
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Run mengirim teks halaman ke provider. Jangan masukkan rahasia dalam instruksi.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          reverse: true,
                          itemCount: events.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            child: Text(
                              events[events.length - 1 - i],
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: TextField(
                          controller: goal,
                          enabled: !running,
                          minLines: 1,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'Instruksi atau jawaban untuk agent',
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          FilledButton(
                            onPressed: running || !ready ? null : run,
                            child: const Text('Run'),
                          ),
                          TextButton(
                            onPressed: running ? () => stop() : null,
                            child: const Text('Stop'),
                          ),
                          TextButton(
                            onPressed: () => stop(
                              'Take over: lanjut manual, lalu Run untuk snapshot baru.',
                            ),
                            child: const Text('Take over'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
