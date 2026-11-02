import 'package:flutter_test/flutter_test.dart';
import 'package:senior_coach/core/exercises.dart';

import 'app_test.dart' show toResult;
import 'fakes.dart';

void main() {
  group('동작 순서표', () {
    for (final activity in exerciseLibrary.activities.keys) {
      for (final minutes in [1, 3, 5, 8, 10, 15, 20, 30]) {
        test('$activity $minutes분: 빈틈없이 이어지고 몸 풀기로 시작해 마무리로 끝난다', () {
          final total = minutes * 60;
          final plan = exerciseLibrary.plan(activity, total);
          expect(plan, isNotEmpty);
          var t = 0;
          for (final s in plan) {
            expect(s.start, t);
            expect(s.seconds, greaterThan(0));
            t = s.end;
          }
          expect(t, total);
          if (minutes >= 3) {
            expect(plan.first.phase, Phase.warmup);
            expect(plan.last.phase, Phase.cooldown);
            expect(plan.where((s) => s.phase == Phase.main), isNotEmpty);
          } else {
            expect(plan.single.phase, Phase.main);
          }
        });
      }
    }

    test('모르는 운동이면 빈 표(종류별 짧은 문장으로 대신)', () {
      expect(exerciseLibrary.plan('unknown', 180), isEmpty);
    });

    test('동작 바뀌는 시각 찾기', () {
      final plan = exerciseLibrary.plan('chair_march', 180);
      expect(segmentAt(plan, 0), 0);
      expect(segmentAt(plan, plan[1].start), 1);
      expect(segmentAt(plan, 999), plan.length - 1);
    });
  });

  testWidgets('운동 중: 동작 그림·이름·방법을 보여 주고, 동작이 바뀌면 말로 알린다', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = Harness();
    await h.start(tester);
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await tester.pump(const Duration(seconds: 1));

    // 3분 = 몸 풀기 30초(숨 고르기) → 본 운동 2분 → 마무리 30초
    expect(find.textContaining('몸 풀기 · 동작 1/'), findsOneWidget);
    expect(find.text('앉아서 숨 고르기'), findsOneWidget);
    expect(find.text('1. 의자에 등을 붙이고 앉아요'), findsOneWidget);
    expect(find.text('다음: 앉아서 제자리 걷기'), findsOneWidget);
    expect(find.bySemanticsLabel('앉아서 숨 고르기 그림'), findsOneWidget);
    expect(h.speaker.said.where((s) => s.contains('먼저 몸 풀기, 앉아서 숨 고르기')), hasLength(1));

    await seconds(tester, 30);
    expect(find.textContaining('본 운동 · 동작 2/'), findsOneWidget);
    expect(find.text('앉아서 제자리 걷기'), findsOneWidget);
    expect(h.speaker.said.where((s) => s.startsWith('이제 본 운동이에요. 앉아서 제자리 걷기')), isNotEmpty);
    semantics.dispose();
  });

  testWidgets('같은 동작 중에는 짧은 문장을 12초마다, 시작 안내는 끊지 않는다', (tester) async {
    final h = Harness();
    await h.start(tester);
    await toResult(tester);
    final before = h.speaker.said.length;
    await tapText(tester, '3분 시작하기');
    await seconds(tester, 11);
    expect(h.speaker.said.sublist(before), hasLength(1), reason: '시작 안내만');
    await seconds(tester, 1);
    expect(h.speaker.said.last, '천천히 들이마시고');
  });

  testWidgets('몸 상태 확인은 한 화면: 증상·컨디션을 한꺼번에 고르고 한 번에 보낸다', (tester) async {
    final h = Harness();
    await h.start(tester);
    await toResult(tester, pick: ['어지러워요', '어젯밤 잠을 못 잤어요']);
    final body = h.server.bodies('POST /me/prechecks').single;
    expect(body['symptoms'], ['dizziness']);
    expect(body['conditions'], ['poor_sleep']);
  });

  testWidgets('운동 중 잠깐 쉬기 → 다시 하기', (tester) async {
    final h = Harness();
    await h.start(tester);
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await seconds(tester, 5);
    await tapText(tester, '잠깐 쉬기');
    expect(find.text('잠깐 쉬는 중'), findsOneWidget);
    await seconds(tester, 10);
    expect(find.text('잠깐 쉬는 중'), findsOneWidget); // 쉬는 동안 시간이 흐르지 않음
    await tapText(tester, '다시 하기');
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('몸 풀기 · 동작 1/'), findsOneWidget);
  });

  testWidgets('홈에 오면 오늘 알림을 기기에 걸고, 누른 알림은 서버에 알린다', (tester) async {
    final h = Harness();
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(h.reminders.scheduled.map((r) => r.text), ['자, 오늘 3분만 해 볼까요?', '오늘 1분만 해볼까요?']);
    h.reminders.opens.add(41);
    await tester.pump();
    expect(h.server.requests.where((r) => r.$1 == 'POST' && r.$2 == '/me/notifications/41/opened'), hasLength(1));
  });

  testWidgets('운동을 마치면 오늘 남은 알림(했으면 안 보내는 것)을 지운다', (tester) async {
    final h = Harness();
    await h.start(tester);
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await seconds(tester, 185);
    await tester.pump(const Duration(milliseconds: 600));
    expect(h.reminders.cancelledDone, 1);
  });

  testWidgets('알림·목표는 홈에서 언제든 바꾼다', (tester) async {
    final h = Harness();
    h.state.settings = {'preferred_time': '09:00', 'anchor': 'time', 'goal': null, 'fall_concern': false};
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tapText(tester, '알림·목표');
    await tapText(tester, '저녁 6시');
    await tapText(tester, '네, 붙잡을 곳이 있는 운동으로 해 주세요');
    await tapText(tester, '저장하기');
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.server.bodies('PUT /me/settings').single, {'preferred_time': '18:00', 'anchor': 'time', 'goal': null, 'fall_concern': true});
    expect(find.text('운동 시작하기'), findsOneWidget); // 홈으로 돌아옴
  });
}
