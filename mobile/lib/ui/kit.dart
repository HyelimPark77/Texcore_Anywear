import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';

/// 고령자 UX 기준(3장): 본문 18sp 이상, 중요 숫자 40sp 이상, 터치 56dp 이상,
/// 한 화면 한 결정(주 버튼 1개, 하단 고정), 되돌리기 항상 보임, 색만으로 상태 구분 금지.
class Sizes {
  static const body = 20.0;
  static const title = 26.0;
  static const number = 44.0;
  static const button = 64.0; // 최소 터치 높이(56dp보다 크게)
  static const gutter = 20.0;
}

ThemeData seniorTheme(Brightness b) {
  final light = b == Brightness.light;
  // 시연 페이지와 같은 색: 차가운 오프화이트 바탕, 짙은 초록, 흰 카드
  const care = Color(0xFF0B7A55);
  final canvas = light ? const Color(0xFFF2F4F7) : const Color(0xFF0B1017);
  final surface = light ? Colors.white : const Color(0xFF141B25);
  final line = light ? const Color(0xFFE2E7EE) : const Color(0xFF263142);
  final scheme = ColorScheme.fromSeed(
    seedColor: care,
    brightness: b,
    primary: light ? care : const Color(0xFF34C48B),
    onPrimary: light ? Colors.white : const Color(0xFF04140D),
    surface: canvas,
    // 본문 명암비 4.5:1 이상이 나오도록 글자색을 거의 검정/흰색으로 둔다.
    onSurface: light ? const Color(0xFF0E1726) : const Color(0xFFEEF2F7),
  );
  final text = TextTheme(
    bodyLarge: const TextStyle(fontSize: Sizes.body, height: 1.5),
    bodyMedium: const TextStyle(fontSize: Sizes.body, height: 1.5),
    titleLarge: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.6),
    headlineMedium: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
    labelLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
  ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  final radius = BorderRadius.circular(18);
  return ThemeData(
    colorScheme: scheme,
    textTheme: text,
    useMaterial3: true,
    scaffoldBackgroundColor: canvas,
    appBarTheme: AppBarTheme(backgroundColor: canvas, surfaceTintColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(Sizes.button),
        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: radius),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(Sizes.button),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        backgroundColor: surface,
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: line, width: 2),
        shape: RoundedRectangleBorder(borderRadius: radius),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(56, 56), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: line, width: 2)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 3)),
    ),
  );
}

/// 모든 화면의 뼈대: 제목, 내용, 하단 고정 주 버튼 1개(+ 필요하면 보조 버튼 1개).
class SeniorScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final Color? primaryColor;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool showBack;

  const SeniorScaffold({
    super.key,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.primaryColor,
    this.secondaryLabel,
    this.onSecondary,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 72,
        leadingWidth: canPop ? 120 : 0,
        // 되돌리기는 아이콘만이 아니라 글자로 항상 보인다.
        leading: canPop
            ? TextButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, size: 28),
                label: const Text('뒤로'),
              )
            : null,
        title: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
      ),
      // 빈 곳을 누르면 키보드를 내린다(아이폰 숫자 키패드에는 '완료' 키가 없다).
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true, // 화면 읽기에는 '이름 없는 버튼'으로 잡히지 않게
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Sizes.gutter),
            child: DefaultTextStyle.merge(style: const TextStyle(fontSize: Sizes.body), child: body),
          ),
        ),
      ),
      // 하단 주 버튼은 키보드 위로 올라온다(bottomNavigationBar는 키보드에 가려지므로 키보드 높이만큼 띄움).
      bottomNavigationBar: (primaryLabel == null && secondaryLabel == null)
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sizes.gutter, 8, Sizes.gutter, Sizes.gutter),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (secondaryLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
                      ),
                    if (primaryLabel != null)
                      FilledButton(
                        onPressed: onPrimary,
                        style: primaryColor == null ? null : FilledButton.styleFrom(backgroundColor: primaryColor),
                        child: Text(primaryLabel!),
                      ),
                  ]),
                ),
              ),
            ),
    );
  }
}

