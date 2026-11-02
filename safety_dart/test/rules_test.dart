import 'dart:convert';
import 'dart:io';

import 'package:safety_engine/safety_engine.dart';
import 'package:test/test.dart';

import 'support.dart';

Map<String, dynamic> _copy(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

void main() {
  final rules = loadYamlRules();
  final envelope = File('test/fixtures/bundle_draft.json').readAsStringSync();

  test('단말이 계산한 번들 해시 = 서버(Python) 해시', () {
    final env = jsonDecode(envelope) as Map<String, dynamic>;
    // 이 테스트가 깨지면 규칙 YAML이 바뀐 것: python tools/export_bundle.py --allow-draft 로 픽스처를 다시 만든다.
    expect(rules.sha256, env['sha256']);
    expect(RuleBundle.sha256Of(env['rules'] as Map<String, dynamic>), env['sha256']);
  });

  test('서버 응답에서 번들 받기: draft는 운영에서 거부, 변조는 항상 거부', () {
    expect(() => RuleBundle.fromEnvelope(envelope), throwsA(isA<RuleError>()));
    expect(RuleBundle.fromEnvelope(envelope, requireApproved: false).version, '0.2.0-draft');
    final tampered = envelope.replaceFirst('"upper": 180', '"upper": 185');
    expect(tampered, isNot(envelope));
    expect(() => RuleBundle.fromEnvelope(tampered, requireApproved: false), throwsA(isA<RuleError>()));
  });

  final invalid = <String, void Function(Map<String, dynamic>)>{
    'gap': (d) => d['precheck']['bands']['systolic'][1]['upper'] = 158,
    'ceiling_pct': (d) => d['session']['ceiling_pct']['absolute_max'] = 0.9,
    'RED': (d) => d['allowance']['RED']['allowed'] = true,
    'overlap': (d) => (d['precheck']['yellow_symptoms'] as List).add('chest_pain'),
    'approved_by': (d) => d['meta']['status'] = 'approved',
  };
  invalid.forEach((msg, mutate) {
    test('잘못된 번들 거부: $msg', () {
      final d = _copy(rules.data);
      mutate(d);
      expect(() => RuleBundle.fromMap(d), throwsA(isA<RuleError>().having((e) => e.message, 'message', contains(msg))));
    });
  });

  test('모르는 증상·출처는 거부', () {
    const p = Profile(age: 72);
    expect(() => preCheck(rules, p, const Vitals(systolic: 130, diastolic: 70, restingHr: 70), symptoms: ['chestpain']),
        throwsArgumentError);
    expect(() => preCheck(rules, p, const Vitals(systolic: 130, diastolic: 70, restingHr: 70, bpSource: 'wrist')),
        throwsArgumentError);
  });

  test('값이 나빠지면 판정이 좋아지지 않는다(수축기 전 범위)', () {
    const p = Profile(age: 72);
    var prev = -1;
    for (var sbp = 130; sbp <= 259; sbp++) {
      final s = severity(preCheck(rules, p, Vitals(systolic: sbp, diastolic: 70, restingHr: 70)).light);
      expect(s, greaterThanOrEqualTo(prev));
      prev = s;
    }
  });

  test('운동 중 시간 역행·이상한 RPE 거부', () {
    final m = SessionMonitor(rules, 111, hrGrade: 'A');
    m.onHr(10, 100);
    expect(() => m.onHr(9, 100), throwsArgumentError);
    expect(() => m.onRpe(11, 25), throwsArgumentError);
  });

  test('sink는 행동이 있을 때만 기록', () {
    final log = <Map<String, dynamic>>[];
    final m = SessionMonitor(rules, 111, hrGrade: 'A', sink: log.add);
    for (var t = 0; t <= 31; t++) {
      m.onHr(t, 115);
    }
    expect(log, hasLength(1));
    expect(log.single['actions'][0]['code'], 'HR_OVER_CEILING');
  });
}
