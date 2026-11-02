import 'package:flutter_test/flutter_test.dart';
import 'package:senior_coach/core/heart_rate.dart';

import 'app_test.dart' show toResult;
import 'fakes.dart';

/// 매초 워치 심박을 보내며 시간을 흘린다.
Future<void> beats(WidgetTester tester, Harness h, int bpm, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    h.watch.beat(bpm);
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('홈에서 워치 연결 → 상태와 심박 표시', (tester) async {
    final h = Harness();
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('워치 연결 안 됨'), findsOneWidget);
    await tapText(tester, '워치 연결하기');
    h.watch.beat(88);
    await tester.pump();
    expect(find.text('워치 연결됨 · 심박 88'), findsOneWidget);
    expect(find.text('워치 연결 끊기'), findsOneWidget);
  });

  testWidgets('같은 심박 126이어도 워치(B 등급)는 중단하지 않고 일시정지까지만', (tester) async {
    final h = Harness();
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tapText(tester, '워치 연결하기');
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await beats(tester, h, 95, 10);
    expect(find.textContaining('디즈먼트 워치 (실시간)'), findsOneWidget);
    expect(find.textContaining('지금 심박 95회/분 · 오늘 상한 109회/분'), findsOneWidget);
    await beats(tester, h, 126, 2);
    expect(find.text('잠깐 쉬는 중'), findsOneWidget);
    expect(find.textContaining('워치는 참고용이라 멈추지 않고'), findsOneWidget);
    expect(find.text('괜찮으세요?'), findsNothing);              // 응급 흐름으로 가지 않음
    // 앉아서 쉬는 동안 심박이 내려옴. 쉬는 중 급하강은 이미 일시정지라 새 행동 없음.
    // (쉬자마자 다시 하기를 누르면 10초 창 안의 126→96 하강이 '급변'으로 또 일시정지된다 — 자문단 확인 항목)
    await beats(tester, h, 96, 12);
    expect(find.text('잠깐 쉬는 중'), findsOneWidget);
    await tapText(tester, '다시 하기');
    await beats(tester, h, 96, 3);
    expect(find.text('남은 시간'), findsOneWidget);
  });

  testWidgets('워치 신호가 15초 넘게 끊기면 채우지 않고 끊김으로 대처', (tester) async {
    final h = Harness();
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tapText(tester, '워치 연결하기');
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await beats(tester, h, 95, 5);
    await seconds(tester, 17);                                    // 심박 없이 시간만
    expect(find.textContaining('워치 신호가 끊겼어요'), findsOneWidget);
    await beats(tester, h, 97, 2);                                 // 다시 들어오면 안내를 거둔다
    expect(find.textContaining('워치 신호가 끊겼어요'), findsNothing);
  });

  testWidgets('워치 없이 시작하면 폰만으로(심박 카드 없음)', (tester) async {
    final h = Harness();
    await h.start(tester);
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('디즈먼트 워치'), findsNothing);
  });

  testWidgets('건강 앱 경유(실시간 아님): 홈에는 최근 심박, 운동 중 판정에는 안 씀', (tester) async {
    final h = Harness();
    h.watch.isRealtime = false;
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('워치 연결하기'), findsNothing); // 건강 앱 경유는 홈에 오면 바로 읽는다
    expect(h.watch.connected, isTrue);
    h.watch.beat(72);
    await tester.pump();
    await tester.pump(); // 심박이 상태에 들어간 다음 프레임에 홈이 다시 그려진다
    expect(find.text('건강 앱 · 최근 심박 72 (방금)'), findsOneWidget);
    expect(find.textContaining('SMART-TIME PRO를 열어 동기화'), findsNothing);
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await beats(tester, h, 130, 3);                               // 늦은 값이 높아도 일시정지하지 않음
    expect(find.textContaining('디즈먼트 워치 (실시간)'), findsNothing);
    expect(find.text('잠깐 쉬는 중'), findsNothing);
  });

  group('HealthHeartRateSource', () {
    final t0 = DateTime(2026, 11, 1, 9);
    late List<HrSample> stored;
    late List<(DateTime, DateTime)> asked;
    late DateTime now;
    HealthHeartRateSource make({bool allowed = true}) => HealthHeartRateSource(
          authorize: () async => allowed,
          read: (from, to) async {
            asked.add((from, to));
            return stored.where((s) => !s.at.isBefore(from) && s.at.isBefore(to)).toList();
          },
          now: () => now,
        );

    setUp(() {
      stored = [];
      asked = [];
      now = t0;
    });

    test('연결하면 최근 2시간 중 가장 새 기록 하나를 낸다', () async {
      stored = [HrSample(70, t0.subtract(const Duration(minutes: 30))), HrSample(75, t0.subtract(const Duration(minutes: 5)))];
      final src = make();
      final got = <int>[];
      src.samples.listen((s) => got.add(s.bpm));
      await src.connect();
      await Future<void>.delayed(Duration.zero);
      expect(got, [75]);
      expect(asked.single.$1, t0.subtract(const Duration(hours: 2)));
      expect(src.realtime, isFalse);
      await src.close();
    });

    test('다음 조회는 마지막 기록 이후만, 새것이 없으면 아무것도 안 냄', () async {
      stored = [HrSample(75, t0.subtract(const Duration(minutes: 5)))];
      final src = make();
      final got = <int>[];
      src.samples.listen((s) => got.add(s.bpm));
      await src.connect();
      now = t0.add(const Duration(minutes: 1));
      await src.poll();
      stored.add(HrSample(81, t0.add(const Duration(seconds: 30))));
      now = t0.add(const Duration(minutes: 2));
      await src.poll();
      await Future<void>.delayed(Duration.zero);
      expect(got, [75, 81]);
      expect(asked.last.$1, t0.subtract(const Duration(minutes: 5)));
      await src.close();
    });

    test('권한을 거절하면 연결 실패와 안내', () async {
      final src = make(allowed: false);
      final msgs = <String>[];
      src.status.listen(msgs.add);
      await expectLater(src.connect(), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(src.connected, isFalse);
      expect(msgs.last, '건강 앱 심박 읽기를 허용해 주세요');
    });

    test('기록이 하나도 없으면 동기화 안내', () async {
      final src = make();
      final msgs = <String>[];
      src.status.listen(msgs.add);
      await src.connect();
      await Future<void>.delayed(Duration.zero);
      expect(msgs.last, contains('SMART-TIME PRO를 열어 동기화'));
      await src.close();
    });
  });

  testWidgets('건강 앱 경유: 오늘 걸음, 워치 기록이 없으면 동기화 안내', (tester) async {
    final h = Harness();
    h.watch.isRealtime = false;
    h.state.readSteps = (from, to) async => 3210;
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('오늘 걸음 3,210보'), findsOneWidget);
    expect(find.textContaining('SMART-TIME PRO를 열어 동기화'), findsOneWidget);
    expect(find.text('워치 기록 다시 불러오기'), findsOneWidget);
  });

  testWidgets('운동이 끝나면 그 시간대 워치 기록(심박 평균·최고, 걸음)을 보여 준다', (tester) async {
    final h = Harness();
    final asked = <(DateTime, DateTime)>[];
    h.state.readHr = (from, to) async {
      asked.add((from, to));
      return [HrSample(90, to), HrSample(100, to), HrSample(110, to)];
    };
    h.state.readSteps = (from, to) async => 420;
    await h.start(tester);
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await seconds(tester, 185);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('워치 기록'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('평균 심박 100')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('최고 심박 110')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('걸음 420')), findsOneWidget);
    // 운동한 시간대에 앞뒤 1분 여유를 두고 읽는다(테스트 시계는 실제로 흐르지 않아 여유분만 남음)
    expect(asked.last.$2.difference(asked.last.$1), greaterThanOrEqualTo(const Duration(minutes: 2)));
  });

  testWidgets('운동 후 워치 기록이 아직 없으면 다시 불러오기', (tester) async {
    final h = Harness();
    var calls = 0;
    h.state.readHr = (from, to) async => ++calls == 1 ? <HrSample>[] : [HrSample(95, to)];
    await h.start(tester);
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await seconds(tester, 185);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('아직 워치 기록이 안 들어왔어요'), findsOneWidget);
    await tapText(tester, '다시 불러오기');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel(RegExp('평균 심박 95')), findsOneWidget);
  });
}
