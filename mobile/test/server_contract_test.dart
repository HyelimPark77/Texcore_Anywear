// 실제 서버와의 계약 테스트. 앱이 쓰는 응답 키가 서버에 정말 있는지 확인한다(가짜 서버만으로는 못 잡는 어긋남).
// 서버 실행: SMS_FILE=/tmp/sms.txt python ../server/tests/e2e_server.py 8766
// 실행: E2E_SERVER=http://127.0.0.1:8766 SMS_FILE=/tmp/sms.txt flutter test test/server_contract_test.dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safety_engine/safety_engine.dart';
import 'package:senior_coach/core/api.dart';

void main() {
  final base = Platform.environment['E2E_SERVER'];
  final smsFile = Platform.environment['SMS_FILE'];
  final skip = base == null || smsFile == null ? 'E2E_SERVER·SMS_FILE이 없으면 건너뜀' : null;

  test('가입부터 운동 완료·응급 보고까지 실제 서버 응답 모양', () async {
    final api = ApiClient(base!);
    const phone = '01077770000';
    await api.requestOtp(phone);
    final code = File(smsFile!).readAsLinesSync().lastWhere((l) => l.startsWith(phone)).split(' ')[1];

    // 처음 온 사람: 이름 없이 확인하면 422, 같은 번호로 정보를 채우면 가입
    await expectLater(api.verifyOtp(phone, code), throwsA(isA<ApiException>().having((e) => e.status, 'status', 422)));
    expect(await api.verifyOtp(phone, code, name: '김영자', birthYear: 1952), isNotEmpty);
    final me = await api.me();
    expect(me['name'], '김영자');
    expect(me['birth_year'], 1952);

    await api.consent('health', true);
    await api.putHealth({'conditions': [], 'beta_blocker': false, 'device': null, 'doctor_limits': {}, 'parq_risk': false});

    // 규칙 번들: 서버 해시 = 단말 재계산 해시
    final bundle = RuleBundle.fromEnvelope(await api.rulesBundle(), requireApproved: false);
    expect(bundle.version, '0.2.0-draft');

    final today = await api.today();
    expect(today['ladder']['minutes'], 3);
    expect(today['ladder']['restart_pending'], isFalse);
    expect(today['reengagement']['prompts'], isA<List>());
    expect(today['rewards']['streak'], 0);
    expect(today['rewards']['weekly_stamps'], 0);
    expect(today['has_new_cheer'], isFalse);
    expect(today, contains('ask_time_change'));

    final body = {'systolic': 130, 'diastolic': 80, 'resting_hr': 70, 'symptoms': <String>[], 'conditions': <String>[]};
    final pre = await api.precheck(body);
    // 서버 판정 = 단말 판정
    final local = preCheck(bundle, const Profile(age: 74), const Vitals(systolic: 130, diastolic: 80, restingHr: 70));
    expect(pre['outcome'], local.outcome);
    final plan = pre['plan'] as Map;
    expect(plan['action'], 'EXERCISE');
    expect(plan['minutes'], 3);
    expect(plan['easier']['minutes'], 1);
    expect(plan['message']['text'], isA<String>());
    expect(pre['precheck_id'], isA<int>());

    final s = await api.startSession(pre['precheck_id'] as int);
    expect(s['minutes'], 3);
    expect(s['activity']['name'], isA<String>());
    expect(s['activity']['kind'], isIn(['aerobic', 'strength', 'balance']));
    expect(s['hr_limits']['ceiling'], hrLimits(bundle, const Profile(age: 74)).ceiling);
    expect(s['light'], 'GREEN');

    // 단말 엔진이 낸 행동을 그대로 올린다
    final events = <Map<String, dynamic>>[];
    final m = SessionMonitor(bundle, s['hr_limits']['ceiling'] as int, sink: events.add);
    for (var t = 1; t <= 120; t++) {
      m.tick(t);
    }
    expect(events.single['actions'][0]['kind'], 'ASK_RPE');
    await api.sessionEvents(s['session_id'] as int, [
      for (final e in events) {'t': e['t'], 'event': e['event'], 'value': e['value'], 'actions': e['actions']},
    ]);

    final done = await api.finish(s['session_id'] as int, {'completed': true, 'minutes': 3.0, 'max_rpe': 11, 'stopped': false});
    expect(done['message'], isA<String>());
    expect(done['rewards']['streak'], 1);
    expect(done, contains('cheer'));

    await api.emergency({'code': 'EM_USER_NOT_OK', 'severe': false});
    final week = await api.week();
    final last = (week['days'] as List).last as Map;
    expect(last['stamp'], isTrue);
    expect(last['minutes'], 3);
    expect(DateTime.tryParse(last['date'] as String), isNotNull);
    expect(await api.guardians(), isEmpty);
  }, skip: skip);
}
