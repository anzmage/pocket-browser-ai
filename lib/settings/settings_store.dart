import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/models.dart';

class SettingsStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  Future<AiSettings> load() async {
    final raw = await _storage.read(key: 'ai-settings-v1');
    if (raw == null) return const AiSettings();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return AiSettings(
      baseUrl: j['baseUrl'] as String,
      apiKey: j['apiKey'] as String,
      model: j['model'] as String,
      maxSteps: j['maxSteps'] as int,
    );
  }

  Future<void> save(AiSettings settings) async {
    settings.validate();
    await _storage.write(
      key: 'ai-settings-v1',
      value: jsonEncode({
        'baseUrl': settings.baseUrl.trim(),
        'apiKey': settings.apiKey.trim(),
        'model': settings.model.trim(),
        'maxSteps': settings.maxSteps,
      }),
    );
  }
}
