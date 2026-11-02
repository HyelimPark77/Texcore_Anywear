import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const blockedHealth = {
  'conditions': ['uncontrolled_arrhythmia'],
  'parq_risk': true,
  'doctor_clearance': false,
  'device': null,
  'beta_blocker': false,
  'doctor_limits': <String, dynamic>{},
};

void main() {
  testWidgets('의사 확인이 필요하면 혈압을 재기 전에 홈에서 먼저 알리고, 이유를 쉬운 말로', (tester) async {
    final h = Harness();
    h.state.health = {...blockedHealth};
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('운동 시작하기'), findsNothing);
    expect(find.textContaining('의사 선생님 확인이 필요해요'), findsOneWidget);
    await tapText(tester, '병원 확인이 필요해요');
    expect(find.text('고르신 병: 맥박이 불규칙한데 약으로 잘 안 잡힌다'), findsOneWidget);
    expect(find.text('몸 상태 질문에서 "예"라고 답하신 것이 있어요'), findsOneWidget);
    expect(h.server.bodies('POST /me/prechecks'), isEmpty);
  });

  testWidgets('의사 확인을 받았다고 넣으면 다시 운동할 수 있다', (tester) async {
    final h = Harness();
    h.state.health = {...blockedHealth};
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tapText(tester, '병원 확인이 필요해요');
    await tapText(tester, '의사 선생님 확인을 받았어요');
    await tapText(tester, '확인받았어요');
    await tester.pump(const Duration(milliseconds: 600));
    expect(h.server.bodies('PUT /me/health').single['doctor_clearance'], true);
    expect(find.text('운동 시작하기'), findsOneWidget);
  });

  testWidgets('심장 박동기는 최고 맥박을 넣어야 열린다', (tester) async {
    final h = Harness();
    h.state.health = {...blockedHealth, 'conditions': <String>[], 'parq_risk': false, 'device': 'pacemaker'};
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tapText(tester, '병원 확인이 필요해요');
    await tapText(tester, '최고 맥박 넣기');
    await tapText(tester, '확인받았어요');
    expect(find.textContaining('최고 맥박을 숫자로 넣어 주세요'), findsOneWidget);
    expect(h.server.bodies('PUT /me/health'), isEmpty);
    await tapText(tester, '확인');
    await enter(tester, '최고 맥박', '110');
    await tapText(tester, '확인받았어요');
    await tester.pump(const Duration(milliseconds: 600));
    expect(h.server.bodies('PUT /me/health').single['doctor_limits'], {'exercise_hr_ceiling': 110});
    expect(find.text('운동 시작하기'), findsOneWidget);
  });

  testWidgets('잘못 고른 병은 내 건강 정보에서 지우면 된다', (tester) async {
    final h = Harness();
    h.state.health = {...blockedHealth, 'parq_risk': false};
    await h.start(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tapText(tester, '병원 확인이 필요해요');
    await tapText(tester, '내 건강 정보 고치기');
    await tapText(tester, '맥박이 불규칙한데 약으로 잘 안 잡힌다'); // 다시 누르면 꺼짐
    await tapText(tester, '저장하기');
    await tester.pump(const Duration(milliseconds: 600));
    expect(h.server.bodies('PUT /me/health').single['conditions'], isEmpty);
    expect(find.text('운동 시작하기'), findsOneWidget);
  });

  testWidgets('운동 전 점검도 서버와 같은 프로필로: 의사 확인 없이 고른 병이 있으면 단말도 막는다', (tester) async {
    final h = Harness();
    h.state.health = {...blockedHealth};
    expect(h.state.gateBlocks, isNotEmpty);
    h.state.health = {...blockedHealth, 'doctor_clearance': true};
    expect(h.state.gateBlocks, isEmpty);
  });
}
