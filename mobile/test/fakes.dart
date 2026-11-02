import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safety_engine/safety_engine.dart';
import 'package:senior_coach/core/api.dart';
import 'package:senior_coach/core/app_state.dart';
import 'package:senior_coach/core/heart_rate.dart';
import 'package:senior_coach/core/services.dart';
import 'package:senior_coach/main.dart';

final bundleBody = File('../safety_dart/test/fixtures/bundle_draft.json').readAsStringSync();

class FakeSpeaker implements Speaker {
  final said = <String>[];
  @override
  Future<void> say(String text) async => said.add(text);
  @override
  Future<void> setRate(double rate) async {}
}

class FakeDialer implements Dialer {
  final calls = <String>[];
  @override
  Future<void> call(String number) async => calls.add(number);
}

class FakeWatch implements HeartRateSource {
  final _samples = StreamController<HrSample>.broadcast();
  final _status = StreamController<String>.broadcast();
  bool _on = false;
  @override
  String get grade => 'B';
  @override
  String get name => '디즈먼트 워치';
  @override
  bool get connected => _on;
  bool isRealtime = true;
  @override
  bool get realtime => isRealtime;
  @override
  Stream<HrSample> get samples => _samples.stream;
  @override
  Stream<String> get status => _status.stream;
  @override
  Future<void> connect() async {
    _on = true;
    _status.add('워치 연결됨');
  }

  @override
  Future<void> close() async => _on = false;
  void beat(int bpm) => _samples.add(HrSample(bpm, DateTime.now(), battery: 70));
}

class MemoryStore implements LocalStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String? value) async => value == null ? data.remove(key) : data[key] = value;
}

typedef Handler = Object? Function(Map<String, dynamic> body);

/// 서버 흉내. 경로별 응답을 바꿔 끼우고, 받은 요청을 기록한다.
class FakeServer {
  final requests = <(String, String, Map<String, dynamic>)>[];
  final routes = <String, Handler>{};

  FakeServer() {
    routes.addAll({
      'POST /auth/otp/request': (_) => {'sent': true},
      'POST /auth/otp/verify': (b) => b.containsKey('name')
          ? {'token': 'tok', 'user': {'id': 1}}
          : (422, {'detail': '처음 오셨네요. 이름과 사용자 종류가 필요해요'}),
      'GET /me': (_) => {'id': 1, 'name': '김영자', 'birth_year': 1952},
      'POST /me/consents': (_) => {'ok': true},
      'PUT /me/health': (_) => {'saved': true},
      'GET /rules/safety': (_) => bundleBody,
      'GET /me/today': (_) => today(),
      'POST /me/prechecks': (b) => precheck('GREEN'),
      'POST /me/sessions': (b) => {
            'session_id': 7,
            'minutes': b['easier'] == true ? 1 : 3,
            'activity': {'id': 'chair_march', 'name': '의자에 앉아 제자리 걷기', 'kind': 'aerobic'},
            'hr_limits': {'ceiling': 109, 'ceiling_pct': 0.7, 'max_hr': 156.2, 'zone_lower': 100, 'mode': 'zone'},
            'light': 'GREEN',
          },
      'POST /me/sessions/7/events': (b) => {'stored': (b['events'] as List).length},
      'POST /me/sessions/7/finish': (b) => {
            'message': '해내셨어요! 오늘 도장 하나 찍었습니다.',
            'slow_recovery': false,
            'cheer': {'from': '이지은', 'text': '엄마 최고', 'audio_url': null},
            'rewards': {'today': {'stamp': true, 'reasons': ['SESSION_STARTED']}, 'streak': 1, 'weekly_stamps': 1},
          },
      'POST /me/emergency': (_) => {'guardians_alerted': 1},
      'GET /me/week': (_) => {'days': [], 'streak': 0},
      'GET /me/guardians': (_) => [],
    });
  }

  static Map<String, dynamic> today() => {
        'date': '2026-11-02',
        'state': 'FEAR',
        'ladder': {'minutes': 3, 'level': 0, 'restart_pending': false},
        'reengagement': {'prompts': []},
        'ask_time_change': false,
        'rewards': {'today': {'stamp': false}, 'streak': 0, 'weekly_stamps': 0},
        'has_new_cheer': true,
      };

  static Map<String, dynamic> precheck(String outcome, {String action = 'EXERCISE'}) => {
        'precheck_id': 11,
        'outcome': outcome,
        'reasons': [],
        'plan': {
          'action': action,
          'minutes': 3,
          'activity_id': 'chair_march',
          'easier': {'minutes': 1, 'activity_id': 'chair_march'},
          'message': {'id': 'f01', 'intent': 'today_FEAR', 'text': '자, 오늘은 3분만 해 볼까요?'},
        },
      };

  List<Map<String, dynamic>> bodies(String key) => [for (final r in requests) if ('${r.$1} ${r.$2}' == key) r.$3];

  http.Client client() => MockClient((req) async {
        final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
        final key = '${req.method} ${req.url.path}';
        requests.add((req.method, req.url.path, body));
        final h = routes[key];
        if (h == null) return http.Response('{"detail":"없는 경로 $key"}', 404);
        final out = h(body);
        if (out is (int, Object)) return http.Response.bytes(utf8.encode(jsonEncode(out.$2)), out.$1);
        if (out is String) return http.Response.bytes(utf8.encode(out), 200);
        return http.Response.bytes(utf8.encode(jsonEncode(out)), 200, headers: {'content-type': 'application/json'});
      });
}

class Harness {
  final server = FakeServer();
  final speaker = FakeSpeaker();
  final dialer = FakeDialer();
  final store = MemoryStore();
  final watch = FakeWatch();
  late final AppState state;

  Harness({bool loggedIn = true, bool withRules = true}) {
    state = AppState(
      api: ApiClient('http://test', client: server.client(), token: loggedIn ? 'tok' : null),
      speaker: speaker,
      dialer: dialer,
      store: store,
      allowDraftRules: true,
      watch: watch,
    );
    state.name = '김영자';
    state.birthYear = 1952;
    if (withRules) state.rules = RuleBundle.fromEnvelope(bundleBody, requireApproved: false);
  }

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SeniorCoachApp(state: state));
    await tester.pump();
    await tester.pump();
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text).last; // 전환 중 아래 화면이 아니라 맨 위 화면
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50)); // 가짜 서버 호출이 이어지는 경우
}

Future<void> enter(WidgetTester tester, String label, String value) async {
  await tester.enterText(find.widgetWithText(TextField, label), value);
  await tester.pump();
}

Future<void> seconds(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}
