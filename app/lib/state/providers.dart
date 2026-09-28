import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runway_core/runway_core.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/token_store.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// The device's calendar date. Overridden in tests.
final todayProvider = Provider<LocalDate>(
  (ref) => LocalDate.fromDateTime(DateTime.now()),
);

// ------------------------------------------------------------------ session

sealed class Session {
  const Session();
}

class SessionLoading extends Session {
  const SessionLoading();
}

class SignedOut extends Session {
  const SignedOut();
}

class SignedIn extends Session {
  final User user;

  /// True right after sign-up until the first-run setup is done or skipped.
  final bool needsSetup;
  const SignedIn(this.user, {this.needsSetup = false});
}

final sessionProvider = NotifierProvider<SessionController, Session>(
  SessionController.new,
);

class SessionController extends Notifier<Session> {
  ApiClient get _api => ref.read(apiClientProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);

  @override
  Session build() {
    _api.onUnauthorized = () => signOut();
    Future.microtask(_restore);
    return const SessionLoading();
  }

  Future<void> _restore() async {
    final token = await _store.read();
    if (token == null) {
      state = const SignedOut();
      return;
    }
    _api.token = token;
    try {
      state = SignedIn(await _api.me());
    } on ApiException catch (e) {
      if (e.status == 401) {
        await signOut();
      } else {
        // Offline: stay signed in with what we know; screens will show errors.
        state = const SignedIn(User(id: '', email: ''));
      }
    }
  }

  Future<void> signIn(String email, String password) async {
    final r = await _api.login(email.trim(), password);
    await _start(r.token, r.user, needsSetup: false);
  }

  Future<void> signUp(String email, String password, String? name) async {
    final r = await _api.register(email.trim(), password, name);
    await _start(r.token, r.user, needsSetup: true);
  }

  Future<void> _start(
    String token,
    User user, {
    required bool needsSetup,
  }) async {
    _api.token = token;
    await _store.write(token);
    state = SignedIn(user, needsSetup: needsSetup);
  }

  void finishSetup() {
    final s = state;
    if (s is SignedIn) state = SignedIn(s.user);
  }

  void updateUser(User user) {
    final s = state;
    if (s is SignedIn) state = SignedIn(user, needsSetup: s.needsSetup);
  }

  Future<void> signOut() async {
    _api.token = null;
    await _store.clear();
    ref.invalidate(monthProvider);
    ref.invalidate(categoriesProvider);
    state = const SignedOut();
  }
}

// --------------------------------------------------------------------- data

final selectedMonthProvider = NotifierProvider<SelectedMonth, YearMonth>(
  SelectedMonth.new,
);

class SelectedMonth extends Notifier<YearMonth> {
  @override
  YearMonth build() => ref.watch(todayProvider).yearMonth;

  void set(YearMonth m) => state = m;
  void previous() => state = state.previous;
  void next() => state = state.next;
}

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final list = await ref.watch(apiClientProvider).categories();
  return list..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

final monthProvider = FutureProvider.family<MonthData, YearMonth>((
  ref,
  month,
) async {
  return ref.watch(apiClientProvider).month(month, ref.watch(todayProvider));
});
