import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_coach/core/vitals.dart';

import 'fakes.dart';

final now = DateTime.now();
BpReading arm(int s, int d, Duration ago, {int? pulse, String source = 'ble_upper_arm'}) =>
    BpReading(s, d, now.subtract(ago), source: source, sourceName: 'OMRON connect', pulse: pulse);
BpReading watch(int s, int d, Duration ago) =>
    BpReading(s, d, now.subtract(ago), source: 'watch', sourceName: 'SMART-TIME PRO');

/// 홈 → 운동 시작하기 → 점검 첫 화면
Future<void> openCheck(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tapText(tester, '운동 시작하기');
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> answerRest(WidgetTester tester) async {
  await tapText(tester, '다음');
  await tapText(tester, '아니요, 괜찮아요');
  await tapText(tester, '아니요');
  await tapText(tester, '아니요');
  await tapText(tester, '결과 보기');
  await tester.pump(const Duration(milliseconds: 600));
}

String field(WidgetTester tester, String label) =>
    tester.widget<TextField>(find.widgetWithText(TextField, label)).controller!.text;

void main() {
  group('출처 가르기', () {
    test('워치 앱·팔 혈압계 앱·건강 앱 직접 입력·모르는 앱', () {
      expect(classifySource('com.sma.smartv3.pro', 'SMART-TIME PRO'), 'watch');
      expect(classifySource('com.example.x', 'SMART-TIME PRO'), 'watch');
      expect(classifySource('jp.co.omron.healthcare.connect', 'OMRON connect'), 'ble_upper_arm');
      expect(classifySource('com.withings.wiScaleNG', 'Withings'), 'ble_upper_arm');
      expect(classifySource('com.apple.Health', '건강'), 'manual');
      expect(classifySource('com.unknown.bp', '어떤 앱'), 'unknown');
    });
  });

  group('점검에 쓸 기록 고르기', () {
    test('30분 안의 팔 혈압계 기록은 채우고, 가장 최근 것을 쓴다', () {
      final v = pickVitals([arm(150, 90, const Duration(minutes: 20)), arm(128, 82, const Duration(minutes: 5))], now);
      expect(v.fresh!.systolic, 128);
      expect(v.stale, isNull);
    });

    test('30분이 지난 기록은 채우지 않고 다시 재도록', () {
      final v = pickVitals([arm(128, 82, const Duration(minutes: 45))], now);
      expect(v.fresh, isNull);
      expect(v.stale!.systolic, 128);
    });

    test('워치 혈압·모르는 출처는 점검에 쓰지 않는다', () {
      final v = pickVitals([watch(120, 80, const Duration(minutes: 1)), arm(120, 80, const Duration(minutes: 1), source: 'unknown')], now);
      expect(v.fresh, isNull);
      expect(v.stale, isNull);
      expect(v.watch!.systolic, 120);
    });
  });

  testWidgets('건강 앱 팔 혈압계 기록을 미리 채우고 출처를 함께 보낸다', (tester) async {
    final h = Harness();
    h.state.readBp = (from, to) async => [arm(128, 82, const Duration(minutes: 5), pulse: 71), watch(150, 95, const Duration(hours: 1))];
    await h.start(tester);
    await openCheck(tester);
    expect(field(tester, '높은 쪽 숫자(수축기)'), '128');
    expect(field(tester, '낮은 쪽 숫자(이완기)'), '82');
    expect(field(tester, '맥박'), '71');
    expect(find.textContaining('건강 앱의 혈압계 기록을 넣어 두었어요 (OMRON connect, 5분 전)'), findsOneWidget);
    expect(find.textContaining('참고: 워치 혈압 150/95'), findsOneWidget);
    await answerRest(tester);
    final body = h.server.bodies('POST /me/prechecks').single;
    expect(body['systolic'], 128);
    expect(body['bp_source'], 'ble_upper_arm');
    expect(body['hr_source'], 'ble_upper_arm');
    expect(find.text('초록 · 평소대로 해요'), findsOneWidget);
  });

  testWidgets('채운 숫자를 고치면 손으로 넣은 값으로 보낸다', (tester) async {
    final h = Harness();
    h.state.readBp = (from, to) async => [arm(128, 82, const Duration(minutes: 5))];
    await h.start(tester);
    await openCheck(tester);
    expect(find.textContaining('맥박은 직접 넣어 주세요'), findsOneWidget);
    await enter(tester, '높은 쪽 숫자(수축기)', '132');
    await enter(tester, '맥박', '70');
    await answerRest(tester);
    final body = h.server.bodies('POST /me/prechecks').single;
    expect(body['systolic'], 132);
    expect(body['bp_source'], 'manual');
    expect(body['hr_source'], 'manual');
  });

  testWidgets('워치 혈압만 있으면 채우지 않고, 높으면 팔 혈압계로 다시 재도록', (tester) async {
    final h = Harness();
    h.state.readBp = (from, to) async => [watch(172, 98, const Duration(minutes: 10))];
    await h.start(tester);
    await openCheck(tester);
    expect(field(tester, '높은 쪽 숫자(수축기)'), '');
    expect(find.textContaining('참고: 워치 혈압 172/98'), findsOneWidget);
    expect(find.text('워치 혈압이 높게 나왔어요. 팔에 감는 혈압계로 꼭 다시 재 주세요.'), findsOneWidget);
    await tapText(tester, '다음');
    expect(find.textContaining('세 숫자를 모두 넣어 주세요'), findsOneWidget); // 비운 채로는 못 넘어감
  });

  testWidgets('건강 앱을 못 읽으면 손으로 넣는다', (tester) async {
    final h = Harness();
    h.state.readBp = (from, to) async => throw Exception('권한 없음');
    await h.start(tester);
    await openCheck(tester);
    expect(field(tester, '높은 쪽 숫자(수축기)'), '');
    expect(find.text('의자에 앉아 5분 쉰 뒤, 팔에 감는 혈압계로 재 주세요.'), findsOneWidget);
  });
}
