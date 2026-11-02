// 화면 4·5·6·10·11·12: 오늘의 운동 / 운동 전 점검 / 신호등 결과 / 완료·칭찬 / 이번 주 기록 / 보호자 연결.
import 'package:flutter/material.dart';
import 'package:safety_engine/safety_engine.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import 'onboarding.dart';
import 'session.dart';

// ---------------- 4. 오늘의 운동(홈) ----------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<Map<String, dynamic>>? _today;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _today ??= AppScope.of(context).api.today();
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
        return SeniorScaffold(
          title: '${app.name ?? ''}님, 안녕하세요',
          showBack: false,
          primaryLabel: '혈압 재고 시작하기',
          onPrimary: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrecheckScreen())),
          secondaryLabel: restart ? '처음부터 다시 하기' : null,
          onSecondary: restart
              ? () async {
                  await app.api.post('/me/ladder/restart');
                  _reload();
                }
              : null,
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('오늘 할 운동', style: Theme.of(context).textTheme.titleLarge),
            Text('$minutes분', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900)),
            const Text('혈압을 재면 오늘 몸 상태에 맞춰 골라 드려요.'),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.local_fire_department, size: 32),
              const SizedBox(width: 8),
              Expanded(child: Text('${rewards['streak']}일째 이어가는 중 · 이번 주 도장 ${rewards['weekly_stamps']}개')),
            ]),
            if (app.watch != null) _WatchRow(app: app),
            if (t['has_new_cheer'] == true)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Row(children: [Icon(Icons.favorite, size: 32), SizedBox(width: 8), Expanded(child: Text('가족이 응원을 보냈어요. 운동이 끝나면 들려 드릴게요.'))]),
              ),
            for (final p in prompts)
              if (_prompts[p] != null && p != 'play_guardian_cheer')
                Padding(padding: const EdgeInsets.only(top: 12), child: Text(_prompts[p]!)),
            if (t['ask_time_change'] == true)
              const Padding(padding: EdgeInsets.only(top: 12), child: Text('알림 시간이 불편하시면 보호자 연결 화면에서 바꿀 수 있어요.')),
            const SizedBox(height: 24),
            Wrap(spacing: 8, runSpacing: 8, children: [
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeekScreen())),
                icon: const Icon(Icons.calendar_month, size: 28),
                label: const Text('이번 주 기록'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuardianScreen())),
                icon: const Icon(Icons.family_restroom, size: 28),
                label: const Text('보호자 연결'),
              ),
              TextButton.icon(
                onPressed: app.cycleTextScale,
                icon: const Icon(Icons.format_size, size: 28),
                label: Text('글자 크기 ${((app.textScale - 1) / 0.25).round() + 1}단계'),
              ),
            ]),
          ]),
        );
      },
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
  int _step = 0; // 0 숫자, 1 가슴·숨, 2 어지러움, 3 피로, 4 오늘 컨디션
  final _sbp = TextEditingController(), _dbp = TextEditingController(), _hr = TextEditingController();
  final Set<String> _symptoms = {}, _conditions = {};
  bool _busy = false;

  static const _conditionLabels = {
    'fever': '열이 나거나 감기·설사가 있어요',
    'poor_sleep': '어젯밤 잠을 잘 못 잤어요',
    'missed_medication': '오늘 먹을 약을 아직 안 먹었어요',
    'rested_3plus_days': '3일 넘게 운동을 쉬었어요',
  };

  void _answer(String? symptom) {
    if (symptom != null) _symptoms.add(symptom);
    // 가슴 통증은 판정을 기다리지 않고 바로 결과(119)로
    if (symptom == 'chest_pain') {
      _submit();
      return;
    }
    setState(() => _step++);
  }

  Future<void> _submit() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final conditions = _conditions.toList();
    final body = {
      'systolic': num.tryParse(_sbp.text),
      'diastolic': num.tryParse(_dbp.text),
      'resting_hr': num.tryParse(_hr.text),
      'symptoms': _symptoms.toList(),
      'conditions': conditions,
    };
    // 단말 안전 엔진이 먼저 판정(오프라인에서도 동작). 서버 판정과 다르면 더 나쁜 쪽을 따른다.
    Decision? local;
    if (app.rules != null) {
      local = preCheck(
        app.rules!,
        Profile(age: app.age),
        Vitals(systolic: body['systolic'] as num?, diastolic: body['diastolic'] as num?, restingHr: body['resting_hr'] as num?),
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
    switch (_step) {
      case 0:
        return SeniorScaffold(
          title: '혈압을 넣어 주세요',
          primaryLabel: '다음',
          onPrimary: () {
            if (_sbp.text.isEmpty || _dbp.text.isEmpty || _hr.text.isEmpty) {
              showError(context, '세 숫자를 모두 넣어 주세요. 의자에 앉아 5분 쉬고 팔에 감는 혈압계로 재 주세요.');
              return;
            }
            setState(() => _step = 1);
          },
          body: Column(children: [
            const Text('의자에 앉아 5분 쉰 뒤, 팔에 감는 혈압계로 재 주세요.'),
            const SizedBox(height: 16),
            BigNumberField(label: '높은 쪽 숫자(수축기)', unit: 'mmHg', controller: _sbp),
            BigNumberField(label: '낮은 쪽 숫자(이완기)', unit: 'mmHg', controller: _dbp),
            BigNumberField(label: '맥박', unit: '회/분', controller: _hr),
          ]),
        );
      case 1:
        return _question('지금 가슴이 아프거나 숨이 많이 차세요?',
            [('아니요, 괜찮아요', null), ('숨이 많이 차요', 'shortness_of_breath'), ('가슴이 아프거나 조여요', 'chest_pain')]);
      case 2:
        return _question('어지럽거나 쓰러질 것 같으세요?', [('아니요', null), ('네, 어지러워요', 'dizziness')]);
      case 3:
        return _question('평소와 다르게 피곤하세요?',
            [('아니요', null), ('조금 피곤해요', 'mild_fatigue'), ('아주 많이 피곤해요', 'severe_unusual_fatigue')]);
      default:
        return SeniorScaffold(
          title: '오늘 이런 일이 있으세요?',
          primaryLabel: _busy ? '확인하는 중' : '결과 보기',
          onPrimary: _busy ? null : _submit,
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('해당하는 것만 눌러 주세요. 없으면 바로 결과 보기를 누르세요.'),
            const SizedBox(height: 12),
            for (final e in _conditionLabels.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _conditions.contains(e.key) ? _conditions.remove(e.key) : _conditions.add(e.key)),
                  icon: Icon(_conditions.contains(e.key) ? Icons.check_box : Icons.check_box_outline_blank, size: 32),
                  label: Align(alignment: Alignment.centerLeft, child: Text(e.value)),
                ),
              ),
          ]),
        );
    }
  }

  Widget _question(String q, List<(String, String?)> answers) => SeniorScaffold(
        title: '몸 상태 확인',
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(q, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          BigChoices(choices: [for (final (l, v) in answers) (l, v ?? '')], onPick: (v) => _answer(v == '' ? null : v as String)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _answer('one_side_weakness'),
            child: const Text('한쪽 팔다리에 힘이 빠지거나 말이 어눌해요'),
          ),
        ]),
      );
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
      primaryColor: outcome == 'EMERGENCY' ? const Color(0xFFB71C1C) : null,
      secondaryLabel: canExercise ? '더 쉬운 걸로 (${plan!['easier']['minutes']}분)' : null,
      onSecondary: canExercise ? () => start(easier: true) : null,
      body: SpeakOnce(text: message, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LightBadge(outcome: outcome),
        const SizedBox(height: 20),
        if (message != null) Text(message, style: const TextStyle(fontSize: 24)),
        if (outcome == 'RED') const Text('\n재 주신 것만으로도 오늘 도장을 받으셨어요.'),
        if (offline) const Text('\n인터넷에 연결되면 운동을 시작할 수 있어요.'),
      ])),
    );
  }
}

