# Validation performed in Termux

Host: Android ARM64 (`aarch64`, ABI `arm64-v8a`). Dart 3.12.2 native Android, Node 26.3.1. Flutter binary, Java/Javac, Gradle, sdkmanager and configured Android SDK were not available. ADB exists but no connected test target/session was used.

## Executed successfully

- `dart analyze` over application, tests and tool source: **No issues found**. Resolution used the official Flutter 3.35.7 source archive and its engine Dart interface source, with SDK version metadata for pub. This is static analysis with native Dart, **not `flutter analyze` with an installed engine**.
- `dart format --output=none --set-exit-if-changed lib test tool/core_checks.dart`: clean.
- `dart run tool/core_checks.dart`: **18 checks passed**. Also ran `bash tool/check_core.sh` in an isolated temporary directory without a Flutter pubspec/config, proving the pure-Dart suite runs on Termux from a clean checkout.
  - All allowed actions and strict JSON schema.
  - Unknown action/extra field/missing field/type/boundary rejection.
  - Stale snapshot, missing/disabled/sensitive elements, invalid target kind/select option.
  - Navigation schemes, default HTTPS address, HTTPS-only AI endpoint.
  - DeepSeek Pro defaults (`https://api.deepseek.com`, `deepseek-v4-pro`), correct Chat Completions URL, and empty bundled key; missing-key validation still rejects Run.
  - Sensitive text redaction and URL query removal.
  - Maximum steps and bounded request/parser retries.
  - Fresh snapshot after retry and after takeover/new Run.
  - Three unchanged iterations stop the loop.
  - User denial prevents execution.
  - Stop during observation, request, confirmation, execution and settle prevents following actions.
  - Uncertain execution failure is not retried.
  - finish/ask_user terminate without executor call.
- `npm ci --ignore-scripts --no-audit --no-fund` / `npm test`: **7 DOM tests passed** using jsdom 26.1.0.
  - Password/OTP/hidden/echoed input values and URL query/fragment absent from snapshot.
  - Hostile-looking text remains data, not executable code.
  - Native input setter and input/change events.
  - Select + click + delayed content verified from fixture DOM.
  - Unknown/disabled/sensitive/reused/stale action rejection.
  - DOM replacement, attribute change, user input and SPA URL change invalidate references.
  - External schemes/bounds and manual-only login form controls.
- `node --check assets/observer.js` and DOM test source: passed.
- `FLUTTER_ROOT=<official-source-tree> dart pub get --enforce-lockfile`: resolved locked packages, SDK lower bound Dart 3.9 / Flutter 3.35.7. Native Dart version differs from the pinned CI SDK; CI is the authoritative dependency/build check.
- `npm audit --audit-level=high`: 0 vulnerabilities reported at execution time (not a guarantee about future advisories).
- XML parsing of Android manifest/styles/vector icon: passed.
- `bash -n android/gradlew tool/check_core.sh`: passed.
- Official Gradle wrapper JAR SHA-256 matched the value checked in workflow; distribution checksum fetched from official Gradle endpoint and pinned in wrapper properties.
- `git diff --check`: clean. Basic known-token-pattern scan of deliverable source: no matches. This is not a comprehensive secret audit. No real AI keys, website accounts or paid AI calls were used.

## Hosted build attempts after user authorization

GitHub CLI 2.95.0 is authenticated as the repository owner. With user authorization, source was scanned for common credential patterns, committed and pushed to **private** repository https://github.com/anzmage/pocket-browser-ai. No AI key, credential file, local caches or unrelated project files were uploaded.

- Build dispatch at source commit `15a2b0c`: https://github.com/anzmage/pocket-browser-ai/actions/runs/39421288514 — `completed/startup_failure`, zero jobs, no logs/artifacts.
- After pinning Actions to current official releases at commit `1596bc1`: https://github.com/anzmage/pocket-browser-ai/actions/runs/39421618299 — same `startup_failure`, zero jobs.
- Minimal `runner-check.yml` at commit `8b4839a`, no external action or build tool, just `printf`: https://github.com/anzmage/pocket-browser-ai/actions/runs/39421794826 — also `startup_failure`, zero jobs.
- Repository Actions permissions API reports enabled / all actions allowed. GitHub Status reports operational. REST checks provide no detailed startup annotation or error log. Billing API is unavailable with the current token's scopes; no extra scopes, billing changes, charges, visibility changes or alternate-server builds were attempted.
- This demonstrates failure before a hosted runner/build starts; it does **not** identify a specific billing, account, or service cause. The next necessary diagnostic is the detailed error visible to the owner on the Actions run page. Do not repeat identical dispatches blindly.

## Not executed / outstanding
- No `flutter test`, `flutter analyze`, Gradle build or APK build was executed; Flutter engine and Android build host are unavailable here.
- No real Android WebView interaction, Android lifecycle/Back/keyboard test, secure-storage instrumentation test, real provider request or live website login was performed.
- jsdom overrides element geometry because it has no rendering/layout. It validates DOM contracts, not actual viewport hit-testing or Android framework behavior.
- Official OpenAI API web documentation returned HTTP 403; request shape was cross-checked against the official OpenAI SDK source instead.

Next: inspect the startup error on the linked GitHub Actions page and resolve the reported account/platform blocker; then dispatch the Android workflow again. After a green build, install its artifact and follow the fixture smoke test in README. Inspect the actual on-device behavior before using real account tasks or sensitive pages. Never report a build/APK/website compatibility success merely from these static/mock checks.
