import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:safety_engine/safety_engine.dart';

import 'api.dart';
import 'exercises.dart';
import 'heart_rate.dart';
import 'services.dart';
import 'vitals.dart';

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

  /// 건강 앱 혈압 기록 읽기(운동 전 점검 자동 채우기). 없으면 손으로만 넣는다.
  BpReader? readBp;

  /// 건강 앱 심박 읽기(워치 맥박으로 맥박 칸 채우기).
  HrReader? readHr;

  /// 오늘 점검에 쓸 혈압: 팔 혈압계 최근 기록은 채우고, 워치 혈압은 참고로만.
  Future<VitalsSnapshot> latestVitals() async {
    final read = readBp;
    if (read == null) return VitalsSnapshot.empty;
    final now = DateTime.now();
    try {
      final from = now.subtract(const Duration(hours: 12));
      final bp = await read(from, now).timeout(const Duration(seconds: 5));
      final hr = await (readHr?.call(now.subtract(freshFor), now) ?? Future.value(<HrSample>[]))
          .timeout(const Duration(seconds: 5), onTimeout: () => <HrSample>[]);
      return pickVitals(bp, now, pulses: [for (final s in hr) (s.bpm, s.at)]);
    } catch (_) {
      return VitalsSnapshot.empty; // 못 읽으면 손으로 넣는다
    }
  }
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
    health = (me['health'] as Map?)?.cast<String, dynamic>();
    goal = (me['settings'] as Map?)?['goal'] as String?;
    notifyListeners();
  }

  /// 온보딩에서 고른 '운동해서 하고 싶은 일'(6-5). 홈에서 진행을 그 말로 보여 준다.
  String? goal;

  /// 가입 때 받은 건강 답변(질환·몸 상태 질문·박동기·의사 확인). PUT /me/health 와 같은 모양.
  Map<String, dynamic>? health;

  /// 단말 안전 엔진에 넘길 프로필. 운동 전 점검도 서버와 같은 프로필로 판정한다.
  Profile get profile {
    final h = health ?? const {};
    return Profile(
      age: age,
      conditions: ((h['conditions'] as List?) ?? const []).cast<String>().toSet(),
      parqRisk: h['parq_risk'] == true,
      doctorClearance: h['doctor_clearance'] == true,
      betaBlocker: h['beta_blocker'] == true,
      device: h['device'] as String?,
      doctorLimits: DoctorLimits.fromJson((h['doctor_limits'] as Map?)?.cast<String, dynamic>()),
    );
  }

  /// 하드 게이트(5-1): 막혀 있으면 이유 코드들, 아니면 빈 목록. 규칙·건강 답변이 없으면 판단 보류(빈 목록).
  List<String> get gateBlocks {
    final r = rules;
    if (r == null || health == null) return const [];
    try {
      return gateReasons(r, profile);
    } on ArgumentError {
      return const [];
    }
  }

  Future<void> saveHealth(Map<String, dynamic> h) async {
    await api.putHealth(h);
    health = h;
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
