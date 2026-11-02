// 화면 4·5·6·10·11·12: 오늘의 운동 / 운동 전 점검 / 신호등 결과 / 완료·칭찬 / 이번 주 기록 / 보호자 연결.
import 'package:flutter/material.dart';
import 'package:safety_engine/safety_engine.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/heart_rate.dart';
import '../core/vitals.dart';
import '../ui/figure.dart';
import '../ui/kit.dart';
import 'health.dart';
import 'onboarding.dart';
import 'session.dart';

// ---------------- 4. 오늘의 운동(홈) ----------------
class TodayTab extends StatefulWidget {
  const TodayTab({super.key});
  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  Future<Map<String, dynamic>>? _today;
  VitalsSnapshot? _vitals; // 오늘 내 몸: 최근 혈압(건강 앱)

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_today == null) {
      final app = AppScope.of(context);
      _today = app.api.today();
      // 건강 앱 경유 워치는 '연결'할 것이 없으므로 홈에 오면 바로 기록을 읽는다(W3).
      final w = app.watch;
      if (w != null && !w.realtime && !w.connected) WidgetsBinding.instance.addPostFrameCallback((_) => app.connectWatch());
      app.loadSteps();
      app.syncReminders();
      if (app.readBp != null) app.latestVitals().then((v) => mounted ? setState(() => _vitals = v) : null);
    }
  }

  void _reload() => setState(() => _today = AppScope.of(context).api.today());

  static const _prompts = {
    'ask_reason': '요즘 어떠세요? 힘드셨는지, 바쁘셨는지, 아프셨는지 알려 주시면 운동을 맞춰 드릴게요.',
    'cause_check': '며칠 쉬셨네요. 시간이나 운동을 바꿔 볼까요?',
    'restart_offer': '다시 처음부터 가볍게 시작해 볼까요? 더 쉬셔도 괜찮아요.',
    'play_guardian_cheer': '가족이 응원을 보냈어요.',
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _today,
      builder: (context, snap) {
        if (snap.hasError) {
          return SeniorScaffold(title: '오늘', primaryLabel: '다시 불러오기', onPrimary: _reload, body: Text('${snap.error}'));
        }
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final t = snap.data!;
        final minutes = t['ladder']['minutes'];
        final rewards = t['rewards'] as Map;
        final prompts = (t['reengagement']['prompts'] as List).cast<String>();
        final restart = t['ladder']['restart_pending'] == true;
        // 의사 확인이 필요하면(5-1) 혈압을 재게 하기 전에 먼저 알린다. 재고 나서야 막히면 헛걸음이다.
        final blocked = app.gateBlocks.isNotEmpty;
        return SeniorScaffold(
          title: '${app.name ?? ''}님, 안녕하세요',
          showBack: false,
          primaryLabel: blocked ? '병원 확인이 필요해요' : '운동 시작하기',
          onPrimary: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => blocked ? const DoctorCheckScreen() : const PrecheckScreen())),
          secondaryLabel: restart ? '처음부터 다시 하기' : null,
          onSecondary: restart
              ? () async {
                  await app.api.post('/me/ladder/restart');
                  _reload();
                }
              : null,
          appBar: false,
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Hero(
              name: app.name ?? '',
              stamps: (rewards['weekly_stamps'] as num).toInt(),
              streak: (rewards['streak'] as num).toInt(),
              goal: app.goal,
            ),
            const SizedBox(height: 18),
            // 의사 확인이 필요하면 오늘의 운동 대신 병원 확인 카드
            if (blocked)
              const ToneCard(
                tone: 'danger',
                icon: Icons.local_hospital,
                title: '병원 확인이 먼저예요',
                subtitle: '운동을 시작하기 전에 의사 선생님 확인이 필요해요. 아래 버튼을 누르면 이유와 방법을 알려 드려요.',
              )
            else
              // 운동 전 점검(5-2)은 건너뛸 수 없다. 시작 버튼 하나 뒤에 두고, 건강 앱 기록이 있으면 확인만 하게 한다.
              _TodayWorkout(minutes: minutes as int, seated: t['state'] == 'FEAR'),
            const SectionTitle('오늘 내 몸'),
            Row(children: [
              MetricTile(
                icon: Icons.directions_walk,
                color: Palette.of(context).steps,
                label: '걸음',
                value: app.stepsToday == null ? '-' : _comma(app.stepsToday!),
              ),
              const SizedBox(width: 8),
              MetricTile(
                icon: Icons.favorite,
                color: Palette.of(context).heart,
                label: '심박',
                value: app.lastHr == null ? '-' : '${app.lastHr!.bpm}',
              ),
              const SizedBox(width: 8),
              MetricTile(
                icon: Icons.bloodtype,
                color: Palette.of(context).pressure,
                label: '혈압',
                value: _vitals?.fill == null ? '-' : '${_vitals!.fill!.systolic}/${_vitals!.fill!.diastolic}',
              ),
            ]),
            if (t['has_new_cheer'] == true) ...[
              const SizedBox(height: 14),
              const ToneCard(tone: 'warn', icon: Icons.favorite, title: '가족이 응원을 보냈어요', subtitle: '운동이 끝나면 들려 드릴게요.'),
            ],
            for (final p in prompts)
              if (_prompts[p] != null && p != 'play_guardian_cheer') NoteRow(Icons.chat_bubble_outline, _prompts[p]!),
            if (t['ask_time_change'] == true) const NoteRow(Icons.schedule, '알림을 몇 번 못 보셨네요. 시간을 바꿔 볼까요? 아래 "내 정보 → 알림·목표"에서 바꿀 수 있어요.'),
            if (app.watch != null) _WatchRow(app: app),
          ]),
        );
      },
    );
  }
}

