import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_coach/core/heart_rate.dart';
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

    test('팔 혈압계 기록이 없으면 3시간 안의 워치 혈압으로 채운다', () {
      final v = pickVitals([watch(120, 80, const Duration(hours: 2))], now, pulses: [(68, now.subtract(const Duration(minutes: 10)))]);
      expect(v.fill!.source, 'watch');
      expect(v.watchPulse, 68);
    });

    test('팔 혈압계 기록이 있으면 워치보다 먼저', () {
      final v = pickVitals([watch(118, 78, const Duration(minutes: 1)), arm(128, 82, const Duration(minutes: 10))], now);
      expect(v.fill!.source, 'ble_upper_arm');
    });

    test('오래된 워치 혈압·모르는 출처·30분 넘은 맥박은 채우지 않는다', () {
      final v = pickVitals([watch(120, 80, const Duration(hours: 4)), arm(120, 80, const Duration(minutes: 1), source: 'unknown')], now,
          pulses: [(70, now.subtract(const Duration(minutes: 40)))]);
      expect(v.fill, isNull);
      expect(v.watch!.systolic, 120);
      expect(v.watchPulse, isNull);
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
    expect(find.text('맥박은 직접 넣어 주세요'), findsOneWidget);
    await enter(tester, '높은 쪽 숫자(수축기)', '132');
    await enter(tester, '맥박', '70');
    await answerRest(tester);
    final body = h.server.bodies('POST /me/prechecks').single;
    expect(body['systolic'], 132);
    expect(body['bp_source'], 'manual');
    expect(body['hr_source'], 'manual');
  });

  testWidgets('혈압계가 없으면 워치 혈압·맥박으로 채우고, 정상이어도 오늘은 가볍게', (tester) async {
    final h = Harness();
    h.state.readBp = (from, to) async => [watch(126, 80, const Duration(minutes: 20))];
    h.state.readHr = (from, to) async => [HrSample(72, now.subtract(const Duration(minutes: 5)))];
    await h.start(tester);
    await openCheck(tester);
    expect(field(tester, '높은 쪽 숫자(수축기)'), '126');
    expect(field(tester, '맥박'), '72');
    expect(find.textContaining('워치에서 잰 혈압을 넣어 두었어요 (20분 전)'), findsOneWidget);
    expect(find.text('맥박은 워치 기록이에요 (5분 전)'), findsOneWidget);
    await answerRest(tester);
    final body = h.server.bodies('POST /me/prechecks').single;
    expect(body['bp_source'], 'watch');
    expect(body['hr_source'], 'watch');
    // 가짜 서버는 초록을 주지만 단말 엔진이 워치(B 등급) 정상값을 노랑으로 → 더 나쁜 쪽
    expect(find.text('노랑 · 오늘은 가볍게'), findsOneWidget);
  });

  testWidgets('워치 혈압이 오래됐으면 채우지 않고 다시 재도록', (tester) async {
    final h = Harness();
    h.state.readBp = (from, to) async => [watch(126, 80, const Duration(hours: 5))];
    await h.start(tester);
    await openCheck(tester);
    expect(field(tester, '높은 쪽 숫자(수축기)'), '');
    expect(find.textContaining('워치에서 혈압을 다시 재고'), findsOneWidget);
  });

  testWidgets('건강 앱을 못 읽으면 손으로 넣는다', (tester) async {
    final h = Harness();
    h.state.readBp = (from, to) async => throw Exception('권한 없음');
    await h.start(tester);
    await openCheck(tester);
    expect(field(tester, '높은 쪽 숫자(수축기)'), '');
    expect(find.text('의자에 앉아 5분 쉰 뒤, 혈압을 재 주세요. 워치로 재도 괜찮아요.'), findsOneWidget);
  });
}
