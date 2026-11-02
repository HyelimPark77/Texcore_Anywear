// 건강 앱(아이폰 '건강' / 안드로이드 Health Connect)에서 심박 기록을 읽는 부분. HealthHeartRateSource에 끼운다.
// 플러그인을 여기에만 두어 heart_rate.dart와 테스트는 플러그인 없이 돈다.
import 'package:health/health.dart';

import 'heart_rate.dart';

final _health = Health();
bool _configured = false;

Future<void> _setup() async {
  if (_configured) return;
  await _health.configure();
  _configured = true;
}

/// 심박 읽기 권한 요청. 아이폰은 사생활 보호 때문에 거절해도 true가 올 수 있다(그때는 기록이 비어서 온다).
Future<bool> authorizeHealth() async {
  await _setup();
  return _health.requestAuthorization([HealthDataType.HEART_RATE], permissions: [HealthDataAccess.READ]);
}

Future<List<HrSample>> readHeartRates(DateTime from, DateTime to) async {
  await _setup();
  final points = await _health.getHealthDataFromTypes(types: [HealthDataType.HEART_RATE], startTime: from, endTime: to);
  return [
    for (final p in points)
      if (p.value is NumericHealthValue) HrSample((p.value as NumericHealthValue).numericValue.round(), p.dateFrom),
  ];
}