// ---------------- 10. 완료·칭찬 ----------------
class CompleteScreen extends StatelessWidget {
  final Map<String, dynamic> result;
  const CompleteScreen({super.key, required this.result});

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
        const Icon(Icons.verified, size: 120),
        Text(result['message'] as String, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text('오늘 도장 ✓  ·  ${rewards['streak']}일째', textAlign: TextAlign.center),
        if (cheer != null) ...[
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('${cheer['from']}님의 응원\n${cheer['text'] ?? '음성 응원이 왔어요'}', style: const TextStyle(fontSize: 22)),
            ),
          ),
        ],
      ])),
    );
  }
}

// ---------------- 11. 이번 주 기록 ----------------
class WeekScreen extends StatelessWidget {
  const WeekScreen({super.key});
  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: AppScope.of(context).api.week(),
        builder: (context, snap) {
          if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final days = snap.data!['days'] as List;
          return SeniorScaffold(
            title: '이번 주 기록',
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${snap.data!['streak']}일째 이어가는 중', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              for (final d in days)
                ListTile(
                  minTileHeight: 64,
                  leading: Icon(d['stamp'] == true ? Icons.check_circle : Icons.radio_button_unchecked, size: 40),
                  title: Text('${_days[DateTime.parse(d['date'] as String).weekday - 1]}요일 '
                      '${d['stamp'] == true ? '도장 받음' : '쉼'}${(d['minutes'] as num) > 0 ? ' · ${d['minutes']}분' : ''}'),
                ),
              const Text('\n도장은 운동을 시작하거나, 혈압을 재거나, 쉬라는 날 쉬면 받아요.'),
            ]),
          );
        },
      );
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

/// 홈 화면 워치 상태: 큰 아이콘 + 상태 문장 + 연결 버튼(계획서 7-4: 연결 상태를 크게 보여 줌).
class _WatchRow extends StatelessWidget {
  final AppState app;
  const _WatchRow({required this.app});

  @override
  Widget build(BuildContext context) {
    final on = app.watchConnected;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(on ? Icons.watch : Icons.watch_off, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  on && app.lastHr != null
                      ? app.watch!.realtime
                          ? '${app.watchStatus} · 심박 ${app.lastHr!.bpm}'
                          : '건강 앱 · 최근 심박 ${app.lastHr!.bpm} (${_ago(app.lastHr!.at)})'
                      : app.watchStatus,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: on ? app.disconnectWatch : app.connectWatch,
              child: Text(on ? '워치 연결 끊기' : '워치 연결하기'),
            ),
          ]),
        ),
      ),
    );
  }
}
