// 내 건강 정보 고치기 + 의사 확인(하드 게이트 5-1).
// 가입 때 고른 답 때문에 운동이 막혀도, 홈에서 이유를 먼저 보여 주고 여기서 고치거나 의사 확인을 넣을 수 있다.
// 판정 자체는 안전 엔진(gateReasons)이 하고, 이 화면은 답을 바꾸는 곳일 뿐이다.
import 'package:flutter/material.dart';
import 'package:safety_engine/safety_engine.dart';

import '../core/app_state.dart';
import '../ui/kit.dart';
import 'onboarding.dart';

/// 막힌 이유를 쉬운 말로. 질환은 고른 이름을 그대로 보여 준다.
List<String> gateExplanations(AppState app) {
  final h = app.health ?? const {};
  return [
    for (final code in app.gateBlocks)
      switch (code) {
        Code.gateConditionNeedsClearance =>
          '고르신 병: ${((h['conditions'] as List?) ?? const []).map((c) => gateConditions[c] ?? c).join(', ')}',
        Code.gateParqRisk => '몸 상태 질문에서 "예"라고 답하신 것이 있어요',
        Code.gateDeviceNeedsHrCeiling => '심장 박동기를 넣으셔서, 의사 선생님이 정한 운동 중 최고 맥박이 필요해요',
        _ => code,
      },
  ];
}

// ---------------- 의사 확인이 필요해요 ----------------
class DoctorCheckScreen extends StatelessWidget {
  const DoctorCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final needsCeiling = app.gateBlocks.contains(Code.gateDeviceNeedsHrCeiling);
    return SeniorScaffold(
      title: '병원 확인이 필요해요',
      primaryLabel: needsCeiling ? '최고 맥박 넣기' : '의사 선생님 확인을 받았어요',
      onPrimary: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClearanceScreen())),
      secondaryLabel: '내 건강 정보 고치기',
      onSecondary: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HealthInfoScreen())),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('안전을 위해, 아래 내용이 있으면 의사 선생님께 운동해도 되는지 먼저 여쭤봐 주세요.'),
        const SizedBox(height: 16),
        for (final e in gateExplanations(app))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.local_hospital, size: 32),
              const SizedBox(width: 10),
              Expanded(child: Text(e)),
            ]),
          ),
        const SizedBox(height: 12),
        const Text('잘못 고르셨다면 "내 건강 정보 고치기"에서 바꿀 수 있어요.'),
      ]),
    );
  }
}

// ---------------- 의사 확인 넣기 ----------------
class ClearanceScreen extends StatefulWidget {
  const ClearanceScreen({super.key});
  @override
  State<ClearanceScreen> createState() => _ClearanceScreenState();
}

class _ClearanceScreenState extends State<ClearanceScreen> {
  final _ceiling = TextEditingController();
  bool _busy = false;

  Future<void> _save() async {
    final app = AppScope.of(context);
    final h = {...?app.health};
    final needsCeiling = app.gateBlocks.contains(Code.gateDeviceNeedsHrCeiling);
    final ceiling = int.tryParse(_ceiling.text);
    if (needsCeiling && (ceiling == null || ceiling < 60 || ceiling > 200)) {
      showError(context, '의사 선생님이 정해 준 최고 맥박을 숫자로 넣어 주세요. 모르시면 병원에 여쭤봐 주세요.');
      return;
    }
    setState(() => _busy = true);
    try {
      await app.saveHealth({
        ...h,
        'doctor_clearance': true,
        if (ceiling != null) 'doctor_limits': {...?(h['doctor_limits'] as Map?)?.cast<String, dynamic>(), 'exercise_hr_ceiling': ceiling},
      });
      if (mounted) goHome(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final needsCeiling = app.gateBlocks.contains(Code.gateDeviceNeedsHrCeiling);
    return SeniorScaffold(
      title: '의사 선생님 확인',
      primaryLabel: _busy ? '저장하는 중' : '확인받았어요',
      onPrimary: _busy ? null : _save,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('의사 선생님께 "가벼운 운동을 해도 된다"는 말을 들으셨나요?'),
        const SizedBox(height: 12),
        const Text('들으셨으면 확인받았어요를 눌러 주세요. 기록에 남아요.'),
        if (needsCeiling) ...[
          const SizedBox(height: 20),
          const Text('심장 박동기를 넣으셨으면, 의사 선생님이 정해 준 운동 중 최고 맥박도 넣어 주세요.'),
          const SizedBox(height: 12),
          BigNumberField(label: '최고 맥박', unit: '회/분', controller: _ceiling),
        ],
      ]),
    );
  }
}

