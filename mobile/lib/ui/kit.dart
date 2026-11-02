import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
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

/// 앱 색. 주 색은 짙은 청록 하나, 상태색(신호등)은 아이콘·글자와 함께만 쓴다(색만으로 구분 금지).
class Palette {
  final bool light;
  const Palette(this.light);
  factory Palette.of(BuildContext context) => Palette(Theme.of(context).brightness == Brightness.light);

  Color get brand => light ? const Color(0xFF0F6E56) : const Color(0xFF5DCAA5);
  Color get onBrand => light ? Colors.white : const Color(0xFF04342C);
  Color get brandTint => light ? const Color(0xFFE1F5EE) : const Color(0xFF0E2E25);
  Color get onBrandTint => light ? const Color(0xFF085041) : const Color(0xFF9FE1CB);
  Color get danger => light ? const Color(0xFFA32D2D) : const Color(0xFFF09595);
  Color get onDanger => light ? Colors.white : const Color(0xFF501313);
  Color get dangerTint => light ? const Color(0xFFFCEBEB) : const Color(0xFF3A1515);
  Color get onDangerTint => light ? const Color(0xFF791F1F) : const Color(0xFFF7C1C1);
  Color get warnTint => light ? const Color(0xFFFAEEDA) : const Color(0xFF3A2A0E);
  Color get onWarnTint => light ? const Color(0xFF633806) : const Color(0xFFFAC775);
  Color get muted => light ? const Color(0xFF4A5565) : const Color(0xFFB4BCC8);
  Color get well => light ? const Color(0xFFF1F3F6) : const Color(0xFF1C2532);

  /// 홈 머리 카드 그라데이션(짙은 청록 → 청록). 위 글자는 흰색.
  // 흰 글자 명암비 4.5:1 이상이 나오도록 밝은 쪽도 짙게(접근성 검사)
  List<Color> get hero => light ? const [Color(0xFF063D33), Color(0xFF0F6E56)] : const [Color(0xFF04342C), Color(0xFF0B5A47)];

  /// 수치 칸 아이콘 원 색(걸음·심박·혈압). 색만으로 뜻을 전하지 않고 글자와 함께 쓴다.
  Color get steps => light ? const Color(0xFF185FA5) : const Color(0xFF85B7EB);
  Color get heart => light ? const Color(0xFFA32D2D) : const Color(0xFFF09595);
  Color get pressure => light ? const Color(0xFF534AB7) : const Color(0xFFAFA9EC);
}

ThemeData seniorTheme(Brightness b) {
  final light = b == Brightness.light;
  final care = Palette(light).brand;
  final canvas = light ? const Color(0xFFF3F6F5) : const Color(0xFF0B1017); // 살짝 청록빛 도는 바탕
  final surface = light ? Colors.white : const Color(0xFF141B25);
  final line = light ? const Color(0xFFE2E7EE) : const Color(0xFF263142);
  final scheme = ColorScheme.fromSeed(
    seedColor: care,
    brightness: b,
    primary: care,
    onPrimary: Palette(light).onBrand,
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
    // 카드는 흰 바탕 + 아주 옅은 그림자로 떠 보이게(다크 모드는 그림자 대신 테두리)
    cardTheme: CardThemeData(
      color: surface,
      elevation: light ? 2 : 0,
      shadowColor: const Color(0x260F2A24),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22), side: BorderSide(color: light ? const Color(0xFFE8EEEC) : line)),
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
    navigationBarTheme: NavigationBarThemeData(
      height: 84,
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Palette(light).brandTint,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 17,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Palette(light).brand : scheme.onSurface,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 30, color: s.contains(WidgetState.selected) ? Palette(light).brand : scheme.onSurface)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(56, 56), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      // 칸 이름은 늘 위 테두리에 두고, 큰 글자와 겹치지 않게 위쪽 여백을 넉넉히(모든 입력 칸 공통)
      floatingLabelBehavior: FloatingLabelBehavior.always,
      floatingLabelStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: care),
      contentPadding: const EdgeInsets.fromLTRB(20, 30, 20, 16),
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

  /// 여러 단계로 된 흐름(가입·점검)에서 지금 어디쯤인지. 0~1.
  final double? progress;

  /// 보조 버튼을 주 버튼 옆에 나란히(운동 중 '잠깐 쉬기 | 그만').
  final bool sideBySide;

  /// 위 제목 줄을 숨긴다(홈처럼 머리 카드가 제목을 대신할 때).
  final bool appBar;

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
    this.progress,
    this.sideBySide = false,
    this.appBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    return Scaffold(
      appBar: !appBar ? null : AppBar(
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
        bottom: progress == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sizes.gutter, 0, Sizes.gutter, 4),
                  child: Semantics(
                    label: '진행 ${(progress! * 100).round()}%',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                          value: progress, minHeight: 6, color: Palette.of(context).brand, backgroundColor: Palette.of(context).well),
                    ),
                  ),
                ),
              ),
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
                  child: sideBySide && secondaryLabel != null && primaryLabel != null
                      ? Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onSecondary,
                              style: OutlinedButton.styleFrom(alignment: Alignment.center),
                              child: Text(secondaryLabel!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _primary(context)),
                        ])
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          if (secondaryLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: OutlinedButton(
                                onPressed: onSecondary,
                                style: OutlinedButton.styleFrom(alignment: Alignment.center),
                                child: Text(secondaryLabel!),
                              ),
                            ),
                          if (primaryLabel != null) _primary(context),
                        ]),
                ),
              ),
            ),
    );
  }
}

