import 'dart:async';
import 'models.dart';

class Cancelled implements Exception {}

class RunToken {
  bool cancelled = false;
  final _done = Completer<void>();
  final List<void Function()> _callbacks = [];
  void check() {
    if (cancelled) throw Cancelled();
  }

  void onCancel(void Function() callback) {
    if (cancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    for (final c in _callbacks) {
      c();
    }
    _callbacks.clear();
    _done.complete();
  }

  Future<T> guard<T>(
    Future<T> future, {
    Duration timeout = const Duration(seconds: 45),
  }) => Future.any<T>([
    future,
    _done.future.then<T>((_) => throw Cancelled()),
  ]).timeout(timeout);
  Future<void> delay(int ms) async {
    check();
    await guard(Future<void>.delayed(Duration(milliseconds: ms)));
    check();
  }
}

abstract interface class AiProvider {
  Future<String> next(
    String goal,
    PageSnapshot page,
    List<String> history,
    RunToken token,
  );
}

abstract interface class AgentPage {
  Future<PageSnapshot> observe(RunToken token);
  Future<void> execute(
    AgentAction action,
    PageSnapshot snapshot,
    RunToken token,
  );
  Future<void> settle(RunToken token);
}

typedef ConfirmAction =
    Future<bool> Function(AgentAction action, PageSnapshot page);

class AgentLoop {
  final AiProvider provider;
  final AgentPage page;
  final ConfirmAction confirm;
  final void Function(String) onEvent;
  final int maxSteps, maxRetries;
  RunToken? _token;
  bool get running => _token != null;
  AgentLoop({
    required this.provider,
    required this.page,
    required this.confirm,
    required this.onEvent,
    this.maxSteps = 15,
    this.maxRetries = 2,
  });
  void stop() {
    _token?.cancel();
  }

  Future<void> run(String goal) async {
    if (running) return;
    final token = RunToken();
    _token = token;
    final history = <String>[];
    void log(String s) {
      history.add(s);
      onEvent(s);
    }

    try {
      if (maxSteps < 1 || maxSteps > 50 || maxRetries < 0 || maxRetries > 3) {
        throw const SafetyException('Batas agent tidak valid.');
      }
      var unchanged = 0;
      for (var step = 1; step <= maxSteps; step++) {
        token.check();
        var before = await token.guard(page.observe(token));
        token.check();
        AgentAction? action;
        for (var retry = 0; retry <= maxRetries; retry++) {
          try {
            token.check();
            final response = await token.guard(
              provider.next(
                goal,
                before,
                history.length > 8
                    ? history.sublist(history.length - 8)
                    : history,
                token,
              ),
            );
            token.check();
            action = AgentAction.parse(response)..validate(before);
            break;
          } on Cancelled {
            rethrow;
          } catch (_) {
            token.check();
            log(
              'Respons/request AI tidak valid (percobaan ${retry + 1}/${maxRetries + 1}).',
            );
            if (retry == maxRetries)
              throw const SafetyException(
                'Batas retry AI tercapai. Periksa provider/model.',
              );
            await token.delay(400 * (retry + 1));
            before = await token.guard(page.observe(token));
          }
        }
        final a = action!;
        token.check();
        log('Langkah $step/$maxSteps: ${a.description}');
        if (a.kind == 'finish' || a.kind == 'ask_user') {
          log(
            '${a.kind == 'finish' ? 'Ringkasan model (periksa hasil)' : 'Butuh pengguna'}: ${redact(a.data[a.kind == 'finish' ? 'summary' : 'question'] as String)}',
          );
          return;
        }
        if (a.needsConfirmation) {
          final allowed = await token.guard(
            confirm(a, before),
            timeout: const Duration(minutes: 5),
          );
          token.check();
          if (!allowed) {
            log('Aksi ditolak. Agent berhenti; Anda dapat melanjutkan manual.');
            return;
          }
        }
        token.check();
        // Execution is never retried: a timeout may mean a mutation already happened.
        await token.guard(
          page.execute(a, before, token),
          timeout: const Duration(seconds: 12),
        );
        token.check();
        await token.guard(
          page.settle(token),
          timeout: const Duration(seconds: 12),
        );
        token.check();
        final after = await token.guard(page.observe(token));
        token.check();
        final changed = before.fingerprint != after.fingerprint;
        log(
          changed
              ? 'Perubahan halaman teramati; bukan bukti tugas selesai.'
              : 'Tidak ada perubahan teramati.',
        );
        unchanged = changed ? 0 : unchanged + 1;
        if (unchanged >= 3)
          throw const SafetyException(
            'Tiga aksi tanpa kemajuan. Ambil alih dan periksa halaman.',
          );
      }
      log('Batas $maxSteps langkah tercapai. Agent berhenti.');
    } on Cancelled {
      onEvent('Dihentikan. Aksi yang sudah dikirim tidak dapat dibatalkan.');
    } on TimeoutException {
      onEvent('Timeout. Tidak mengulang aksi; periksa halaman secara manual.');
    } on SafetyException catch (e) {
      onEvent(e.message);
    } catch (_) {
      onEvent(
        'Gagal membaca/menjalankan halaman. Periksa koneksi atau lanjut manual.',
      );
    } finally {
      token.cancel();
      _token = null;
    }
  }
}
