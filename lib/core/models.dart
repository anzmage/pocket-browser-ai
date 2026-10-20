import 'dart:convert';

class SafetyException implements Exception {
  final String message;
  const SafetyException(this.message);
  @override
  String toString() => message;
}

Uri webUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      value.length > 2048) {
    throw const SafetyException(
      'Hanya URL HTTP/HTTPS tanpa kredensial diizinkan.',
    );
  }
  return uri;
}

Uri browserAddress(String value) {
  final trimmed = value.trim();
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(trimmed);
  return webUri(hasScheme ? trimmed : 'https://$trimmed');
}

String redact(String value) => value
    .replaceAll(
      RegExp(r'\bBearer\s+[^\s]+', caseSensitive: false),
      '[REDACTED]',
    )
    .replaceAll(
      RegExp(
        r'\b(?:sk-[A-Za-z0-9_-]+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b',
      ),
      '[REDACTED]',
    )
    .replaceAll(
      RegExp(
        r'(?:password|passwd|token|secret|api[_ -]?key|otp|cookie|authorization)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      '[REDACTED]',
    )
    .replaceAll(RegExp(r'\b[A-Za-z0-9_\-]{40,}\b'), '[REDACTED]');

String safeUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !['https', 'http'].contains(uri.scheme))
    return 'local fixture';
  return redact(
    '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}',
  );
}

class PageElement {
  final String id, role, type, label;
  final bool enabled, sensitive;
  final List<String> options;
  PageElement({
    required this.id,
    required this.role,
    required this.type,
    required this.label,
    required this.enabled,
    required this.sensitive,
    this.options = const [],
  });
  factory PageElement.fromJson(Map<String, dynamic> j) => PageElement(
    id: j['id'] as String,
    role: j['role'] as String,
    type: j['type'] as String,
    label: redact(j['label'] as String),
    enabled: j['enabled'] == true,
    sensitive: j['sensitive'] == true,
    options: (j['options'] as List? ?? [])
        .map((v) => redact(v as String))
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'type': type,
    'label': sensitive ? '[manual only]' : label,
    'enabled': enabled,
    'sensitive': sensitive,
    if (!sensitive && options.isNotEmpty) 'options': options,
  };
}