String _todayLabel() {
  final d = DateTime.now();
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  return '${d.month}월 ${d.day}일 ${days[d.weekday - 1]}요일';
}

String _greeting(String name) {
  final h = DateTime.now().hour;
  final when = h < 11 ? '좋은 아침이에요' : (h < 17 ? '좋은 오후예요' : '편안한 저녁이에요');
  // 이름과 인사를 두 줄로 나눠 낱말 중간에서 줄이 바뀌지 않게
  return name.isEmpty ? when : '$name님,\n$when';
}

/// 홈 머리 카드: 날짜·인사, 이번 주 도장 고리, 이어 온 날, 목표.
class _Hero extends StatelessWidget {
  final String name;
  final int stamps, streak;
  final String? goal;
  const _Hero({required this.name, required this.stamps, required this.streak, this.goal});

  /// 주 3회(계획서 KPI '4주차 주 3회 이상')를 이번 주 목표로 보여 준다.
  static const weeklyTarget = 3;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const on = Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 18, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: p.hero, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_todayLabel(), style: TextStyle(fontSize: 17, color: on.withValues(alpha: 0.85))),
              const SizedBox(height: 4),
              Semantics(
                header: true,
                child: Text(_greeting(name), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: on, height: 1.25)),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          ProgressRing(
            value: stamps / weeklyTarget,
            center: '$stamps/$weeklyTarget',
            caption: '이번 주',
            color: on,
            track: on.withValues(alpha: 0.22),
            size: 104,
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _HeroChip(icon: Icons.local_fire_department, text: streak > 0 ? '$streak일째 이어가는 중' : '오늘 하면 첫 도장이에요'),
          if (goal != null) _HeroChip(icon: Icons.flag, text: '"$goal"에 한 걸음씩'),
        ]),
      ]),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HeroChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600))),
        ]),
      );
}

/// 오늘의 운동 카드: 시간과 동작 그림.
class _TodayWorkout extends StatelessWidget {
  final int minutes;
  final bool seated;
  const _TodayWorkout({required this.minutes, required this.seated});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final move = AppScope.of(context).exercises?.moves[seated ? 'seated_march' : 'home_walk_easy'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: p.brandTint, borderRadius: BorderRadius.circular(12)),
                child: Text('오늘의 운동', style: TextStyle(fontSize: 15, color: p.onBrandTint, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              Text('$minutes분', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, height: 1.1)),
              const SizedBox(height: 4),
              Text(seated ? '의자에 앉아서 할 수 있어요' : '오늘 몸에 맞게 골라 드려요', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('시작하면 먼저 몸 상태를 확인해요', style: TextStyle(fontSize: 16, color: p.muted)),
            ]),
          ),
          if (move != null)
            Container(
              width: 104,
              height: 132,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: p.well, borderRadius: BorderRadius.circular(20)),
              child: MoveFigure(poseNames: move.poses, tempoSeconds: move.tempoSeconds, label: move.name),
            ),
        ]),
      ),
    );
  }
}

