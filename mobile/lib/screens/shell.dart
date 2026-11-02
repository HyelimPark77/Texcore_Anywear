// 앱 뼈대: 아래 메뉴(오늘 · 기록 · 가족 · 내 정보). 메뉴는 아이콘과 글자를 함께 쓰고 늘 보인다
// (3장: 햄버거 메뉴·스와이프 금지. 아래 고정 메뉴는 누르기만 하면 되므로 허용).
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../ui/kit.dart';
import 'daily.dart';
import 'habit.dart';
import 'health.dart';

class HomeScreen extends StatefulWidget {
  final int initialTab;
  const HomeScreen({super.key, this.initialTab = 0});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _tab = widget.initialTab;

  static const _tabs = [
    (Icons.today_outlined, Icons.today, '오늘'),
    (Icons.insert_chart_outlined, Icons.insert_chart, '기록'),
    (Icons.family_restroom_outlined, Icons.family_restroom, '가족'),
    (Icons.person_outline, Icons.person, '내 정보'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        // 탭을 오가도 각 화면의 상태(불러온 기록 등)를 유지한다
        body: IndexedStack(index: _tab, children: const [TodayTab(), WeekScreen(), GuardianScreen(), MeTab()]),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final (icon, selected, label) in _tabs)
                NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
            ],
          ),
        ),
      );
}

// ---------------- 내 정보 ----------------
class MeTab extends StatelessWidget {
  const MeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = Palette.of(context);
    final name = app.name ?? '';
    final level = ((app.textScale - 1) / 0.25).round() + 1;
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return SeniorScaffold(
      title: '내 정보',
      showBack: false,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: p.brand,
                child: Text(name.isEmpty ? '나' : name.characters.first,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: p.onBrand)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isEmpty ? '이름 없음' : '$name님', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  Text('${app.age}세${app.goal != null ? ' · "${app.goal}"' : ''}', style: TextStyle(fontSize: 17, color: p.muted)),
                ]),
              ),
            ]),
          ),
        ),
        const SectionTitle('건강과 운동'),
        SettingRow(
          icon: Icons.medical_information,
          title: '내 건강 정보',
          subtitle: '병·약·심장 박동기·의사 확인',
          onTap: () => push(const HealthInfoScreen()),
        ),
        SettingRow(
          icon: Icons.notifications_active,
          title: '알림·목표',
          subtitle: '하고 싶은 일, 편한 시간, 워치 진동',
          onTap: () => push(const HabitSetupScreen()),
        ),
        const SectionTitle('보기와 듣기'),
        SettingRow(
          icon: Icons.format_size,
          title: '글자 크기 $level단계',
          subtitle: '누를 때마다 크게, 3단계 다음엔 처음으로',
          onTap: app.cycleTextScale,
        ),
        SettingRow(
          icon: app.voiceOn ? Icons.volume_up : Icons.volume_off,
          title: '안내 음성',
          subtitle: '운동 중 말로 알려 드려요',
          trailing: app.voiceOn ? '켜짐' : '꺼짐',
          onTap: app.toggleVoice,
        ),
      ]),
    );
  }
}
