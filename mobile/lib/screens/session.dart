// 화면 7·8·9: 운동 진행 / 숨찬 정도 질문 / 중단·응급.
// 운동 중 판정은 단말 안전 엔진(SessionMonitor·EmergencyFlow)이 한다. 네트워크가 끊겨도 중단·응급 흐름은 동작한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:safety_engine/safety_engine.dart';

import '../core/app_state.dart';
import '../core/exercises.dart';
import '../ui/figure.dart';
import '../ui/kit.dart';
import 'daily.dart';
import 'onboarding.dart';

// 콘텐츠(assets/exercises.json)에 없는 운동일 때만 쓰는 종류별 문장
const _guidance = {
  'aerobic': ['발을 번갈아 들어 올려요', '팔도 같이 앞뒤로 흔들어요', '숨이 조금 차는 정도면 알맞아요', '말은 할 수 있을 만큼만 해요'],
  'strength': ['천천히 힘을 주세요', '숨을 참지 말고 내쉬면서 힘을 줘요', '아프면 바로 멈추세요'],
  'balance': ['의자를 꼭 잡으세요', '천천히 균형을 잡아요', '어지러우면 바로 앉으세요'],
};

// ---------------- 7. 운동 진행 ----------------
class SessionScreen extends StatefulWidget {
  final int precheckId;
  final bool easier;
  const SessionScreen({super.key, required this.precheckId, this.easier = false});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Map<String, dynamic>? _session;
  SessionMonitor? _monitor;
  Timer? _timer;
  int _t = 0, _elapsed = 0;
  bool _paused = false, _askingRpe = false, _ending = false;
  String? _banner;
  num? _maxRpe;
  final _events = <Map<String, dynamic>>[];
  int _uploaded = 0;
  // 디즈먼트 워치(PC 브리지)로 시작한 세션: 새 값이 올 때만 넣고, 끊기면 채우지 않는다(안전 엔진이 끊김으로 판단).
  bool _live = false;
  int? _pendingBpm;
  StreamSubscription? _hrSub;
  String? _pauseCode;
  // 동작 안내: 세션 시간을 몸 풀기 → 본 운동 → 마무리 동작으로 나눈 표
  List<Segment> _plan = const [];
  int _seg = -1;
  int _lastSafetySayT = -100; // 안전 안내 직후에는 동작 안내로 말을 끊지 않는다
  String? _pendingIntro; // 안전 안내와 겹쳐 미뤄 둔 '다음 동작' 안내

  AppState get app => AppScope.of(context);
  int get _total => (_session?['minutes'] as int? ?? 0) * 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hrSub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final rules = app.rules;
    if (rules == null) {
      await showError(context, '안전 규칙을 아직 받지 못했어요. 인터넷에 연결한 뒤 다시 해 주세요.');
      if (mounted) goHome(context);
      return;
    }
    try {
      final s = await app.api.startSession(widget.precheckId, easier: widget.easier);
      if (!mounted) return;
      setState(() {
        _session = s;
        // 워치가 실시간으로 연결돼 있으면 B 등급(경고용) 심박으로, 아니면 폰만으로(확인 질문 간격이 짧아짐).
        // 건강 앱 경유 심박은 몇 분 늦어서 판정에 쓰지 않는다(늦은 값을 지금 값처럼 보면 안 됨).
        final w = app.watch;
        _live = w != null && w.connected && w.realtime;
        _monitor = SessionMonitor(rules, s['hr_limits']['ceiling'] as int, hrGrade: _live ? w!.grade : null, sink: _events.add);
        if (_live) _hrSub = w!.samples.listen((hr) => _pendingBpm = hr.bpm);
      });
      _plan = app.exercises?.plan(s['activity']['id'] as String, _total) ?? const [];
      final first = _plan.isEmpty ? '' : ' 먼저 ${phaseNames[_plan.first.phase]}, ${_plan.first.move.name}. ${_plan.first.move.how.first}';
      if (_plan.isNotEmpty) _seg = 0;
      _lastSafetySayT = 0; // 시작 안내도 끝까지 듣게
      app.say('${s['activity']['name']} ${s['minutes']}분 시작할게요. 힘들면 언제든 그만을 누르세요.$first');
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (e) {
      if (mounted) {
        await showError(context, e);
        if (mounted) goHome(context);
      }
    }
  }