// ---------------- 5. 운동 전 점검(혈압·증상) ----------------
class PrecheckScreen extends StatefulWidget {
  const PrecheckScreen({super.key});
  @override
  State<PrecheckScreen> createState() => _PrecheckScreenState();
}

class _PrecheckScreenState extends State<PrecheckScreen> {
  // 한 화면에서: 혈압·맥박(건강 앱으로 채움) + 지금 증상·오늘 컨디션 한꺼번에 고르기 + 응급 증상은 바로.
  bool _editing = true; // 숫자 칸 보이기. 건강 앱으로 채웠으면 큰 숫자 칸으로 보이고 '숫자 고치기'로 연다.
  final _sbp = TextEditingController(), _dbp = TextEditingController(), _hr = TextEditingController();
  final Set<String> _symptoms = {}, _conditions = {};
  bool _busy = false;
  // 측정 출처(안전 규칙 source_grades). 건강 앱 팔 혈압계 기록으로 채웠다가 어르신이 고치면 'manual'.
  String _bpSource = 'manual', _hrSource = 'manual';
  VitalsSnapshot? _vitals;
  bool _loadingVitals = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vitals == null && !_loadingVitals) _loadVitals();
  }

  Future<void> _loadVitals() async {
    final app = AppScope.of(context);
    if (app.readBp == null) {
      _vitals = VitalsSnapshot.empty;
      return;
    }
    setState(() => _loadingVitals = true);
    final v = await app.latestVitals();
    if (!mounted) return;
    setState(() {
      _loadingVitals = false;
      _vitals = v;
      final r = v.fill; // 팔 혈압계(A) 우선, 없으면 워치(B)
      // 이미 손으로 넣기 시작했으면 덮어쓰지 않는다
      if (r != null && _sbp.text.isEmpty && _dbp.text.isEmpty && _hr.text.isEmpty) {
        _sbp.text = '${r.systolic}';
        _dbp.text = '${r.diastolic}';
        _bpSource = r.source;
        _editing = false;
        // 맥박: 혈압과 같이 잰 값, 없으면 워치 맥박
        final pulse = r.pulse ?? v.watchPulse;
        if (pulse != null) {
          _hr.text = '$pulse';
          _hrSource = r.pulse != null ? r.source : 'watch';
        }
        void toManual(TextEditingController c, String filled, void Function() set) =>
            c.addListener(() => c.text != filled ? set() : null);
        toManual(_sbp, _sbp.text, () => _bpSource = 'manual');
        toManual(_dbp, _dbp.text, () => _bpSource = 'manual');
        if (pulse != null) toManual(_hr, _hr.text, () => _hrSource = 'manual');
      }
    });
  }

  // 증상(s:)과 오늘 컨디션(c:)을 한 목록으로. 코드는 안전 규칙 precheck 의 증상·컨디션 이름.
  static const _chips = [
    ('숨이 많이 차요', 's:shortness_of_breath'),
    ('어지러워요', 's:dizziness'),
    ('조금 피곤해요', 's:mild_fatigue'),
    ('아주 많이 피곤해요', 's:severe_unusual_fatigue'),
    ('열·감기·설사가 있어요', 'c:fever'),
    ('어젯밤 잠을 못 잤어요', 'c:poor_sleep'),
    ('오늘 약을 아직 안 먹었어요', 'c:missed_medication'),
    ('3일 넘게 운동을 쉬었어요', 'c:rested_3plus_days'),
  ];

  bool _picked(String key) => key.startsWith('s:') ? _symptoms.contains(key.substring(2)) : _conditions.contains(key.substring(2));

  void _toggle(String key) => setState(() {
        final set = key.startsWith('s:') ? _symptoms : _conditions;
        final code = key.substring(2);
        set.contains(code) ? set.remove(code) : set.add(code);
      });

  /// 응급 증상은 숫자를 기다리지 않고 바로 판정(119 안내).
  void _emergency(String symptom) {
    _symptoms.add(symptom);
    _submit();
  }

  void _check() {
    if (_sbp.text.isEmpty || _dbp.text.isEmpty || _hr.text.isEmpty) {
      setState(() => _editing = true);
      showError(context, '혈압 두 숫자와 맥박을 모두 넣어 주세요. 의자에 앉아 5분 쉬고 재 주세요.');
      return;
    }
    _submit();
  }

  Future<void> _submit() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final conditions = _conditions.toList();
    final body = {
      'systolic': num.tryParse(_sbp.text),
      'diastolic': num.tryParse(_dbp.text),
      'resting_hr': num.tryParse(_hr.text),
      'bp_source': _bpSource,
      'hr_source': _hrSource,
      'symptoms': _symptoms.toList(),
      'conditions': conditions,
    };
    // 단말 안전 엔진이 먼저 판정(오프라인에서도 동작). 서버 판정과 다르면 더 나쁜 쪽을 따른다.
    Decision? local;
    if (app.rules != null) {
      local = preCheck(
        app.rules!,
        app.profile,
        Vitals(
          systolic: body['systolic'] as num?,
          diastolic: body['diastolic'] as num?,
          restingHr: body['resting_hr'] as num?,
          bpSource: _bpSource,
          hrSource: _hrSource,
        ),
        symptoms: _symptoms,
        conditions: conditions,
      );
    }
    Map<String, dynamic>? server;
    Object? error;
    try {
      server = await app.api.precheck(body);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (server == null && local == null) {
      showError(context, error ?? '잠시 후 다시 해 주세요');
      return;
    }
    var outcome = server?['outcome'] as String? ?? local!.outcome;
    if (local != null && severity(local.light) > severity(lightOf(outcome))) outcome = local.outcome;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LightResultScreen(outcome: outcome, server: server, offline: server == null)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final none = _symptoms.isEmpty && _conditions.isEmpty;
    return SeniorScaffold(
      title: '몸 상태 확인',
      progress: 0.5,
      primaryLabel: _busy ? '확인하는 중' : (none ? '없어요, 괜찮아요' : '이대로 확인하기'),
      onPrimary: _busy ? null : _check,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('오늘 혈압이에요', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (_loadingVitals) const NoteRow(Icons.hourglass_empty, '건강 앱 기록을 확인하는 중이에요'),
        if (!_editing) ...[
          Row(children: [
            StatTile(label: '혈압', value: _sbp.text, unit: '/${_dbp.text}', flex: 2),
            const SizedBox(width: 10),
            StatTile(label: '맥박', value: _hr.text.isEmpty ? '-' : _hr.text),
          ]),
          if (_vitals != null) _VitalsNotes(_vitals!),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit, size: 26),
              label: const Text('숫자 고치기'),
            ),
          ),
        ] else ...[
          Text(_vitals?.fill != null ? '숫자가 맞는지 보고, 다르면 고쳐 주세요.' : '의자에 앉아 5분 쉰 뒤, 혈압을 재 주세요. 워치로 재도 괜찮아요.',
              style: TextStyle(color: p.muted)),
          if (_vitals != null) _VitalsNotes(_vitals!),
          const SizedBox(height: 14),
          BigNumberField(label: '높은 쪽 숫자(수축기)', unit: 'mmHg', controller: _sbp),
          BigNumberField(label: '낮은 쪽 숫자(이완기)', unit: 'mmHg', controller: _dbp),
          BigNumberField(label: '맥박', unit: '회/분', controller: _hr),
        ],
        const SectionTitle('지금 이런 게 있으세요?'),
        Text('있는 것만 눌러 주세요. 없으면 아래 "없어요, 괜찮아요"를 누르세요.', style: TextStyle(color: p.muted)),
        const SizedBox(height: 12),
        TwoColumn(children: [
          for (final (label, key) in _chips) ChoiceChipTile(label: label, on: _picked(key), onTap: () => _toggle(key)),
        ]),
        const SizedBox(height: 12),
        // 응급 증상(5-2): 판정을 기다리지 않고 바로 119 안내
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.dangerTint, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.emergency, color: p.onDangerTint, size: 28),
              const SizedBox(width: 8),
              Expanded(child: Text('이런 게 있으면 바로 눌러 주세요', style: TextStyle(color: p.onDangerTint, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            for (final (label, code) in const [('가슴이 아프거나 조여요', 'chest_pain'), ('한쪽 팔다리에 힘이 빠지거나 말이 어눌해요', 'one_side_weakness')])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _emergency(code),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.danger,
                    side: BorderSide(color: p.danger, width: 2),
                    alignment: Alignment.center,
                  ),
                  child: Text(label, textAlign: TextAlign.center),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// 건강 앱에서 가져온 혈압 안내: 채운 기록의 출처·시각, 오래된 기록, 워치 혈압(참고용).
class _VitalsNotes extends StatelessWidget {
  final VitalsSnapshot v;
  const _VitalsNotes(this.v);

  Widget _note(IconData icon, String text) => NoteRow(icon, text);

  @override
  Widget build(BuildContext context) {
    final fill = v.fill, watch = v.watch;
    final pulseMissing = fill != null && fill.pulse == null && v.watchPulse == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (fill != null && fill.source != 'watch')
        _note(Icons.check_circle, '건강 앱의 혈압계 기록을 넣어 두었어요 (${fill.sourceName}, ${_ago(fill.at)})'),
      if (fill != null && fill.source == 'watch')
        _note(Icons.watch, '워치에서 잰 혈압을 넣어 두었어요 (${_ago(fill.at)}). 워치는 조금 틀릴 수 있어서 오늘은 가볍게 하는 날로 정해요.'),
      if (fill != null && fill.pulse == null && v.watchPulse != null) _note(Icons.favorite_border, '맥박은 워치 기록이에요 (${_ago(v.watchPulseAt!)})'),
      if (pulseMissing) _note(Icons.edit, '맥박은 직접 넣어 주세요'),
      if (fill == null && watch != null)
        _note(Icons.schedule, '워치 혈압 기록이 ${_ago(watch.at)}이에요. 워치에서 혈압을 다시 재고 이 화면을 다시 열어 주세요.'),
      if (fill == null && watch == null && v.stale != null)
        _note(Icons.schedule, '마지막 혈압 기록이 ${_ago(v.stale!.at)}이라 지금 다시 재 주세요.'),
    ]);
  }
}

