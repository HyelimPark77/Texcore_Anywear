import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:safety_engine/safety_engine.dart';

import 'api.dart';
import 'exercises.dart';
import 'heart_rate.dart';
import 'services.dart';

/// 앱 전체 상태. 화면은 AppScope.of(context)로 꺼내 쓴다.
class AppState extends ChangeNotifier {
  final ApiClient api;
  final Speaker speaker;
  final Dialer dialer;
  final LocalStore store;

  /// 개발 중(draft 규칙)에만 true. 운영 빌드는 자문단 승인 번들만 받는다.
  final bool allowDraftRules;

  RuleBundle? rules;

  /// 운동 중 심박 출처(디즈먼트 워치 = PC 브리지). 없으면 폰만으로(숨찬 정도 질문).
  HeartRateSource? watch;
  String watchStatus = '워치 연결 안 됨';
  HrSample? lastHr;

  /// 운동 동작 안내 콘텐츠(assets/exercises.json). 없으면 종류별 짧은 문장만 말한다.
  ExerciseLibrary? exercises;
  StreamSubscription? _watchSubs, _watchStatusSub;
  String? name;
  int? birthYear;
  double textScale = 1.0; // 3단계: 1.0 / 1.25 / 1.5
  bool voiceOn = true;

  AppState({required this.api, required this.speaker, required this.dialer, required this.store, this.allowDraftRules = false, this.watch});

  bool get watchConnected => watch?.connected ?? false;

  Future<void> connectWatch() async {
    final w = watch;
    if (w == null) return;
    _watchStatusSub ??= w.status.listen((s) {
      watchStatus = s;
      notifyListeners();
    });
    _watchSubs ??= w.samples.listen((hr) {
      lastHr = hr;
      notifyListeners();
    });
    try {
      await w.connect();
      watchStatus = '워치 연결됨';
    } catch (_) {}
    notifyListeners();
  }

  Future<void> disconnectWatch() async {
    await watch?.close();
    watchStatus = '워치 연결 안 됨';
    lastHr = null;
    notifyListeners();
  }

  int get age => DateTime.now().year - (birthYear ?? DateTime.now().year - 70);

  Future<void> restore() async {
    api.token = await store.read('token');
    textScale = double.tryParse(await store.read('textScale') ?? '') ?? 1.0;
    final cached = await store.read('rules');
    if (cached != null) {
      try {
        rules = RuleBundle.fromEnvelope(cached, requireApproved: !allowDraftRules);
      } on RuleError {
        rules = null;
      }
    }
  }

  bool get loggedIn => api.token != null;

  Future<void> saveToken(String token) async {
    api.token = token;
    await store.write('token', token);
  }

  Future<void> logout() async {
    api.token = null;
    await store.write('token', null);
    notifyListeners();
  }

  /// 운동 중 오프라인 판정에 쓸 규칙 번들. 받은 뒤 해시를 확인하고 기기에 보관한다.
  Future<void> refreshRules() async {
    try {
      final body = await api.rulesBundle();
      rules = RuleBundle.fromEnvelope(body, requireApproved: !allowDraftRules);
      await store.write('rules', body);
    } catch (_) {
      // 받지 못하면 보관해 둔 번들을 계속 쓴다(없으면 운동 시작을 막는다).
    }
    notifyListeners();
  }

  Future<void> loadMe() async {
    final me = await api.me();
    name = me['name'] as String?;
    birthYear = me['birth_year'] as int?;
    notifyListeners();
  }

  void cycleTextScale() {
    textScale = textScale >= 1.5 ? 1.0 : textScale + 0.25;
    store.write('textScale', '$textScale');
    notifyListeners();
  }

  Future<void> say(String text) async {
    if (voiceOn) await speaker.say(text);
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
