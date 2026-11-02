// 화면 1~3: 시작·본인인증 / 기본 정보·질환 / 운동 전 문진. 온보딩 5분 이내, 보호자 대리 설정도 같은 화면.
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../ui/kit.dart';
import 'daily.dart';

// ---------------- 1. 시작·본인인증 ----------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;

  Future<void> _next() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    try {
      if (!_codeSent) {
        await app.api.requestOtp(_phone.text);
        setState(() => _codeSent = true);
        await app.say('문자로 온 숫자 여섯 개를 넣어 주세요');
      } else {
        try {
          await app.saveToken(await app.api.verifyOtp(_phone.text, _code.text));
          await app.loadMe();
          await app.refreshRules();
          if (mounted) goHome(context);
        } on ApiException catch (e) {
          if (e.status != 422) rethrow;
          // 처음 오신 분: 이름·태어난 해를 받고 같은 인증번호로 가입
          if (mounted) {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => BasicInfoScreen(phone: _phone.text, code: _code.text)));
          }
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SeniorScaffold(
        title: '반가워요',
        showBack: false,
        primaryLabel: _codeSent ? '확인' : '인증번호 받기',
        onPrimary: _busy ? null : _next,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('휴대폰 번호로 시작해요. 아이디나 비밀번호는 필요 없어요.'),
          const SizedBox(height: 24),
          if (!_codeSent)
            BigNumberField(label: '휴대폰 번호', unit: '', controller: _phone, maxDigits: 11)
          else
            BigNumberField(label: '문자로 온 인증번호', unit: '', controller: _code, maxDigits: 6),
          if (_codeSent) const Text('문자가 안 오면 뒤로 가서 다시 받으세요.'),
        ]),
      );
}

/// 홈으로 가면서 쌓인 화면을 비운다.
void goHome(BuildContext context) =>
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);

// ---------------- 2. 기본 정보·질환 선택 ----------------
const gateConditions = {
  'unstable_angina': '가슴 통증(협심증)이 요즘 심해졌다',
  'uncontrolled_arrhythmia': '맥박이 불규칙한데 약으로 잘 안 잡힌다',
  'worsening_heart_failure': '심장이 약해져서(심부전) 요즘 더 숨이 차다',
  'recent_myocardial_infarction': '최근 1년 안에 심근경색이 있었다',
  'recent_cardiac_surgery': '최근 1년 안에 심장 수술·시술을 받았다',
  'recent_stroke': '최근 1년 안에 뇌졸중(중풍)이 있었다',
  'severe_aortic_stenosis': '심장 판막이 많이 좁다는 말을 들었다',
  'syncope_history': '이유 없이 쓰러지거나 정신을 잃은 적이 있다',
};

class BasicInfoScreen extends StatefulWidget {
  final String phone, code;
  const BasicInfoScreen({super.key, required this.phone, required this.code});
  @override
  State<BasicInfoScreen> createState() => _BasicInfoScreenState();
}

class _BasicInfoScreenState extends State<BasicInfoScreen> {
  int _step = 0; // 0 이름, 1 태어난 해, 2 건강 정보 동의, 3 질환, 4 심박 약, 5 심박조율기
  final _name = TextEditingController();
  final _year = TextEditingController();
  final _ceiling = TextEditingController();
  final Set<String> _conditions = {};
  bool _betaBlocker = false;
  bool? _device;
  bool _busy = false;