class PageSnapshot {
  final String id, url, title, text, fingerprint;
  final List<PageElement> elements;
  PageSnapshot({
    required this.id,
    required this.url,
    required this.title,
    required this.text,
    required this.fingerprint,
    required this.elements,
  });
  factory PageSnapshot.fromJson(Map<String, dynamic> j) => PageSnapshot(
    id: j['id'] as String,
    url: safeUrl(j['url'] as String),
    title: redact(j['title'] as String),
    text: redact(j['text'] as String),
    fingerprint: j['fingerprint'] as String,
    elements: (j['elements'] as List)
        .map((v) => PageElement.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'snapshotId': id,
    'url': url,
    'title': title,
    'text': text,
    'elements': elements.map((e) => e.toJson()).toList(),
  };
}

class AgentAction {
  final String kind, snapshotId;
  final Map<String, dynamic> data;
  AgentAction._(this.kind, this.snapshotId, this.data);
  static const schemas = <String, Set<String>>{
    'observe': {},
    'click': {'elementId'},
    'type': {'elementId', 'text'},
    'select': {'elementId', 'value'},
    'scroll': {'direction', 'amount'},
    'navigate': {'url'},
    'back': {},
    'wait': {'milliseconds'},
    'finish': {'summary'},
    'ask_user': {'question'},
  };
  factory AgentAction.parse(String source) {
    if (source.length > 12000)
      throw const SafetyException('Respons aksi terlalu besar.');
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const SafetyException(
        'Respons harus satu objek JSON, tanpa Markdown.',
      );
    }
    if (decoded is! Map<String, dynamic>)
      throw const SafetyException('Aksi bukan objek JSON.');
    final kind = decoded['action'];
    if (kind is! String || !schemas.containsKey(kind))
      throw const SafetyException('Aksi tidak dikenal.');
    final keys = {'action', 'snapshotId', ...schemas[kind]!};
    if (decoded.length != keys.length || !keys.every(decoded.containsKey)) {
      throw const SafetyException('Field aksi tidak sesuai schema.');
    }
    for (final key in keys.difference({'amount', 'milliseconds'})) {
      if (decoded[key] is! String ||
          (decoded[key] as String).isEmpty ||
          (decoded[key] as String).length > 4000) {
        throw const SafetyException('Field teks aksi tidak valid.');
      }
    }
    if (kind == 'scroll' &&
        (!['up', 'down'].contains(decoded['direction']) ||
            decoded['amount'] is! int ||
            decoded['amount'] < 1 ||
            decoded['amount'] > 1200)) {
      throw const SafetyException('Scroll harus up/down, 1–1200 piksel.');
    }
    if (kind == 'wait' &&
        (decoded['milliseconds'] is! int ||
            decoded['milliseconds'] < 0 ||
            decoded['milliseconds'] > 5000)) {
      throw const SafetyException('Wait dibatasi 0–5000 ms.');
    }
    if (kind == 'navigate') webUri(decoded['url'] as String);
    return AgentAction._(kind, decoded['snapshotId'] as String, decoded);
  }
  void validate(PageSnapshot current) {
    if (snapshotId != current.id)
      throw const SafetyException('Snapshot usang.');
    if (!data.containsKey('elementId')) return;
    final matches = current.elements.where((e) => e.id == data['elementId']);
    if (matches.length != 1)
      throw const SafetyException('Elemen tidak ditemukan.');
    final e = matches.single;
    if (!e.enabled || e.sensitive)
      throw const SafetyException('Elemen nonaktif/sensitif: isi manual.');
    if (kind == 'type' &&
        (!['input', 'textarea'].contains(e.role) ||
            ![
              'text',
              'search',
              'url',
              'email',
              'tel',
              'number',
              'textarea',
            ].contains(e.type))) {
      throw const SafetyException('Elemen bukan input teks yang didukung.');
    }
    if (kind == 'select' &&
        (e.role != 'select' || !e.options.contains(data['value']))) {
      throw const SafetyException('Pilihan select tidak valid.');
    }
  }

  bool get needsConfirmation =>
      ['click', 'type', 'select', 'navigate', 'back'].contains(kind);
  String get signature => jsonEncode({...data}..remove('snapshotId'));
  String get description => switch (kind) {
    'type' => 'type ${data['elementId']} (teks tidak dicatat)',
    'select' => 'select ${data['elementId']} (nilai tidak dicatat)',
    'navigate' => 'navigate ${safeUrl(data['url'] as String)}',
    _ => '$kind${data.containsKey('elementId') ? ' ${data['elementId']}' : ''}',
  };
}

class AiSettings {
  final String baseUrl, apiKey, model;
  final int maxSteps;
  const AiSettings({
    this.baseUrl = 'https://api.deepseek.com',
    this.apiKey = '',
    this.model = 'deepseek-v4-pro',
    this.maxSteps = 15,
  });
  Uri get endpoint {
    final uri = webUri(baseUrl.trim());
    if (uri.scheme != 'https' || uri.hasQuery || uri.hasFragment) {
      throw const SafetyException(
        'Endpoint AI wajib HTTPS tanpa query/fragment.',
      );
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(
      path: path.endsWith('/chat/completions')
          ? path
          : '$path/chat/completions',
    );
  }

  void validate() {
    endpoint;
    if (apiKey.trim().isEmpty ||
        apiKey.contains('\n') ||
        apiKey.contains('\r') ||
        model.trim().isEmpty ||
        maxSteps < 1 ||
        maxSteps > 50) {
      throw const SafetyException('Isi key, model, dan batas langkah 1–50.');
    }
  }
}
