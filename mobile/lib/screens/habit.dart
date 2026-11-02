// 목표·편한 시간·앵커 고르기(6-3·6-5). 가입 마지막 단계이자 홈 '알림·목표'에서 언제든 바꾼다.
// 고른 시간·앵커로 서버 유도 엔진이 오늘 알림을 정하고, 앱이 기기 알림으로 건다(워치 진동은 SMART-TIME PRO가 전달).
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../ui/kit.dart';
import 'onboarding.dart';

const goalChoices = ['손주 안아 주기', '시장까지 걸어가기', '계단 편하게 오르기', '여행 가기', '친구와 산책하기'];
const timeChoices = [('아침 9시', '09:00'), ('점심 지나 1시', '13:00'), ('오후 4시', '16:00'), ('저녁 6시', '18:00')];
// 앵커 이름은 유도 엔진 UserProfile.anchor 와 같다(bp 이면 '혈압 재기' 알림 문구)
const anchorChoices = [('혈압 잰 다음', 'bp'), ('아침 약 먹은 다음', 'after_meds'), ('정한 시간에', 'time')];

class HabitSetupScreen extends StatefulWidget {
  /// 가입 중이면 저장 뒤 홈으로, 아니면 뒤로.
  final bool onboarding;
  const HabitSetupScreen({super.key, this.onboarding = false});
  @override
  State<HabitSetupScreen> createState() => _HabitSetupScreenState();
}

class _HabitSetupScreenState extends State<HabitSetupScreen> {
  String? _goal;
  String _time = '09:00', _anchor = 'time';
  bool _fall = false, _busy = false, _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final s = AppScope.of(context).settings;
    _goal = s['goal'] as String?;
    _time = (s['preferred_time'] as String?) ?? '09:00';
    _anchor = (s['anchor'] as String?) ?? 'time';
    _fall = s['fall_concern'] == true;
    _ready = true;
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    try {
      await app.reminders?.requestPermission();
      await app.saveSettings({'preferred_time': _time, 'anchor': _anchor, 'goal': _goal, 'fall_concern': _fall});
      if (!mounted) return;
      widget.onboarding ? goHome(context) : Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SeniorScaffold(
      title: widget.onboarding ? '마지막이에요' : '알림·목표',
      progress: widget.onboarding ? 1 : null,
      primaryLabel: _busy ? '저장하는 중' : '저장하기',
      onPrimary: _busy ? null : _save,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('운동해서 하고 싶은 일이 있으세요?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text('고르시면 운동이 끝날 때 그 말로 응원해 드려요.', style: TextStyle(color: p.muted)),
        const SizedBox(height: 12),
        TwoColumn(children: [
          for (final g in goalChoices) ChoiceChipTile(label: g, on: _goal == g, onTap: () => setState(() => _goal = _goal == g ? null : g)),
        ]),
        const SectionTitle('언제 운동하면 편하세요?'),
        TwoColumn(children: [
          for (final (label, t) in timeChoices) ChoiceChipTile(label: label, on: _time == t, onTap: () => setState(() => _time = t)),
        ]),
        const SectionTitle('무엇을 한 다음에 하면 좋을까요?'),
        Text('매일 하는 일 바로 뒤에 붙이면 잊지 않아요.', style: TextStyle(color: p.muted)),
        const SizedBox(height: 12),
        for (final (label, a) in anchorChoices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ChoiceChipTile(label: label, on: _anchor == a, onTap: () => setState(() => _anchor = a)),
          ),
        const SectionTitle('넘어질까 걱정되세요?'),
        CheckTile(
          label: '네, 붙잡을 곳이 있는 운동으로 해 주세요',
          on: _fall,
          onTap: () => setState(() => _fall = !_fall),
        ),
        const SizedBox(height: 18),
        const ToneCard(
          icon: Icons.watch,
          title: '워치로도 알림 받기',
          subtitle: 'SMART-TIME PRO → 알림 설정에서 "운동친구"를 켜 주세요. 운동 시간에 워치가 진동해요.',
        ),
        const NoteRow(Icons.notifications_none, '알림은 하루 두 번까지, 아침 7시부터 저녁 8시 사이에만 와요.'),
      ]),
    );
  }
}