  void _tick() {
    if (_ending) return;
    _t++;
    if (!_paused) _elapsed++;
    if (_live && _pendingBpm != null) {
      final bpm = _pendingBpm!;
      _pendingBpm = null;
      _handle(_monitor!.onHr(_t, bpm));
    } else {
      _handle(_monitor!.tick(_t));
    }
    if (_ending) return;
    if (!_paused && _elapsed < _total) _guide();
    if (!_ending && _elapsed >= _total) _end(completed: true);
    if (mounted) setState(() {});
  }

  /// 동작이 바뀌면 이름과 방법을, 같은 동작 중에는 짧은 문장을 일정 간격으로 말한다.
  void _guide() {
    if (_plan.isEmpty) {
      final lines = _guidance[_session!['activity']['kind']] ?? _guidance['aerobic']!;
      if (_elapsed % 30 == 0) _sayGuide(lines[(_elapsed ~/ 30) % lines.length]);
      return;
    }
    final i = segmentAt(_plan, _elapsed);
    final seg = _plan[i];
    if (i != _seg) {
      final phaseChanged = _seg < 0 || _plan[_seg].phase != seg.phase;
      _seg = i;
      final head = phaseChanged ? phaseIntros[seg.phase]! : '다음 동작이에요. ';
      _pendingIntro = '$head${seg.move.name}. ${seg.move.how.join('. ')}';
    }
    if (_pendingIntro != null) {
      if (_sayGuide(_pendingIntro!, force: true)) _pendingIntro = null;
      return;
    }
    final every = app.exercises!.cueEverySeconds;
    final inSeg = _elapsed - seg.start;
    if (inSeg > 0 && inSeg % every == 0) _sayGuide(seg.move.cues[(inSeg ~/ every - 1) % seg.move.cues.length]);
  }

  /// 말했으면 true. 안전 안내 뒤 8초(동작 바뀜 안내는 4초)는 말을 끊지 않으려고 쉰다.
  bool _sayGuide(String text, {bool force = false}) {
    if (_t - _lastSafetySayT < (force ? 4 : 8)) return false;
    app.say(text);
    return true;
  }

  void _sayAlert(String text) {
    _lastSafetySayT = _t;
    app.say(text);
  }

  void _handle(List<SafetyAction> actions) {
    for (final a in actions) {
      switch (a.kind) {
        case ActionKind.ASK_RPE:
          _askRpe();
        case ActionKind.SLOW_DOWN || ActionKind.STEP_DOWN:
          _banner = a.code.startsWith('SENSOR')
              ? '워치 신호가 끊겼어요. 조금 느리게 하시고, 숨찬 정도를 더 자주 여쭤볼게요.'
              : '천천히 하세요. 조금 더 느리게 움직여요.';
          _sayAlert(_banner!);
        case ActionKind.PAUSE:
          _paused = true;
          _pauseCode = a.code;
          _sayAlert('잠깐 쉬어요. 의자에 앉아 숨을 고르세요.');
        case ActionKind.STOP:
          _end(completed: false, emergency: false);
        case ActionKind.EMERGENCY_119:
          _end(completed: false, emergency: true);
        case ActionKind.GUARDIAN_ALERT:
          _upload();
        case ActionKind.LOUD_PROMPT:
          _sayAlert('괜찮으세요? 괜찮으시면 화면을 한 번 눌러 주세요.');
        case ActionKind.SENSOR_RESTORED:
          _banner = null;
        case ActionKind.SENSOR_FALLBACK:
          break;
      }
    }
  }