extension on SeniorScaffold {
  Widget _primary(BuildContext context) => FilledButton(
        onPressed: onPrimary,
        style: primaryColor == null ? null : FilledButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
        child: Text(primaryLabel!, textAlign: TextAlign.center),
      );
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
            suffixStyle: TextStyle(fontSize: 20, color: Palette.of(context).muted),
          ),
        ),
      );
}

/// 신호등: 색 + 아이콘 + 글자를 함께 보여 준다(색만으로 구분하지 않음).
class LightBadge extends StatelessWidget {
  final String outcome;
  const LightBadge({super.key, required this.outcome});

  // 신호등 색 + 아이콘 + 글자(색만으로 구분하지 않음). 글자는 같은 계열의 짙은 색으로 명암비를 지킨다.
  static const _look = {
    'GREEN': ('brand', Icons.check_circle, '초록 · 평소대로 해요'),
    'YELLOW': ('warn', Icons.error, '노랑 · 오늘은 가볍게'),
    'RED': ('danger', Icons.pan_tool, '빨강 · 오늘은 쉬어요'),
    'REMEASURE': ('well', Icons.refresh, '다시 재 주세요'),
    'BLOCKED': ('danger', Icons.local_hospital, '의사 선생님 확인이 필요해요'),
    'EMERGENCY': ('solid', Icons.emergency, '지금 바로 도움을 받으세요'),
  };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (tone, icon, label) = _look[outcome] ?? _look['REMEASURE']!;
    final (bg, fg) = switch (tone) {
      'brand' => (p.brandTint, p.onBrandTint),
      'warn' => (p.warnTint, p.onWarnTint),
      'danger' => (p.dangerTint, p.onDangerTint),
      'solid' => (p.danger, p.onDanger),
      _ => (p.well, Theme.of(context).colorScheme.onSurface),
    };
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(26)),
        child: Row(children: [
          Icon(icon, size: 56, color: fg),
          const SizedBox(width: 16),
          Expanded(child: Text(label, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: fg))),
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

/// 한 줄 안내: 아이콘 + 글자.
class NoteRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool strong;
  final Color? color;
  const NoteRow(this.icon, this.text, {super.key, this.strong = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 28, color: color ?? Palette.of(context).muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 18, color: color ?? Palette.of(context).muted, fontWeight: strong ? FontWeight.w800 : null)),
          ),
        ]),
      );
}

/// 색을 입힌 카드(오늘의 운동, 병원 확인 등). [tone]: brand | danger | warn
class ToneCard extends StatelessWidget {
  final String tone;
  final IconData icon;
  final String? label;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const ToneCard({super.key, this.tone = 'brand', required this.icon, this.label, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (bg, fg) = switch (tone) {
      'danger' => (p.dangerTint, p.onDangerTint),
      'warn' => (p.warnTint, p.onWarnTint),
      _ => (p.brandTint, p.onBrandTint),
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null) Text(label!, style: TextStyle(fontSize: 17, color: fg, fontWeight: FontWeight.w600)),
        if (label != null) const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(icon, size: 40, color: fg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: fg, height: 1.3)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 18, color: fg, height: 1.4)),
            ]),
          ),
          ?trailing,
        ]),
      ]),
    );
  }
}