// ---------------- 내 건강 정보 ----------------
class HealthInfoScreen extends StatefulWidget {
  const HealthInfoScreen({super.key});
  @override
  State<HealthInfoScreen> createState() => _HealthInfoScreenState();
}

class _HealthInfoScreenState extends State<HealthInfoScreen> {
  late Map<String, dynamic> _h;
  late Set<String> _conditions;
  final _ceiling = TextEditingController();
  bool _ready = false, _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _h = {...?AppScope.of(context).health};
    _conditions = ((_h['conditions'] as List?) ?? const []).cast<String>().toSet();
    final c = (_h['doctor_limits'] as Map?)?['exercise_hr_ceiling'];
    if (c != null) _ceiling.text = '$c';
    _ready = true;
  }

  Map<String, dynamic> get _edited => {
        ..._h,
        'conditions': _conditions.toList(),
        'doctor_limits': {
          ...?(_h['doctor_limits'] as Map?)?.cast<String, dynamic>(),
          if (int.tryParse(_ceiling.text) != null) 'exercise_hr_ceiling': int.parse(_ceiling.text),
        }..removeWhere((k, v) => k == 'exercise_hr_ceiling' && _ceiling.text.isEmpty),
      };

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).saveHealth(_edited);
      if (mounted) goHome(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    final parqRisk = _h['parq_risk'] == true;
    return SeniorScaffold(
      title: '내 건강 정보',
      primaryLabel: _busy ? '저장하는 중' : '저장하기',
      onPrimary: _busy ? null : _save,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('바꾸고 싶은 것만 눌러 고친 뒤 저장하기를 눌러 주세요.'),
        _section('의사에게 들은 적이 있는 것'),
        for (final e in gateConditions.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CheckTile(
              label: e.value,
              on: _conditions.contains(e.key),
              onTap: () => setState(() => _conditions.contains(e.key) ? _conditions.remove(e.key) : _conditions.add(e.key)),
            ),
          ),
        _section('약과 기기'),
        CheckTile(
          label: '맥박을 느리게 하는 약(베타차단제)을 먹어요',
          on: _h['beta_blocker'] == true,
          onTap: () => setState(() => _h['beta_blocker'] = !(_h['beta_blocker'] == true)),
        ),
        const SizedBox(height: 10),
        CheckTile(
          label: '심장 박동기나 제세동기를 넣었어요',
          on: _h['device'] != null,
          onTap: () => setState(() => _h['device'] = _h['device'] == null ? 'pacemaker' : null),
        ),
        if (_h['device'] != null) ...[
          const SizedBox(height: 12),
          BigNumberField(label: '의사 선생님이 정한 최고 맥박', unit: '회/분', controller: _ceiling),
        ],
        _section('몸 상태 질문'),
        Text(parqRisk ? '"예"라고 답하신 질문이 있어요.' : '모두 "아니요"로 답하셨어요.'),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParqScreen(health: _edited))),
          child: const Text('몸 상태 질문 다시 답하기'),
        ),
        _section('의사 선생님 확인'),
        CheckTile(
          label: '운동해도 된다고 의사 선생님께 확인받았어요',
          on: _h['doctor_clearance'] == true,
          onTap: () => setState(() => _h['doctor_clearance'] = !(_h['doctor_clearance'] == true)),
        ),
      ]),
    );
  }
}