  Future<void> _askRpe() async {
    if (_askingRpe || _ending) return;
    _askingRpe = true;
    _sayAlert('숨이 차세요? 말은 하실 수 있나요?');
    final r = await Navigator.of(context).push<RpeResult>(MaterialPageRoute(builder: (_) => const RpeScreen()));
    _askingRpe = false;
    if (_ending || !mounted) return;
    if (r?.answer != null) {
      final value = app.rules!['session']['rpe']['answer_map'][r!.answer] as num;
      _maxRpe = _maxRpe == null || value > _maxRpe! ? value : _maxRpe;
      _handle(_monitor!.onRpe(_t, r.answer!));
    } else if (r?.symptom != null) {
      _handle(_monitor!.onSymptom(_t, r!.symptom!));
    } else {
      _handle(_monitor!.onInteraction(_t));
    }
  }

  /// 단말이 낸 행동을 서버 판정 로그로 보낸다. 실패하면 다음 번에 다시 보낸다.
  Future<void> _upload() async {
    final pending = _events.sublist(_uploaded);
    if (pending.isEmpty || _session == null) return;
    try {
      await app.api.sessionEvents(_session!['session_id'] as int, [
        for (final e in pending) {'t': e['t'], 'event': e['event'], 'value': e['value'], 'actions': e['actions']},
      ]);
      _uploaded += pending.length;
    } catch (_) {}
  }

  Future<void> _end({required bool completed, bool? emergency}) async {
    if (_ending) return;
    _ending = true;
    _timer?.cancel();
    final nav = Navigator.of(context);
    final finish = () async {
      await _upload();
      return app.api.finish(_session!['session_id'] as int, {
        'completed': completed,
        'minutes': (_elapsed / 60 * 10).floor() / 10,
        'max_rpe': _maxRpe,
        'stopped': emergency != null,
      });
    }();
    if (emergency != null) {
      // 응급 화면이 먼저. 기록 전송은 뒤에서(실패해도 응급 흐름을 막지 않음).
      finish.catchError((_) => <String, dynamic>{});
      nav.pushReplacement(MaterialPageRoute(builder: (_) => EmergencyScreen(severe: emergency)));
      return;
    }
    try {
      final result = await finish;
      nav.pushReplacement(MaterialPageRoute(builder: (_) => CompleteScreen(result: result)));
    } catch (e) {
      if (mounted) await showError(context, '운동은 끝났어요. 기록은 인터넷이 연결되면 다시 보내 주세요.');
      if (mounted) goHome(context);
    }
  }