/// 큰 숫자 칸(혈압·맥박 등).
class StatTile extends StatelessWidget {
  final String label, value;
  final String? unit;
  final int flex;
  const StatTile({super.key, required this.label, required this.value, this.unit, this.flex = 1});

  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Semantics(
          label: '$label $value ${unit ?? ''}',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            decoration: BoxDecoration(color: Palette.of(context).well, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              Text(label, style: TextStyle(fontSize: 17, color: Palette.of(context).muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: value, style: const TextStyle(fontSize: Sizes.number, fontWeight: FontWeight.w800)),
                  if (unit != null) TextSpan(text: unit, style: TextStyle(fontSize: 20, color: Palette.of(context).muted)),
                ])),
              ),
            ]),
          ),
        ),
      );
}

/// 이번 주 도장 칸: 채운 칸은 체크, 다음 칸은 점선(색 + 아이콘).
class StampRow extends StatelessWidget {
  final int filled, slots;
  const StampRow({super.key, required this.filled, this.slots = 5});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final n = filled > slots ? filled : slots;
    return Semantics(
      label: '이번 주 도장 $filled개',
      excludeSemantics: true,
      child: Row(children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: i < filled ? p.brand : p.well,
                borderRadius: BorderRadius.circular(12),
                border: i == filled ? Border.all(color: p.brand, width: 2) : null,
              ),
              child: i < filled ? Icon(Icons.check, size: 28, color: p.onBrand) : null,
            ),
          ),
        ],
      ]),
    );
  }
}

/// 여러 개 고를 수 있는 큰 칩(증상 등). 고르면 색 + 체크 아이콘.
class ChoiceChipTile extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const ChoiceChipTile({super.key, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? p.brandTint : Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: on ? p.brand : Theme.of(context).dividerColor, width: on ? 2.5 : 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(on ? Icons.check_circle : Icons.circle_outlined, size: 26, color: on ? p.brand : p.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: TextStyle(fontSize: 19, fontWeight: on ? FontWeight.w800 : FontWeight.w500, color: on ? p.onBrandTint : null))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// 두 칸씩 놓는 격자.
class TwoColumn extends StatelessWidget {
  final List<Widget> children;
  const TwoColumn({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < children.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: children[i]),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
              ]),
            ),
          ),
      ]);
}

/// 단계 막대(몸 풀기·본 운동·마무리 등). [done]까지 채움, [current]는 반쯤.
class SegmentBar extends StatelessWidget {
  final List<int> weights;
  final int current;
  final double currentFraction;
  const SegmentBar({super.key, required this.weights, required this.current, this.currentFraction = 0});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ExcludeSemantics(
      child: Row(children: [
        for (var i = 0; i < weights.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            flex: weights[i] < 1 ? 1 : weights[i],
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: i < current ? 1 : (i == current ? currentFraction.clamp(0, 1) : 0),
                color: p.brand,
                backgroundColor: p.well,
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// 섹션 제목.
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Semantics(header: true, child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
      );
}

/// 진행 고리(이번 주 도장 등). 가운데에 큰 글자.
class ProgressRing extends StatelessWidget {
  final double value;
  final String center, caption;
  final Color color, track;
  final double size;
  const ProgressRing({super.key, required this.value, required this.center, required this.caption, required this.color, required this.track, this.size = 116});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$caption $center',
        excludeSemantics: true,
        child: SizedBox(
          width: size,
          height: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => CustomPaint(
              painter: _RingPainter(v, color, track),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color, height: 1.1)),
                  Text(caption, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color, track;
  _RingPainter(this.v, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, 6.2832, false, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = stroke);
    canvas.drawArc(r, -1.5708, 6.2832 * v, false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

/// 오늘 내 몸 수치 칸: 색 원 아이콘 + 큰 값 + 이름.
class MetricTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  final String? unit;
  const MetricTile({super.key, required this.icon, required this.color, required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          label: '$label $value ${unit ?? ''}',
          excludeSemantics: true,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Icon(icon, size: 24, color: color),
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                    if (unit != null) TextSpan(text: ' $unit', style: TextStyle(fontSize: 15, color: Palette.of(context).muted)),
                  ])),
                ),
                Text(label, style: TextStyle(fontSize: 16, color: Palette.of(context).muted)),
              ]),
            ),
          ),
        ),
      );
}

/// 설정 목록 한 줄: 색 원 아이콘 + 이름 + 설명 + 오른쪽 값/화살표.
class SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle, trailing;
  final VoidCallback onTap;
  const SettingRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: p.brandTint, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, size: 26, color: p.brand),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 16, color: p.muted)),
                ]),
              ),
              if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 18, color: p.brand, fontWeight: FontWeight.w800)),
              Icon(Icons.chevron_right, size: 30, color: p.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

