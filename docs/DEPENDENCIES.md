# Versions and official references

Selected Flutter: **3.35.7 stable** (Dart 3.9.x). Android API 24+; compile/target 36 and NDK 27.0.12077973 follow the Flutter extension. Java 17, AGP 8.9.1, Kotlin 2.1.0, Gradle 8.12 follow the selected Flutter Android template.

Direct runtime packages pinned:

| Package | Version | Published requirement checked |
|---|---|---|
| webview_flutter | 4.13.0 | Dart ^3.6, Flutter >=3.27 |
| webview_flutter_android | 4.10.0 | Dart ^3.6, Flutter >=3.27 |
| webview_flutter_wkwebview | 3.23.0 | Dart ^3.6, Flutter >=3.27; federated dependency only, no iOS app target |
| flutter_secure_storage | 9.2.4 | Dart >=2.12 <4, Flutter >=2.0; encryptedSharedPreferences at constructor |

Transitive dependency versions and SHA-256 hashes are in `pubspec.lock`. The lockfile SDK lower bound is Dart 3.9 / Flutter 3.35.7. `package_config` was resolved down to 2.1.0 because its latest release needs Dart 3.11; it is a build/test transitive dependency, not an application feature. CI uses `--enforce-lockfile`, not an unbounded upgrade. Local dependency resolution used Dart 3.12.2 with the official Flutter 3.35.7 **source tree**; no runnable Flutter engine was installed. Compatibility of the full Android build remains to be confirmed by CI.

Official sources fetched/read during implementation:

- Flutter install platforms: https://docs.flutter.dev/install/manual (HTTP 200). Android/Termux is not a standard Flutter desktop build host.
- Flutter source release: https://github.com/flutter/flutter/tree/3.35.7
- Android template versions: https://github.com/flutter/flutter/blob/3.35.7/packages/flutter_tools/lib/src/android/gradle_utils.dart
- Android Flutter extension defaults: https://github.com/flutter/flutter/blob/3.35.7/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt
- WebView package metadata/source: https://pub.dev/packages/webview_flutter/versions/4.13.0 and https://pub.dev/api/packages/webview_flutter
- NavigationDelegate API including `onUrlChange`, `onSslAuthError`: https://pub.dev/documentation/webview_flutter/4.13.0/webview_flutter/NavigationDelegate-class.html (HTTP 200); package source `navigation_delegate.dart` checked for `SslAuthError.cancel()`.
- WebView controller docs: https://pub.dev/documentation/webview_flutter/4.13.0/webview_flutter/WebViewController-class.html
- Secure storage official README/source: https://pub.dev/packages/flutter_secure_storage/versions/9.2.4 (HTTP 200), package archive README and constructor options checked.
- OpenAI API reference: https://platform.openai.com/docs/api-reference/chat/create returned HTTP 403 to this environment. Instead the official SDK source was fetched to verify request path and fields: https://github.com/openai/openai-python/blob/main/src/openai/resources/chat/completions/completions.py (`POST /chat/completions`, `messages`, `model`, `stream`). No tools or response-format support assumed.
- Gradle wrapper official source: https://github.com/gradle/gradle/tree/v8.12.0/gradle/wrapper
- Gradle distribution checksum: https://services.gradle.org/distributions/gradle-8.12-bin.zip.sha256

Wrapper JAR SHA-256: `2db75c40782f5e8ba1fc278a5574bab070adccb2d21ca5a6e5ed840888448046` (checked again in workflow).
Distribution ZIP SHA-256: `7a00d51fb93147819aab76024feece20b6b84e420694101f276be952e08bef03` (enforced in wrapper properties).

DOM test dependency: jsdom 26.1.0, only a Node dev dependency, not included in APK. npm transitive versions/integrity are in `package-lock.json`.