  /// 어르신이 스스로 쉬기. 안전 엔진에도 쉬는 중으로 알려(무응답 감시는 계속) 다시 하기로 이어 간다.
  void _userPause() => setState(() {
        _paused = true;
        _pauseCode = 'USER_PAUSE';
        _monitor!.paused = true;
        _handle(_monitor!.onInteraction(_t));
        _sayAlert('잠깐 쉬어요. 괜찮아지면 다시 하기를 누르세요.');
      });

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final p = Palette.of(context);
    final left = (_total - _elapsed).clamp(0, _total);
    final mm = (left ~/ 60).toString(), ss = (left % 60).toString().padLeft(2, '0');
    final yellow = _session!['light'] == 'YELLOW';
    final seg = _plan.isEmpty ? null : _plan[_seg.clamp(0, _plan.length - 1)];
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true, // 화면 읽기 사용자는 아래 버튼으로 응답
      onTap: () => _handle(_monitor!.onInteraction(_t)), // 화면을 누르면 "괜찮다"는 응답으로 본다
      child: SeniorScaffold(
        title: _session!['activity']['name'] as String,
        showBack: false,
        sideBySide: true,
        primaryLabel: _paused ? '다시 하기' : '그만',
        primaryColor: _paused ? null : p.danger,
        onPrimary: _paused
            ? () => setState(() {
                  _paused = false;
                  _banner = null;
                  _handle(_monitor!.resume(_t));
                })
            : () => _handle(_monitor!.onUserStop(_t)),
        secondaryLabel: _paused ? '그만할래요' : '잠깐 쉬기',
        onSecondary: _paused ? () => _handle(_monitor!.onUserStop(_t)) : _userPause,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(seg == null ? '' : '${phaseNames[seg.phase]} · 동작 ${_seg + 1}/${_plan.length}',
                  style: TextStyle(fontSize: 18, color: p.muted)),
            ),
            _LightChip(yellow: yellow),
          ]),
          if (seg != null) ...[
            const SizedBox(height: 10),
            SegmentBar(
              weights: [for (final s in _plan) s.seconds],
              current: _seg,
              currentFraction: (_elapsed - seg.start) / seg.seconds,
            ),
          ],
          const SizedBox(height: 14),
          if (_paused) ...[
            ToneCard(
              tone: 'warn',
              icon: Icons.self_improvement,
              title: '잠깐 쉬는 중',
              subtitle: _live && (_pauseCode == 'HR_FAR_OVER_CEILING' || _pauseCode == 'HR_SUDDEN_CHANGE')
                  ? '워치 심박이 많이 높게 나왔어요. 워치는 참고용이라 멈추지 않고 잠깐 쉬게 해요. 숨이 많이 차면 그만을 누르세요.'
                  : '의자에 앉아 숨을 고르세요. 괜찮아지면 다시 하기를 누르세요.',
            ),
          ] else if (seg != null)
            _MoveCard(plan: _plan, index: _seg.clamp(0, _plan.length - 1), elapsed: _elapsed)
          else ...[
            Text('남은 시간', style: Theme.of(context).textTheme.titleLarge),
            Semantics(
              label: '남은 시간 $mm분 $ss초',
              child: Text('$mm:$ss', style: const TextStyle(fontSize: 88, fontWeight: FontWeight.w900)),
            ),
          ],
          if (_banner != null && !_paused) ...[
            const SizedBox(height: 12),
            ToneCard(tone: 'warn', icon: Icons.slow_motion_video, title: _banner!),
          ],
          if (_live) ...[
            const SizedBox(height: 16),
            _HeartCard(connected: app.watchConnected, bpm: app.lastHr?.bpm, ceiling: _session!['hr_limits']['ceiling'] as int),
          ],
          // 동작이 하나뿐이면(1분 세션) 이 동작 남은 시간과 같으므로 생략
          if (seg != null && !_paused && _plan.length > 1) ...[
            const SizedBox(height: 16),
            Row(children: [
              Text('남은 시간', style: TextStyle(fontSize: 18, color: p.muted)),
              const Spacer(),
              Semantics(
                label: '남은 시간 $mm분 $ss초',
                excludeSemantics: true,
                child: Text('$mm:$ss', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// 오늘 신호등: 색 + 글자(색만으로 구분하지 않음).
class _LightChip extends StatelessWidget {
  final bool yellow;
  const _LightChip({required this.yellow});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (bg, fg, text) = yellow ? (p.warnTint, p.onWarnTint, '노랑 · 가볍게') : (p.brandTint, p.onBrandTint, '초록 · 평소대로');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text('오늘 $text', style: TextStyle(fontSize: 16, color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

/// 지금 동작: 움직이는 그림, 이름, 하는 방법, 주의, 이 동작 남은 시간, 다음 동작.
class _MoveCard extends StatelessWidget {
  final List<Segment> plan;
  final int index, elapsed;
  const _MoveCard({required this.plan, required this.index, required this.elapsed});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final seg = plan[index];
    final m = seg.move;
    final next = index + 1 < plan.length ? plan[index + 1].move.name : null;
    final left = (seg.end - elapsed).clamp(0, seg.seconds);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 210,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.well, borderRadius: BorderRadius.circular(22)),
        child: MoveFigure(poseNames: m.poses, tempoSeconds: m.tempoSeconds, label: m.name),
      ),
      const SizedBox(height: 14),
      Text(m.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.25)),
      const SizedBox(height: 8),
      for (final (i, step) in m.how.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('${i + 1}. $step', style: TextStyle(fontSize: i == 0 ? 22 : 19, fontWeight: i == 0 ? FontWeight.w700 : null)),
        ),
      NoteRow(Icons.info_outline, m.caution),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Semantics(
          label: '이 동작 $left초 남음',
          excludeSemantics: true,
          child: Text('${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, height: 1)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('이 동작 남은 시간', style: TextStyle(fontSize: 17, color: p.muted))),
        ),
      ]),
      if (next != null) ...[
        const SizedBox(height: 8),
        Text('다음: $next', style: TextStyle(fontSize: 19, color: p.muted)),
      ],
    ]);
  }
}

// ---------------- 8. 숨찬 정도 질문 ----------------
class RpeResult {
  final String? answer; // comfortable | slightly_hard | hard | very_hard
  final String? symptom;
  const RpeResult({this.answer, this.symptom});
}

class RpeScreen extends StatefulWidget {
  const RpeScreen({super.key});
  @override
  State<RpeScreen> createState() => _RpeScreenState();
}

class _RpeScreenState extends State<RpeScreen> {
  bool _symptoms = false;

  @override
  Widget build(BuildContext context) {
    void done(RpeResult r) => Navigator.of(context).pop(r);
    if (_symptoms) {
      return SeniorScaffold(
        title: '어디가 이상하세요?',
        body: BigChoices(
          choices: const [
            ('가슴이 아프거나 조여요', 'chest_pain'),
            ('한쪽 팔다리에 힘이 빠져요', 'one_side_weakness'),
            ('말이 어눌해져요', 'slurred_speech'),
            ('숨이 너무 차요', 'shortness_of_breath'),
            ('어지러워요', 'dizziness'),
            ('식은땀이 나요', 'cold_sweat'),
            ('눈이 침침하거나 이상해요', 'vision_change'),
          ],
          onPick: (v) => done(RpeResult(symptom: v as String)),
        ),
      );
    }
    return SeniorScaffold(
      title: '숨이 차세요?',
      showBack: false,
      secondaryLabel: '몸이 이상해요',
      onSecondary: () => setState(() => _symptoms = true),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('말은 하실 수 있나요? 가장 가까운 것을 눌러 주세요.'),
        const SizedBox(height: 20),
        BigChoices(
          choices: const [
            ('편해요, 말도 잘 나와요', 'comfortable'),
            ('조금 힘들어요', 'slightly_hard'),
            ('힘들어요, 말하기 어려워요', 'hard'),
            ('너무 힘들어요', 'very_hard'),
          ],
          onPick: (v) => done(RpeResult(answer: v as String)),
        ),
      ]),
    );
  }
}