// ---------------- 6. 신호등 결과 ----------------
class LightResultScreen extends StatelessWidget {
  final String outcome;
  final Map<String, dynamic>? server;
  final bool offline;
  const LightResultScreen({super.key, required this.outcome, this.server, this.offline = false});

  @override
  Widget build(BuildContext context) {
    final plan = server?['plan'] as Map<String, dynamic>?;
    final message = (plan?['message'] as Map?)?['text'] as String?;
    final canExercise = !offline && plan?['action'] == 'EXERCISE' && (outcome == 'GREEN' || outcome == 'YELLOW');

    void start({bool easier = false}) => Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => SessionScreen(precheckId: server!['precheck_id'] as int, easier: easier)));

    final (String label, VoidCallback action) = switch (outcome) {
      'EMERGENCY' => (
          '도움 요청하기',
          () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const EmergencyScreen(severe: true)))
        ),
      'REMEASURE' => ('다시 재기', () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PrecheckScreen()))),
      _ when canExercise => ('${plan!['minutes']}분 시작하기', () => start()),
      _ => ('확인', () => goHome(context)),
    };
    return SeniorScaffold(
      title: '오늘 몸 상태',
      showBack: false,
      primaryLabel: label,
      onPrimary: action,
      primaryColor: outcome == 'EMERGENCY' ? Palette.of(context).danger : null,
      secondaryLabel: canExercise ? '더 쉬운 걸로 (${plan!['easier']['minutes']}분)' : null,
      onSecondary: canExercise ? () => start(easier: true) : null,
      body: SpeakOnce(text: message, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LightBadge(outcome: outcome),
        const SizedBox(height: 20),
        if (message != null) Text(message, style: const TextStyle(fontSize: 24, height: 1.4)),
        if (canExercise) _PlanPreview(activityId: plan!['activity_id'] as String?, minutes: plan['minutes'] as int),
        if (outcome == 'RED') const NoteRow(Icons.verified, '재 주신 것만으로도 오늘 도장을 받으셨어요.'),
        if (offline) const NoteRow(Icons.wifi_off, '인터넷에 연결되면 운동을 시작할 수 있어요.'),
      ])),
    );
  }
}

