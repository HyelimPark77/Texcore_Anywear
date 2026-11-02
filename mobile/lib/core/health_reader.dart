// 건강 앱(아이폰 '건강' / 안드로이드 Health Connect)에서 심박·혈압 기록을 읽는 부분.
// HealthHeartRateSource(홈 화면 최근 심박)와 운동 전 점검(혈압 자동 채우기)에 끼운다.
// 플러그인을 여기에만 두어 heart_rate.dart·vitals.dart와 테스트는 플러그인 없이 돈다.
import 'package:health/health.dart';

import 'heart_rate.dart';
import 'vitals.dart';

final _health = Health();
bool _configured = false;
const _types = [
  HealthDataType.HEART_RATE,
  HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
  HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
  HealthDataType.STEPS,
];

Future<void> _setup() async {
  if (_configured) return;
  await _health.configure();
  _configured = true;
}

/// 심박·혈압·걸음 읽기 권한 요청(한 번에). 아이폰은 사생활 보호 때문에 거절해도 true가 올 수 있다(그때는 기록이 비어서 온다).
Future<bool> authorizeHealth() async {
  await _setup();
  return _health.requestAuthorization(_types, permissions: [for (final _ in _types) HealthDataAccess.READ]);
}

int? _num(HealthDataPoint p) => p.value is NumericHealthValue ? (p.value as NumericHealthValue).numericValue.round() : null;

Future<List<HrSample>> readHeartRates(DateTime from, DateTime to) async {
  await _setup();
  final points = await _health.getHealthDataFromTypes(types: [HealthDataType.HEART_RATE], startTime: from, endTime: to);
  return [
    for (final p in points)
      if (_num(p) != null) HrSample(_num(p)!, p.dateFrom),
  ];
}

/// 혈압 기록을 수축기·이완기 한 쌍으로 묶고, 같은 앱이 3분 안에 남긴 맥박을 붙인다.
Future<List<BpReading>> readBloodPressure(DateTime from, DateTime to) async {
  await authorizeHealth();
  final points = await _health.getHealthDataFromTypes(types: _types, startTime: from, endTime: to);
  final dia = points.where((p) => p.type == HealthDataType.BLOOD_PRESSURE_DIASTOLIC).toList();
  final hr = points.where((p) => p.type == HealthDataType.HEART_RATE).toList();
  bool near(HealthDataPoint a, HealthDataPoint b, Duration d) =>
      a.sourceId == b.sourceId && a.dateFrom.difference(b.dateFrom).abs() <= d;
  final out = <BpReading>[];
  for (final s in points.where((p) => p.type == HealthDataType.BLOOD_PRESSURE_SYSTOLIC)) {
    final d = dia.where((p) => near(p, s, const Duration(minutes: 1))).firstOrNull;
    if (d == null || _num(s) == null || _num(d) == null) continue;
    final pulse = hr.where((p) => near(p, s, const Duration(minutes: 3))).firstOrNull;
    out.add(BpReading(_num(s)!, _num(d)!, s.dateFrom,
        source: classifySource(s.sourceId, s.sourceName), sourceName: s.sourceName, pulse: pulse == null ? null : _num(pulse)));
  }
  return out;
}

/// [from, to) 걸음 수 합계(워치·폰 중복은 건강 앱이 정리해 준다). 기록이 없으면 null.
Future<int?> readSteps(DateTime from, DateTime to) async {
  await authorizeHealth();
  return _health.getTotalStepsInInterval(from, to);
}