  Map<String, dynamic> get _health => {
        'conditions': _conditions.toList(),
        'beta_blocker': _betaBlocker,
        'device': _device == true ? 'pacemaker' : null,
        'doctor_limits': {if (_ceiling.text.isNotEmpty) 'exercise_hr_ceiling': int.parse(_ceiling.text)},
      };

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _primary() => _run(() async {
        final app = AppScope.of(context);
        switch (_step) {
          case 0:
            if (_name.text.trim().isEmpty) return;
          case 1:
            final y = int.tryParse(_year.text);
            final thisYear = DateTime.now().year;
            if (y == null || y < 1900 || y > thisYear) throw ApiException(422, '태어난 해를 네 자리로 넣어 주세요. 예: 1952');
            // 대상은 65세 이상. 막지는 않지만(보호자·직원이 시험해 볼 수 있음) 잘못 넣은 건 아닌지 묻는다.
            if (thisYear - y < 60 && !await confirmDialog(context, '${thisYear - y}세로 넣으셨어요. 이 앱은 65세 이상 어르신을 위해 만들었어요. 맞게 넣으셨나요?')) {
              return;
            }
            await app.saveToken(await app.api.verifyOtp(widget.phone, widget.code, name: _name.text.trim(), birthYear: y));
            await app.loadMe();
          case 5:
            await app.saveHealth(_health);
            if (mounted) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParqScreen(health: _health)));
            }
            return;
        }
        setState(() => _step++);
      });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    switch (_step) {
      case 0:
        return SeniorScaffold(
          title: '성함을 알려 주세요',
          primaryLabel: '다음',
          onPrimary: _busy ? null : _primary,
          body: TextField(controller: _name, style: const TextStyle(fontSize: 32), decoration: const InputDecoration(labelText: '이름')),
        );
      case 1:
        return SeniorScaffold(
          title: '태어난 해',
          primaryLabel: '다음',
          onPrimary: _busy ? null : _primary,
          body: BigNumberField(label: '예: 1952', unit: '년', controller: _year, maxDigits: 4),
        );
      case 2:
        return SeniorScaffold(
          title: '건강 정보 사용 동의',
          primaryLabel: '동의해요',
          onPrimary: _busy
              ? null
              : () => _run(() async {
                    await app.api.consent('health', true);
                    setState(() => _step = 3);
                  }),
          secondaryLabel: '동의하지 않아요',
          onSecondary: () => showError(context, '동의하지 않으면 안전 확인을 할 수 없어서 운동 기능을 쓸 수 없어요. 언제든 다시 동의할 수 있어요.'),
          body: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('안전하게 운동을 돕기 위해 아래 정보를 받아요.'),
            SizedBox(height: 16),
            Text('· 앓고 계신 병과 드시는 약의 종류\n· 혈압, 맥박, 몸 상태 답변\n· 운동한 기록'),
            SizedBox(height: 16),
            Text('쓰는 곳: 운동해도 되는지 확인하고, 보호자에게 알릴 때만\n보관: 탈퇴하거나 지워 달라고 하실 때까지\n거부하셔도 되지만, 그러면 운동 기능은 쓸 수 없어요.'),
          ]),
        );
      case 3:
        return SeniorScaffold(
          title: '의사에게 들은 적이 있는 것',
          primaryLabel: _conditions.isEmpty ? '해당 없어요' : '다음',
          onPrimary: () => setState(() => _step = 4),
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('해당하는 것을 모두 눌러 주세요. 다시 누르면 지워져요.'),
            const SizedBox(height: 12),
            for (final e in gateConditions.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CheckTile(
                  label: e.value,
                  on: _conditions.contains(e.key),
                  onTap: () => setState(() => _conditions.contains(e.key) ? _conditions.remove(e.key) : _conditions.add(e.key)),
                ),
              ),
          ]),
        );
      case 4:
        return SeniorScaffold(
          title: '맥박을 느리게 하는 약',
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('혈압약 중에 맥박을 느리게 하는 약(베타차단제)을 드시나요?\n모르시면 약 봉투를 보호자와 함께 확인해 주세요.'),
            const SizedBox(height: 20),
            BigChoices(
              choices: const [('먹어요', true), ('안 먹어요', false), ('잘 모르겠어요', false)],
              onPick: (v) => setState(() {
                _betaBlocker = v as bool;
                _step = 5;
              }),
            ),
          ]),
        );
      default:
        return SeniorScaffold(
          title: '심장 박동기',
          primaryLabel: _device == null ? null : '다음',
          onPrimary: _busy ? null : _primary,
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('가슴에 심장 박동기나 제세동기를 넣으셨나요?'),
            const SizedBox(height: 20),
            BigChoices(choices: const [('넣었어요', true), ('아니요', false)], onPick: (v) => setState(() => _device = v as bool)),
            if (_device == true) ...[
              const Text('의사 선생님이 정해 준 운동 중 최고 맥박을 넣어 주세요. 모르면 비워 두고 다음에 보호자와 넣어도 돼요.'),
              const SizedBox(height: 12),
              BigNumberField(label: '최고 맥박', unit: '회/분', controller: _ceiling),
            ],
          ]),
        );
    }
  }
}

// ---------------- 3. 운동 전 문진 (PAR-Q+ 간소화, 자문단 검수 필요) ----------------
const parqQuestions = [
  '의사 선생님이 심장 때문에 운동을 조심하라고 한 적이 있나요?',
  '몸을 움직일 때 가슴이 아픈 적이 있나요?',
  '최근 한 달 사이, 가만히 있을 때도 가슴이 아픈 적이 있나요?',
  '지난 1년 사이 어지러워서 넘어지거나 정신을 잃은 적이 있나요?',
  '운동하면 뼈나 관절이 더 나빠진다는 말을 들은 적이 있나요?',
  '그 밖에 의사 선생님이 운동하지 말라고 한 이유가 있나요?',
  '최근 3개월 안에 입원하거나 수술을 받으셨나요?',
];

class ParqScreen extends StatefulWidget {
  final Map<String, dynamic> health;
  const ParqScreen({super.key, required this.health});
  @override
  State<ParqScreen> createState() => _ParqScreenState();
}

class _ParqScreenState extends State<ParqScreen> {
  int _i = 0;
  bool _risk = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => AppScope.of(context).say(parqQuestions[0]));
  }

  Future<void> _answer(bool yes) async {
    _risk |= yes;
    if (_i < parqQuestions.length - 1) {
      setState(() => _i++);
      AppScope.of(context).say(parqQuestions[_i]);
      return;
    }
    final app = AppScope.of(context);
    try {
      await app.saveHealth({...widget.health, 'parq_risk': _risk});
      await app.refreshRules();
      if (mounted) goHome(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SeniorScaffold(
      title: '몸 상태 질문 ${_i + 1} / ${parqQuestions.length}',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(parqQuestions[_i], style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 28),
        BigChoices(choices: const [('예', true), ('아니요', false)], onPick: (v) => _answer(v as bool)),
      ]),
    );
  }
}