/// 큰 선택지 목록(질문 화면). 하나를 누르면 바로 다음으로 간다.
class BigChoices extends StatelessWidget {
  final List<(String label, Object value)> choices;
  final ValueChanged<Object> onPick;
  const BigChoices({super.key, required this.choices, required this.onPick});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, value) in choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: OutlinedButton(onPressed: () => onPick(value), child: Text(label, textAlign: TextAlign.center)),
            ),
        ],
      );
}

/// 큰 숫자 입력(혈압·맥박). 숫자 자판만, 40sp 이상.
class BigNumberField extends StatelessWidget {
  final String label;
  final String unit;
  final TextEditingController controller;
  final int maxDigits; // 혈압·맥박 3, 태어난 해 4, 인증번호 6, 휴대폰 11
  const BigNumberField({super.key, required this.label, required this.unit, required this.controller, this.maxDigits = 3});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(maxDigits)],
          style: const TextStyle(fontSize: Sizes.number, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontSize: 22),
            suffixText: unit,
            suffixStyle: const TextStyle(fontSize: 22),
          ),
        ),
      );
}

/// 신호등: 색 + 아이콘 + 글자를 함께 보여 준다(색만으로 구분하지 않음).
class LightBadge extends StatelessWidget {
  final String outcome;
  const LightBadge({super.key, required this.outcome});

  static const _look = {
    'GREEN': (Color(0xFF2E7D32), Icons.check_circle, '초록 · 평소대로 해요'),
    'YELLOW': (Color(0xFFF9A825), Icons.error, '노랑 · 오늘은 가볍게'),
    'RED': (Color(0xFFC62828), Icons.pan_tool, '빨강 · 오늘은 쉬어요'),
    'REMEASURE': (Color(0xFF546E7A), Icons.refresh, '다시 재 주세요'),
    'BLOCKED': (Color(0xFF546E7A), Icons.local_hospital, '의사 선생님 확인이 필요해요'),
    'EMERGENCY': (Color(0xFFB71C1C), Icons.emergency, '지금 바로 도움을 받으세요'),
  };

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = _look[outcome] ?? _look['REMEASURE']!;
    final onColor = outcome == 'YELLOW' ? Colors.black : Colors.white;
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(26)),
        child: Row(children: [
          Icon(icon, size: 56, color: onColor),
          const SizedBox(width: 16),
          Expanded(child: Text(label, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: onColor))),
        ]),
      ),
    );
  }
}

Future<void> showError(BuildContext context, Object e) => showDialog(
      context: context,
      builder: (c) => AlertDialog(
        content: Text('$e', style: const TextStyle(fontSize: Sizes.body)),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('확인'))],
      ),
    );

/// 정말 맞는지 한 번 더 묻는다(위험하거나 실수하기 쉬운 입력에만, 3장 '확인 팝업은 꼭 필요할 때만').
Future<bool> confirmDialog(BuildContext context, String text, {String yes = '맞아요', String no = '다시 넣을게요'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(text, style: const TextStyle(fontSize: Sizes.body)),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
        ],
      ),
    ) ??
    false;

/// 화면이 처음 뜰 때 한 번만 읽어 준다(다시 그려져도 반복하지 않음).
class SpeakOnce extends StatefulWidget {
  final String? text;
  final Widget child;
  const SpeakOnce({super.key, required this.text, required this.child});
  @override
  State<SpeakOnce> createState() => _SpeakOnceState();
}

class _SpeakOnceState extends State<SpeakOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.text != null) AppScope.of(context).say(widget.text!);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 눌러서 켜고 끄는 큰 체크 칸(여러 개 고르기).
class CheckTile extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const CheckTile({super.key, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        selected: on,
        button: true,
        child: OutlinedButton.icon(
          onPressed: onTap,
          style: on ? OutlinedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer) : null,
          icon: Icon(on ? Icons.check_box : Icons.check_box_outline_blank, size: 32),
          label: Align(alignment: Alignment.centerLeft, child: Text(label)),
        ),
      );
}
