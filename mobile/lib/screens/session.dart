// 화면 7·8·9: 운동 진행 / 숨찬 정도 질문 / 중단·응급.
// 운동 중 판정은 단말 안전 엔진(SessionMonitor·EmergencyFlow)이 한다. 네트워크가 끊겨도 중단·응급 흐름은 동작한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:safety_engine/safety_engine.dart';

import '../core/app_state.dart';
import '../ui/kit.dart';
import 'daily.dart';
import 'onboarding.dart';

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
      app.say('${s['activity']['name']} ${s['minutes']}분 시작할게요. 힘들면 언제든 그만을 누르세요.');
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
    final lines = _guidance[_session!['activity']['kind']] ?? _guidance['aerobic']!;
    if (!_paused && _elapsed % 30 == 0 && _elapsed < _total) app.say(lines[(_elapsed ~/ 30) % lines.length]);
    if (!_ending && _elapsed >= _total) _end(completed: true);
    if (mounted) setState(() {});
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
          app.say(_banner!);
        case ActionKind.PAUSE:
          _paused = true;
          _pauseCode = a.code;
          app.say('잠깐 쉬어요. 의자에 앉아 숨을 고르세요.');
        case ActionKind.STOP:
          _end(completed: false, emergency: false);
        case ActionKind.EMERGENCY_119:
          _end(completed: false, emergency: true);
        case ActionKind.GUARDIAN_ALERT:
          _upload();
        case ActionKind.LOUD_PROMPT:
          app.say('괜찮으세요? 괜찮으시면 화면을 한 번 눌러 주세요.');
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
    app.say('숨이 차세요? 말은 하실 수 있나요?');
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

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final left = (_total - _elapsed).clamp(0, _total);
    final mm = (left ~/ 60).toString(), ss = (left % 60).toString().padLeft(2, '0');
    final stopColor = const Color(0xFFC62828);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true, // 화면 읽기 사용자는 아래 버튼으로 응답
      onTap: () => _handle(_monitor!.onInteraction(_t)), // 화면을 누르면 "괜찮다"는 응답으로 본다
      child: SeniorScaffold(
        title: _session!['activity']['name'] as String,
        showBack: false,
        primaryLabel: _paused ? '다시 하기' : '그만',
        primaryColor: _paused ? null : stopColor,
        onPrimary: _paused
            ? () => setState(() {
                  _paused = false;
                  _banner = null;
                  _handle(_monitor!.resume(_t));
                })
            : () => _handle(_monitor!.onUserStop(_t)),
        secondaryLabel: _paused ? '그만할래요' : null,
        onSecondary: _paused ? () => _handle(_monitor!.onUserStop(_t)) : null,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_paused ? '잠깐 쉬는 중' : '남은 시간', style: Theme.of(context).textTheme.titleLarge),
          Semantics(
            label: '남은 시간 $mm분 $ss초',
            child: Text('$mm:$ss', style: const TextStyle(fontSize: 88, fontWeight: FontWeight.w900)),
          ),
          if (_paused) const Text('의자에 앉아 숨을 고르세요. 괜찮아지면 다시 하기를 누르세요.'),
          if (_paused && _live && (_pauseCode == 'HR_FAR_OVER_CEILING' || _pauseCode == 'HR_SUDDEN_CHANGE'))
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('워치 심박이 많이 높게 나왔어요. 워치는 참고용이라 멈추지 않고 잠깐 쉬게 해요. 숨이 많이 차면 그만을 누르세요.'),
            ),
          if (_banner != null && !_paused)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFFFF3C4), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.slow_motion_video, size: 36, color: Colors.black),
                const SizedBox(width: 12),
                Expanded(child: Text(_banner!, style: const TextStyle(color: Colors.black, fontSize: 22))),
              ]),
            ),
          if (_live) ...[
            const SizedBox(height: 16),
            _HeartCard(connected: app.watchConnected, bpm: app.lastHr?.bpm, ceiling: _session!['hr_limits']['ceiling'] as int),
          ],
          const SizedBox(height: 16),
          Text('오늘은 ${_session!['light'] == 'YELLOW' ? '가볍게 하는 날' : '평소대로 하는 날'}이에요.'),
        ]),
      ),
    );
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