// ---------------- 9. 중단·응급 ----------------
class EmergencyScreen extends StatefulWidget {
  final bool severe;
  const EmergencyScreen({super.key, required this.severe});
  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  EmergencyFlow? _flow;
  Timer? _timer;
  int _t = 0;
  bool _notifyFailed = false;

  AppState get app => AppScope.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rules = app.rules;
      if (rules == null) {
        // 규칙 번들이 없어도 119·보호자 연락은 막지 않는다.
        setState(() {});
        app.say('119에 전화하려면 빨간 버튼을 누르세요.');
        _notify('EM_SEVERE_SYMPTOM', true);
        return;
      }
      _flow = EmergencyFlow(rules, 0, severe: widget.severe);
      _run(_flow!.started);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _run(_flow!.tick(++_t)));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _notify(String code, bool severe) async {
    try {
      await app.api.emergency({'code': code, 'severe': severe});
    } catch (_) {
      if (mounted) setState(() => _notifyFailed = true);
    }
  }

  void _run(List<EmStep> steps) {
    for (final (action, code) in steps) {
      switch (action) {
        case EmAction.REST_GUIDANCE:
          app.say(code == null ? '그 자리에 앉아서 쉬세요.' : '다행이에요. 천천히 쉬세요.');
        case EmAction.ASK_OK:
          app.say('괜찮으세요?');
        case EmAction.SHOW_119:
          app.say('119에 전화하려면 빨간 버튼을 누르세요.');
        case EmAction.DIAL_119:
          app.dialer.call('119');
        case EmAction.NOTIFY_GUARDIAN:
          _notify(code!, false);
        case EmAction.GUARDIAN_CALL_119:
          _notify(code!, true);
      }
    }
    if (_flow?.finished ?? false) _timer?.cancel();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _flow?.state ?? EmState.SHOW_119;
    const red = Color(0xFFB71C1C);
    final note = _notifyFailed ? '\n보호자에게 알리지 못했어요. 가까운 사람에게 직접 도움을 청하세요.' : '';
    return switch (state) {
      EmState.ASK_OK => SeniorScaffold(
          title: '괜찮으세요?',
          showBack: false,
          primaryLabel: '괜찮아요',
          onPrimary: () => _run(_flow!.answer(_t, true)),
          secondaryLabel: '아니에요',
          onSecondary: () => _run(_flow!.answer(_t, false)),
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('운동을 멈췄어요. 그 자리에 앉아서 쉬세요.', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 24),
            TextButton(onPressed: () => _run(_flow!.reportSevere(_t)), child: const Text('가슴이 아프거나 말이 어눌해요')),
          ]),
        ),
      EmState.SHOW_119 => SeniorScaffold(
          title: '119에 전화하세요',
          showBack: false,
          primaryLabel: '119 전화하기',
          primaryColor: red,
          onPrimary: () => _flow == null ? app.dialer.call('119') : _run(_flow!.confirm119(_t)),
          body: Text('누르면 바로 119로 전화가 걸려요. 보호자에게도 알려요.$note', style: const TextStyle(fontSize: 24)),
        ),
      _ => SeniorScaffold(
          title: state == EmState.RESTING_OK ? '천천히 쉬세요' : '도움을 부르고 있어요',
          showBack: false,
          primaryLabel: '처음 화면으로',
          onPrimary: () => goHome(context),
          body: Text(
            switch (state) {
              EmState.RESTING_OK => '오늘은 여기까지 해요. 쉬는 것도 잘하신 거예요.',
              EmState.GUARDIAN_ALERTED => '보호자에게 알렸어요. 앉아서 기다리세요.$note',
              _ => '보호자에게 119 연결을 부탁했어요. 문을 열어 두고 앉아서 기다리세요.$note',
            },
            style: const TextStyle(fontSize: 24),
          ),
        ),
    };
  }
}

/// 운동 중 워치 심박 카드: 출처·실시간 값·오늘 상한. 끊기면 숫자 대신 "연결 끊김".
class _HeartCard extends StatelessWidget {
  final bool connected;
  final int? bpm;
  final int ceiling;
  const _HeartCard({required this.connected, required this.bpm, required this.ceiling});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.watch, size: 32),
              const SizedBox(width: 8),
              Expanded(child: Text('디즈먼트 워치 ${connected ? '(실시간)' : '(연결 끊김)'}', style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 8),
            Text('지금 심박 ${connected && bpm != null ? '$bpm' : '–'}회/분 · 오늘 상한 $ceiling회/분', style: const TextStyle(fontSize: 22)),
            const Text('워치 심박은 경고용이에요. 숨찬 정도도 함께 여쭤봐요.', style: TextStyle(fontSize: 16)),
          ]),
        ),
      );
}
