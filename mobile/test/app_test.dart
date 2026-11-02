import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// 홈 → 운동 시작하기 → 몸 상태 확인(한 화면) → 신호등 결과.
/// [pick]: 고를 증상·컨디션 칩. '가슴이 아프거나 조여요'면 응급 버튼을 누르고 끝.
Future<void> toResult(WidgetTester tester, {String sbp = '130', String dbp = '80', String hr = '70', List<String> pick = const []}) async {
  await tester.pump(const Duration(milliseconds: 600)); // 홈 불러오기·화면 전환 끝내기
  await tapText(tester, '운동 시작하기');
  await enter(tester, '높은 쪽 숫자(수축기)', sbp);
  await enter(tester, '낮은 쪽 숫자(이완기)', dbp);
  await enter(tester, '맥박', hr);
  if (pick.contains('가슴이 아프거나 조여요')) {
    await tapText(tester, '가슴이 아프거나 조여요');
    return;
  }
  for (final p in pick) {
    await tapText(tester, p);
  }
  await tapText(tester, pick.isEmpty ? '없어요, 괜찮아요' : '이대로 확인하기');
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('온보딩: 처음 온 어르신이 혼자 가입·동의·문진을 마치고 홈으로', (tester) async {
    final h = Harness(loggedIn: false, withRules: false);
    await h.start(tester);
    await enter(tester, '휴대폰 번호', '01011112222');
    await tapText(tester, '인증번호 받기');
    await enter(tester, '문자로 온 인증번호', '123456');
    await tapText(tester, '확인');                         // 서버: 처음 오셨네요(422)
    await enter(tester, '이름', '김영자');
    await tapText(tester, '다음');
    await enter(tester, '예: 1952', '1952');
    await tapText(tester, '다음');
    await tapText(tester, '동의해요');
    await tapText(tester, '가슴 통증(협심증)이 요즘 심해졌다');
    await tapText(tester, '다음');
    await tapText(tester, '안 먹어요');
    await tapText(tester, '아니요');
    await tapText(tester, '다음');
    for (var i = 0; i < 7; i++) {
      await tapText(tester, '아니요');
    }
    await tester.pump(const Duration(milliseconds: 500));
    // 협심증을 골랐으므로 혈압을 재기 전에 홈에서 바로 의사 확인 안내(5-1)
    expect(find.text('병원 확인이 필요해요'), findsOneWidget);

    expect(h.server.bodies('POST /auth/otp/request').single, {'phone': '01011112222'});
    expect(h.server.bodies('POST /auth/otp/verify').last, {'phone': '01011112222', 'code': '123456', 'role': 'elder', 'name': '김영자', 'birth_year': 1952});
    expect(h.server.bodies('POST /me/consents').single, {'kind': 'health', 'granted': true});
    final health = h.server.bodies('PUT /me/health').last;
    expect(health['conditions'], ['unstable_angina']);
    expect(health['parq_risk'], false);
    expect(h.state.rules, isNotNull);                      // 규칙 번들을 받아 해시 확인 후 보관
    expect(h.store.data['token'], 'tok');
  });

  testWidgets('초록 날: 점검 → 신호등 → 3분 운동(2분에 숨찬 정도 질문) → 칭찬과 응원', (tester) async {
    final h = Harness();
    await h.start(tester);
    expect(find.text('3분'), findsOneWidget);
    await toResult(tester);
    expect(find.text('초록 · 평소대로 해요'), findsOneWidget);
    expect(h.speaker.said, contains('자, 오늘은 3분만 해 볼까요?'));
    expect(h.server.bodies('POST /me/prechecks').single,
        {'systolic': 130, 'diastolic': 80, 'resting_hr': 70, 'bp_source': 'manual', 'hr_source': 'manual', 'symptoms': [], 'conditions': []});

    await tapText(tester, '3분 시작하기');
    await tester.pump();
    expect(find.text('그만'), findsOneWidget);
    await seconds(tester, 122);   // 타이머는 서버 응답 다음 프레임에 시작                            // 폰만으로 하는 날: 2분마다 확인(규칙 번들 값)
    expect(find.text('숨이 차세요?'), findsOneWidget);
    await tapText(tester, '편해요, 말도 잘 나와요');
    await seconds(tester, 62);
    expect(find.text('해내셨어요'), findsOneWidget);
    expect(find.textContaining('엄마 최고'), findsOneWidget);

    final finish = h.server.bodies('POST /me/sessions/7/finish').single;
    expect(finish, {'completed': true, 'minutes': 3.0, 'max_rpe': 11, 'stopped': false});
    final events = h.server.bodies('POST /me/sessions/7/events').single['events'] as List;
    expect(events.single['actions'][0]['kind'], 'ASK_RPE');
  });

  testWidgets('"너무 힘들어요" → 단말 엔진이 중단 → 괜찮으세요? → 아니에요 → 보호자 알림', (tester) async {
    final h = Harness();
    await h.start(tester);
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await seconds(tester, 122);   // 타이머는 서버 응답 다음 프레임에 시작
    await tapText(tester, '너무 힘들어요');
    await tester.pump();
    expect(find.text('괜찮으세요?'), findsOneWidget);
    await tapText(tester, '아니에요');
    expect(h.server.bodies('POST /me/emergency').single, {'code': 'EM_USER_NOT_OK', 'severe': false});
    expect(find.textContaining('보호자에게 알렸어요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(h.server.bodies('POST /me/sessions/7/finish').single['stopped'], true);
  });

  testWidgets('"그만" 뒤 60초 무응답 → 보호자 알림', (tester) async {
    final h = Harness();
    await h.start(tester);
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await seconds(tester, 5);
    await tapText(tester, '그만');
    await seconds(tester, 59);
    expect(h.server.bodies('POST /me/emergency'), isEmpty);
    await seconds(tester, 1);
    expect(h.server.bodies('POST /me/emergency').single['code'], 'EM_NO_RESPONSE');
  });

  testWidgets('운동 중 "가슴이 아파요" → 119 화면 → 한 번 눌러 발신 + 보호자 알림', (tester) async {
    final h = Harness();
    await h.start(tester);
    await toResult(tester);
    await tapText(tester, '3분 시작하기');
    await seconds(tester, 122);   // 타이머는 서버 응답 다음 프레임에 시작
    await tapText(tester, '몸이 이상해요');
    await tapText(tester, '가슴이 아프거나 조여요');
    await tester.pump();
    expect(find.text('119 전화하기'), findsOneWidget);
    await tapText(tester, '119 전화하기');
    expect(h.dialer.calls, ['119']);
    expect(h.server.bodies('POST /me/emergency').single, {'code': 'EM_119_CONFIRMED', 'severe': false});
  });

  testWidgets('점검에서 가슴 통증 → 바로 119 안내', (tester) async {
    final h = Harness();
    h.server.routes['POST /me/prechecks'] = (_) => FakeServer.precheck('EMERGENCY', action: 'EMERGENCY');
    await h.start(tester);
    await toResult(tester, pick: ['가슴이 아프거나 조여요']);
    await tester.pump();
    expect(find.text('지금 바로 도움을 받으세요'), findsOneWidget);
    expect(h.server.bodies('POST /me/prechecks').single['symptoms'], ['chest_pain']);
    await tapText(tester, '도움 요청하기');
    expect(find.text('119 전화하기'), findsOneWidget);
  });

  testWidgets('단말 판정이 더 나쁘면 단말을 따른다(서버 초록, 단말 빨강)', (tester) async {
    final h = Harness();
    await h.start(tester);
    await toResult(tester, sbp: '185');                    // 서버 흉내는 GREEN을 돌려줌
    expect(find.text('빨강 · 오늘은 쉬어요'), findsOneWidget);
    expect(find.text('3분 시작하기'), findsNothing);
  });

  testWidgets('인터넷이 끊겨도 단말이 판정한다. 운동 시작은 연결 후에만', (tester) async {
    final h = Harness();
    h.server.routes['POST /me/prechecks'] = (_) => (503, {'detail': '연결 안 됨'});
    await h.start(tester);
    await toResult(tester);
    expect(find.text('초록 · 평소대로 해요'), findsOneWidget);
    expect(find.textContaining('인터넷에 연결되면'), findsOneWidget);
    expect(find.text('3분 시작하기'), findsNothing);

    await tapText(tester, '확인');
    await toResult(tester, sbp: '190');
    expect(find.text('빨강 · 오늘은 쉬어요'), findsOneWidget);
  });

  testWidgets('더 쉬운 걸로 → 1분 세션', (tester) async {
    final h = Harness();
    await h.start(tester);
    await toResult(tester);
    await tapText(tester, '더 쉬운 걸로 (1분)');
    expect(h.server.bodies('POST /me/sessions').single['easier'], true);
    expect(find.text('1:00'), findsOneWidget);
  });

  testWidgets('글자 크기 3단계', (tester) async {
    final h = Harness();
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    for (final (expected, label) in [(1.25, '글자 크기 2단계'), (1.5, '글자 크기 3단계'), (1.0, '글자 크기 1단계')]) {
      await tester.ensureVisible(find.textContaining('글자 크기'));
      await tester.tap(find.textContaining('글자 크기'));
      await tester.pump();
      expect(h.state.textScale, expected);
      expect(find.text(label), findsOneWidget);
      expect(MediaQuery.textScalerOf(tester.element(find.text(label))).scale(10), closeTo(10 * expected, 0.01));
    }
    expect(h.store.data['textScale'], '1.0');
  });

  group('접근성 기준', () {
    Future<void> check(WidgetTester tester) async {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      // 하단 주 버튼은 56dp보다 크게
      for (final e in find.byType(FilledButton).evaluate()) {
        expect(tester.getSize(find.byWidget(e.widget)).height, greaterThanOrEqualTo(56));
      }
    }

    testWidgets('홈', (tester) async {
      final handle = tester.ensureSemantics();
      await Harness().start(tester);
      await check(tester);
      handle.dispose();
    });

    testWidgets('신호등 결과·운동 진행', (tester) async {
      final handle = tester.ensureSemantics();
      final h = Harness();
      await h.start(tester);
      await toResult(tester, sbp: '165');
      await check(tester);
      await tapText(tester, '3분 시작하기');
      await tester.pump(const Duration(milliseconds: 600)); // 화면 전환이 끝난 뒤 검사
      expect(find.text('그만'), findsOneWidget);
      await check(tester);
      handle.dispose();
    });
  });
}
