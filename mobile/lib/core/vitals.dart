// 운동 전 점검에 쓸 혈압·맥박을 건강 앱 기록에서 고른다(계획서 7-3 센서 신뢰 등급).
//   팔에 감는 혈압계 앱이 쓴 기록(A) → 점검 칸을 미리 채운다(어르신은 확인만).
//   그게 없으면 디즈먼트 워치(SMART-TIME PRO) 혈압·맥박(B)으로 채운다. 안전 엔진이 B 등급 정상값을
//   '노랑(가볍게)'으로 판정한다(safety_rules.yaml low_grade_green, 발주사 결정 2026-11-02).
//   출처를 알 수 없는 기록 → 안전 쪽으로 채우지 않는다.
// 출처 이름(manual / ble_upper_arm / watch)은 안전 규칙 source_grades 와 같다.

/// 상완형(팔에 감는) 혈압계 앱으로 확인된 것만. 늘릴 때는 그 앱이 손목형 기기 기록도 쓰는지 확인한다.
const upperArmApps = ['omron', 'withings', 'ihealth', 'beurer', 'qardio', 'microlife'];

/// 디즈먼트 워치 전용 앱 SMART-TIME PRO(com.sma.smartv3 계열).
const watchApps = ['com.sma.', 'smart-time', 'smart time', 'smartv3'];

/// 건강 앱에 사람이 직접 넣은 기록(아이폰 '건강' 앱).
const manualApps = ['com.apple.health'];

/// 'ble_upper_arm' | 'manual' | 'watch' | 'unknown'
String classifySource(String sourceId, String sourceName) {
  final s = '${sourceId.toLowerCase()} ${sourceName.toLowerCase()}';
  if (watchApps.any(s.contains)) return 'watch';
  if (upperArmApps.any(s.contains)) return 'ble_upper_arm';
  if (manualApps.any((m) => sourceId.toLowerCase() == m)) return 'manual';
  return 'unknown';
}

class BpReading {
  final int systolic, diastolic;
  final int? pulse;
  final DateTime at;
  final String source; // classifySource 결과
  final String sourceName;
  const BpReading(this.systolic, this.diastolic, this.at, {required this.source, required this.sourceName, this.pulse});

  bool get usableForCheck => source == 'ble_upper_arm' || source == 'manual';
}

class VitalsSnapshot {
  /// 점검 칸을 채울 팔 혈압계 기록(최근 [freshFor] 안). 없으면 null.
  final BpReading? fresh;

  /// 오래돼서 채우지 않는 마지막 팔 혈압계 기록(안내용).
  final BpReading? stale;

  /// 마지막 워치 혈압. [watchFreshFor] 안이고 [fresh]가 없으면 칸을 채운다.
  final BpReading? watch;

  /// 워치 맥박(최근 [freshFor] 안). 맥박 칸이 비면 채운다.
  final int? watchPulse;
  final DateTime? watchPulseAt;
  final DateTime now;
  const VitalsSnapshot({this.fresh, this.stale, this.watch, this.watchPulse, this.watchPulseAt, required this.now});

  static final empty = VitalsSnapshot(now: DateTime.fromMillisecondsSinceEpoch(0));

  /// 칸을 채울 혈압: 팔 혈압계 우선, 없으면 최근 워치 혈압.
  BpReading? get fill => fresh ?? (watch != null && now.difference(watch!.at) <= watchFreshFor ? watch : null);
}

/// 운동 직전에 잰 값만 쓴다: 앉아서 5분 쉬고 잰 뒤 바로 점검하는 흐름(5-2).
const freshFor = Duration(minutes: 30);

/// 워치는 수시로 재므로 조금 더 넓게 본다(오늘 몸 상태로 볼 수 있는 범위, 초안).
const watchFreshFor = Duration(hours: 3);

VitalsSnapshot pickVitals(List<BpReading> readings, DateTime now, {List<(int bpm, DateTime at)> pulses = const []}) {
  BpReading? latest(bool Function(BpReading) test) {
    final xs = readings.where(test).where((r) => !r.at.isAfter(now)).toList()..sort((a, b) => b.at.compareTo(a.at));
    return xs.isEmpty ? null : xs.first;
  }

  final arm = latest((r) => r.usableForCheck);
  final isFresh = arm != null && now.difference(arm.at) <= freshFor;
  final p = pulses.where((x) => !x.$2.isAfter(now) && now.difference(x.$2) <= freshFor).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  return VitalsSnapshot(
    fresh: isFresh ? arm : null,
    stale: isFresh ? null : arm,
    watch: latest((r) => r.source == 'watch'),
    watchPulse: p.isEmpty ? null : p.first.$1,
    watchPulseAt: p.isEmpty ? null : p.first.$2,
    now: now,
  );
}

typedef BpReader = Future<List<BpReading>> Function(DateTime from, DateTime to);
