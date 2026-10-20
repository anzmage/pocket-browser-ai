import 'package:flutter/material.dart';
import '../ai/openai_provider.dart';
import '../core/agent_loop.dart';
import '../core/models.dart';
import '../settings/settings_store.dart';

class SettingsPage extends StatefulWidget {
  final AiSettings settings;
  const SettingsPage({super.key, required this.settings});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final base = TextEditingController(text: widget.settings.baseUrl);
  late final keyInput = TextEditingController(text: widget.settings.apiKey);
  late final model = TextEditingController(text: widget.settings.model);
  late final steps = TextEditingController(text: '${widget.settings.maxSteps}');
  bool busy = false;
  String status = '';
  RunToken? token;
  AiSettings values() => AiSettings(
    baseUrl: base.text,
    apiKey: keyInput.text,
    model: model.text,
    maxSteps: int.tryParse(steps.text) ?? 0,
  );
  Future<void> operation(bool test) async {
    setState(() {
      busy = true;
      status = '';
    });
    final t = RunToken();
    token = t;
    try {
      final settings = values()..validate();
      if (test) {
        await t.guard(OpenAiProvider(settings).test(t));
        if (mounted)
          setState(
            () => status = 'Terhubung: Chat Completions mengembalikan teks.',
          );
      } else {
        await SettingsStore().save(settings);
        if (mounted) Navigator.pop(context, settings);
      }
    } on SafetyException catch (e) {
      if (mounted) setState(() => status = e.message);
    } catch (_) {
      if (mounted)
        setState(
          () => status =
              'Koneksi/penyimpanan gagal. Periksa jaringan dan konfigurasi.',
        );
    } finally {
      t.cancel();
      token = null;
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    token?.cancel();
    base.dispose();
    keyInput.dispose();
    model.dispose();
    steps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pengaturan AI')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Bring your own key. Konteks halaman dikirim hanya saat Run. Gunakan provider yang Anda percayai.',
        ),
        TextField(
          controller: base,
          enabled: !busy,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Base URL HTTPS / endpoint lengkap',
          ),
        ),
        TextField(
          controller: keyInput,
          enabled: !busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'API key (Android secure storage)',
          ),
        ),
        TextField(
          controller: model,
          enabled: !busy,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Model ID'),
        ),
        TextField(
          controller: steps,
          enabled: !busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Batas langkah (1–50, default 15)',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : () => operation(false),
          child: const Text('Simpan'),
        ),
        OutlinedButton(
          onPressed: busy ? null : () => operation(true),
          child: const Text('Test connection'),
        ),
        if (busy) const LinearProgressIndicator(),
        Text(status),
        const SizedBox(height: 16),
        const Text(
          'Test mengirim request kecil berbayar sesuai provider, tanpa data halaman. Tidak memakai tool calling atau structured output. Tidak ada key di APK/workflow.',
        ),
      ],
    ),
  );
}