/// 오늘 할 운동 미리 보기: 이름, 시간, 첫 동작 그림.
class _PlanPreview extends StatelessWidget {
  final String? activityId;
  final int minutes;
  const _PlanPreview({required this.activityId, required this.minutes});

  @override
  Widget build(BuildContext context) {
    final lib = AppScope.of(context).exercises;
    final name = activityId == null ? null : lib?.activityNames[activityId];
    final move = activityId == null ? null : lib?.firstMainMove(activityId!);
    if (name == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            if (move != null)
              Container(
                width: 96,
                height: 120,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Palette.of(context).well, borderRadius: BorderRadius.circular(16)),
                child: MoveFigure(poseNames: move.poses, tempoSeconds: move.tempoSeconds, label: move.name),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('오늘의 운동', style: TextStyle(fontSize: 17, color: Palette.of(context).muted)),
                Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.3)),
                Text('$minutes분 · 몸 풀기부터 천천히', style: TextStyle(fontSize: 18, color: Palette.of(context).muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------- 10. 완료·칭찬 ----------------
class CompleteScreen extends StatelessWidget {
  final Map<String, dynamic> result;
  final DateTime? startedAt, endedAt;
  const CompleteScreen({super.key, required this.result, this.startedAt, this.endedAt});

  @override
  Widget build(BuildContext context) {
    final cheer = result['cheer'] as Map?;
    final spoken = [result['message'] as String, if (cheer?['text'] != null) '${cheer!['from']}님의 응원이에요. ${cheer['text']}'];
    final rewards = result['rewards'] as Map;
    return SeniorScaffold(
      title: '해내셨어요',
      showBack: false,
      primaryLabel: '확인',
      onPrimary: () => goHome(context),
      body: SpeakOnce(text: spoken.join(' '), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(Icons.verified, size: 120, color: Palette.of(context).brand),
        Text(result['message'] as String, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
        const SectionTitle('이번 주 도장'),
        StampRow(filled: ((rewards['weekly_stamps'] as num?) ?? 1).toInt(), slots: 3),
        const SizedBox(height: 8),
        Text('오늘 도장 ✓  ·  ${rewards['streak']}일째', textAlign: TextAlign.center, style: TextStyle(color: Palette.of(context).muted)),
        if (cheer != null) ...[
          const SizedBox(height: 24),
          ToneCard(icon: Icons.favorite, label: '${cheer['from']}님의 응원', title: (cheer['text'] as String?) ?? '음성 응원이 왔어요'),
        ],
        if (startedAt != null && endedAt != null && AppScope.of(context).readHr != null)
          WatchSummaryCard(from: startedAt!, to: endedAt!),
      ])),
    );
  }
}

/// 운동한 시간대의 워치 기록(건강 앱): 심박 평균·최고, 걸음(W2). 워치 심박은 B 등급이라 보여 주기만 한다.
/// SMART-TIME PRO 동기화가 늦으면 비어 있으므로 '다시 불러오기'를 둔다.
class WatchSummaryCard extends StatefulWidget {
  final DateTime from, to;
  const WatchSummaryCard({super.key, required this.from, required this.to});
  @override
  State<WatchSummaryCard> createState() => _WatchSummaryCardState();
}

class _WatchSummaryCardState extends State<WatchSummaryCard> {
  List<HrSample>? _hr;
  int? _steps;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hr == null && !_loading) _load();
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    setState(() => _loading = true);
    // 동기화가 운동 끝보다 조금 늦게 기록하는 경우가 있어 앞뒤로 1분 여유
    final from = widget.from.subtract(const Duration(minutes: 1)), to = widget.to.add(const Duration(minutes: 1));
    List<HrSample> hr = const [];
    int? steps;
    try {
      hr = await app.readHr!(from, to).timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      steps = await app.readSteps?.call(from, to).timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _hr = hr;
      _steps = steps;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hr = _hr ?? const <HrSample>[];
    final has = hr.isNotEmpty || (_steps ?? 0) > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.watch, size: 30, color: Palette.of(context).brand),
              const SizedBox(width: 8),
              const Expanded(child: Text('워치 기록', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const Text('워치 기록을 불러오는 중이에요')
            else if (has) ...[
              Row(children: [
                if (hr.isNotEmpty) ...[
                  StatTile(label: '평균 심박', value: '${(hr.map((s) => s.bpm).reduce((a, b) => a + b) / hr.length).round()}'),
                  const SizedBox(width: 10),
                  StatTile(label: '최고 심박', value: '${hr.map((s) => s.bpm).reduce((a, b) => a > b ? a : b)}'),
                ],
                if (hr.isNotEmpty && _steps != null) const SizedBox(width: 10),
                if (_steps != null) StatTile(label: '걸음', value: _comma(_steps!)),
              ]),
              const NoteRow(Icons.info_outline, '워치 숫자는 참고용이에요. 숨찬 정도를 함께 보세요.'),
            ] else ...[
              const Text('아직 워치 기록이 안 들어왔어요. 워치를 차고 SMART-TIME PRO를 열면 동기화돼요.'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _load,
                style: OutlinedButton.styleFrom(alignment: Alignment.center),
                icon: const Icon(Icons.refresh, size: 26),
                label: const Text('다시 불러오기'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ---------------- 11. 이번 주 기록 ----------------
class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});
  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  static const _days = ['월', '화', '수', '목', '금', '토', '일'];
  Future<Map<String, dynamic>>? _week;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _week ??= AppScope.of(context).api.week(); // 탭을 오가며 다시 그려도 한 번만 불러온다
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _week,
        builder: (context, snap) {
          if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final p = Palette.of(context);
          final days = [...(snap.data!['days'] as List).cast<Map>()]..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
          final stamps = days.where((d) => d['stamp'] == true).length;
          final total = days.fold<num>(0, (sum, d) => sum + (d['minutes'] as num));
          return SeniorScaffold(
            title: '이번 주 기록',
            showBack: Navigator.of(context).canPop(),
            primaryLabel: null,
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                MetricTile(icon: Icons.verified, color: p.brand, label: '도장', value: '$stamps', unit: '개'),
                const SizedBox(width: 8),
                MetricTile(icon: Icons.timer, color: p.steps, label: '운동 시간', value: '${total.round()}', unit: '분'),
                const SizedBox(width: 8),
                MetricTile(icon: Icons.local_fire_department, color: p.heart, label: '이어 온 날', value: '${snap.data!['streak']}', unit: '일'),
              ]),
              const SectionTitle('요일별 운동'),
              if (days.isEmpty)
                const NoteRow(Icons.info_outline, '아직 기록이 없어요. 오늘 첫 운동을 해 보세요.')
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                    child: _WeekBars(days: days, labels: _days),
                  ),
                ),
              const SizedBox(height: 8),
              for (final d in days.reversed)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    minTileHeight: 64,
                    leading: Icon(d['stamp'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 36, color: d['stamp'] == true ? p.brand : p.muted),
                    title: Text('${_days[DateTime.parse(d['date'] as String).weekday - 1]}요일 '
                        '${d['stamp'] == true ? '도장 받음' : '쉼'}${(d['minutes'] as num) > 0 ? ' · ${d['minutes']}분' : ''}'),
                  ),
                ),
              const NoteRow(Icons.info_outline, '도장은 운동을 시작하거나, 혈압을 재거나, 쉬라는 날 쉬면 받아요.'),
            ]),
          );
        },
      );
}

