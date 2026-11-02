// 운동 전 점검에 쓸 혈압·맥박을 건강 앱 기록에서 고른다(계획서 7-3 센서 신뢰 등급).
//   팔에 감는 혈압계 앱이 쓴 기록(A) → 점검 칸을 미리 채운다(어르신은 확인만).
//   디즈먼트 워치(SMART-TIME PRO)가 쓴 혈압(C) → 채우지 않고 '참고용'으로만 보여 준다. 높으면 팔 혈압계로 재측정 유도.
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

  /// 워치 혈압(참고용).
  final BpReading? watch;
  const VitalsSnapshot({this.fresh, this.stale, this.watch});

  static const empty = VitalsSnapshot();
}

/// 운동 직전에 잰 값만 쓴다: 앉아서 5분 쉬고 잰 뒤 바로 점검하는 흐름(5-2).
const freshFor = Duration(minutes: 30);

/// 워치 혈압이 이 이상이면 팔 혈압계로 다시 재도록 강하게 안내한다(노랑 시작값, safety_rules.yaml precheck.bands).
const watchHighSystolic = 160, watchHighDiastolic = 100;

VitalsSnapshot pickVitals(List<BpReading> readings, DateTime now) {
  BpReading? latest(bool Function(BpReading) test) {
    final xs = readings.where(test).where((r) => !r.at.isAfter(now)).toList()..sort((a, b) => b.at.compareTo(a.at));
    return xs.isEmpty ? null : xs.first;
  }

  final arm = latest((r) => r.usableForCheck);
  final isFresh = arm != null && now.difference(arm.at) <= freshFor;
  return VitalsSnapshot(
    fresh: isFresh ? arm : null,
    stale: isFresh ? null : arm,
    watch: latest((r) => r.source == 'watch'),
  );
}

typedef BpReader = Future<List<BpReading>> Function(DateTime from, DateTime to);