/// 요일별 운동 시간 막대(도장 받은 날은 진한 색 + 체크). 숫자도 함께 적어 색만으로 읽지 않게.
class _WeekBars extends StatelessWidget {
  final List<Map> days;
  final List<String> labels;
  const _WeekBars({required this.days, required this.labels});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final most = days.map((d) => (d['minutes'] as num).toDouble()).fold<double>(10, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 200,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in days)
          Expanded(
            child: Semantics(
              container: true,
              label: '${labels[DateTime.parse(d['date'] as String).weekday - 1]}요일 ${d['minutes']}분${d['stamp'] == true ? ', 도장' : ''}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text((d['minutes'] as num) > 0 ? '${d['minutes']}' : '', style: TextStyle(fontSize: 15, color: p.muted)),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (d['minutes'] as num) / most),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Container(
                      height: 8 + 120 * v,
                      decoration: BoxDecoration(
                        color: d['stamp'] == true ? p.brand : p.well,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.topCenter,
                      padding: const EdgeInsets.only(top: 4),
                      child: d['stamp'] == true && v > 0.2 ? Icon(Icons.check, size: 18, color: p.onBrand) : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(labels[DateTime.parse(d['date'] as String).weekday - 1],
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

// ---------------- 12. 보호자 연결 설정 ----------------
class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key});
  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  Future<List>? _links;
  static const scopes = {
    'emergency_only': '위급할 때만 알려요',
    'cheer_only': '응원만 받아요 (운동 여부는 안 보여요)',
    'full': '오늘 운동했는지와 주간 요약도 알려요',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _links ??= AppScope.of(context).api.guardians();
  }

  Future<void> _update(int id, {String? status, String? scope}) async {
    final api = AppScope.of(context).api;
    try {
      await api.updateGuardian(id, status: status, scope: scope);
      setState(() => _links = api.guardians());
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List>(
        future: _links,
        builder: (context, snap) {
          final links = snap.data ?? const [];
          return SeniorScaffold(
            title: '보호자 연결',
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('보호자에게 무엇을 알릴지 직접 고르세요. 언제든 바꾸거나 끊을 수 있어요.'),
              if (snap.hasData && links.isEmpty) const Text('\n아직 연결된 보호자가 없어요. 보호자 앱에서 연결을 요청하면 여기에 보여요.'),
              for (final l in links) ...[
                const SizedBox(height: 20),
                Text('${l['guardian']}님 · ${l['status'] == 'active' ? '연결됨' : l['status'] == 'pending' ? '연결 요청' : '끊음'}',
                    style: Theme.of(context).textTheme.titleLarge),
                if (l['status'] == 'pending')
                  FilledButton(onPressed: () => _update(l['link_id'] as int, status: 'active'), child: const Text('연결하기')),
                if (l['status'] == 'active') ...[
                  for (final s in scopes.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OutlinedButton.icon(
                        onPressed: () => _update(l['link_id'] as int, scope: s.key),
                        icon: Icon(l['scope'] == s.key ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 32),
                        label: Align(alignment: Alignment.centerLeft, child: Text(s.value)),
                      ),
                    ),
                  TextButton(onPressed: () => _update(l['link_id'] as int, status: 'revoked'), child: const Text('연결 끊기')),
                ],
              ],
            ]),
          );
        },
      );
}

String _ago(DateTime at) {
  final m = DateTime.now().difference(at).inMinutes;
  if (m < 1) return '방금';
  if (m < 60) return '$m분 전';
  return '${m ~/ 60}시간 전';
}

/// 홈 화면 워치 상태(7-4: 연결 상태를 크게 보여 줌).
/// 실시간(PC 브리지)은 연결 버튼, 건강 앱 경유는 마지막 워치 기록 시각과 오늘 걸음 + 동기화 안내(W1·W3).
class _WatchRow extends StatelessWidget {
  final AppState app;
  const _WatchRow({required this.app});

  /// 이보다 오래된 워치 기록이면 워치를 안 찼거나 동기화가 안 된 것으로 본다.
  static const staleAfter = Duration(hours: 2);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final w = app.watch!;
    final on = app.watchConnected;
    final hr = app.lastHr;
    final stale = !w.realtime && (hr == null || DateTime.now().difference(hr.at) > staleAfter);
    final status = w.realtime
        ? (on && hr != null ? '${app.watchStatus} · 심박 ${hr.bpm}' : app.watchStatus)
        : hr != null
            ? '건강 앱 · 최근 심박 ${hr.bpm} (${_ago(hr.at)})'
            : (on ? '워치 기록을 기다리는 중' : app.watchStatus);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(on && !stale ? Icons.watch : Icons.watch_off, size: 36, color: on && !stale ? p.brand : p.muted),
              const SizedBox(width: 10),
              Expanded(child: Text(status, style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            if (app.stepsToday != null) NoteRow(Icons.directions_walk, '오늘 걸음 ${_comma(app.stepsToday!)}보'),
            if (stale) const NoteRow(Icons.sync_problem, '워치 기록이 한동안 없어요. 워치를 차고 SMART-TIME PRO를 열어 동기화해 주세요.'),
            const SizedBox(height: 8),
            if (w.realtime)
              OutlinedButton(
                onPressed: on ? app.disconnectWatch : app.connectWatch,
                style: OutlinedButton.styleFrom(alignment: Alignment.center, minimumSize: const Size.fromHeight(56)),
                child: Text(on ? '워치 연결 끊기' : '워치 연결하기'),
              )
            else
              OutlinedButton.icon(
                onPressed: () {
                  app.connectWatch();
                  app.loadSteps();
                },
                style: OutlinedButton.styleFrom(alignment: Alignment.center, minimumSize: const Size.fromHeight(56)),
                icon: const Icon(Icons.refresh, size: 26),
                label: const Text('워치 기록 다시 불러오기'),
              ),
          ]),
        ),
      ),
    );
  }
}

String _comma(int n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
