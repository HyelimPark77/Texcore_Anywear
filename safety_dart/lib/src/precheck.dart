import 'dart:math' as math;

import 'codes.dart';
import 'rules.dart';

class DoctorLimits {
  final num? systolicMax, diastolicMax, restingHrMax, exerciseHrCeiling;
  const DoctorLimits({this.systolicMax, this.diastolicMax, this.restingHrMax, this.exerciseHrCeiling});

  factory DoctorLimits.fromJson(Map<String, dynamic>? j) => DoctorLimits(
        systolicMax: j?['systolic_max'],
        diastolicMax: j?['diastolic_max'],
        restingHrMax: j?['resting_hr_max'],
        exerciseHrCeiling: j?['exercise_hr_ceiling'],
      );

  num? byField(String f) => switch (f) {
        'systolic_max' => systolicMax,
        'diastolic_max' => diastolicMax,
        'resting_hr_max' => restingHrMax,
        _ => exerciseHrCeiling,
      };
}

class Profile {
  final int age;
  final Set<String> conditions;
  final bool parqRisk, doctorClearance, betaBlocker;
  final String? device;
  final DoctorLimits doctorLimits;

  const Profile({
    required this.age,
    this.conditions = const {},
    this.parqRisk = false,
    this.doctorClearance = false,
    this.device,
    this.betaBlocker = false,
    this.doctorLimits = const DoctorLimits(),
  });
}

class Vitals {
  final num? systolic, diastolic, restingHr;
  final String bpSource, hrSource;
  const Vitals({this.systolic, this.diastolic, this.restingHr, this.bpSource = 'manual', this.hrSource = 'manual'});
}

class Decision {
  final String kind;
  final String outcome;
  final List<String> reasons;
  final String ruleVersion, ruleSha256;
  final Map<String, dynamic> detail;
  const Decision(this.kind, this.outcome, this.reasons, this.ruleVersion, this.ruleSha256, [this.detail = const {}]);

  Light get light => lightOf(outcome);
}

const _metrics = ['systolic', 'diastolic', 'resting_hr'];
const _limitField = {'systolic': 'systolic_max', 'diastolic': 'diastolic_max', 'resting_hr': 'resting_hr_max'};

Decision _decision(RuleBundle r, String kind, String outcome, List<String> reasons, [Map<String, dynamic>? detail]) =>
    Decision(kind, outcome, reasons, r.version, r.sha256, detail ?? const {});

void _checkKnown(String name, Iterable<String> given, Iterable known) {
  final unknown = given.toSet().difference(known.map((e) => e.toString()).toSet());
  // 오타·미지원 항목이 조용히 "없음"으로 처리되면 위험하므로 입력 자체를 거부한다.
  if (unknown.isNotEmpty) throw ArgumentError('unknown $name: ${unknown.toList()..sort()}');
}

List<String> gateReasons(RuleBundle r, Profile p) {
  final g = r['hard_gate'];
  _checkKnown('gate condition', p.conditions, g['conditions_requiring_clearance']);
  final reasons = <String>[];
  if (!p.doctorClearance) {
    if (p.conditions.isNotEmpty) reasons.add(Code.gateConditionNeedsClearance);
    if (p.parqRisk && g['parq_risk_requires_clearance'] == true) reasons.add(Code.gateParqRisk);
  }
  if ((g['devices_requiring_doctor_hr_ceiling'] as List).contains(p.device) && p.doctorLimits.exerciseHrCeiling == null) {
    reasons.add(Code.gateDeviceNeedsHrCeiling);
  }
  return reasons;
}

Decision hardGate(RuleBundle r, Profile p) {
  final reasons = gateReasons(r, p);
  return _decision(r, 'hard_gate', reasons.isEmpty ? 'OPEN' : 'BLOCKED', reasons.isEmpty ? [Code.gateOpen] : reasons);
}

Map _band(List bands, num v) => bands.firstWhere(
    (b) => (b['lower'] == null || v >= b['lower']) && (b['upper'] == null || v < b['upper']));

Decision preCheck(RuleBundle r, Profile profile, Vitals vitals,
    {Iterable<String> symptoms = const [], Iterable<String> conditions = const []}) {
  final pre = r['precheck'];
  final sym = symptoms.toSet(), cond = conditions.toSet();
  _checkKnown('symptom', sym, [...pre['emergency_symptoms'], ...pre['red_symptoms'], ...pre['yellow_symptoms']]);
  _checkKnown('condition', cond, [...pre['red_conditions'], ...pre['yellow_conditions']]);

  // 1) 급성 위급 증상 → 즉시 119
  final emergency = sym.intersection((pre['emergency_symptoms'] as List).cast<String>().toSet()).toList()..sort();
  if (emergency.isNotEmpty) {
    return _decision(r, 'pre_check', 'EMERGENCY', [Code.preEmergencySymptom], {'symptoms': emergency});
  }
  // 2) 하드 게이트
  final blocked = gateReasons(r, profile);
  if (blocked.isNotEmpty) return _decision(r, 'pre_check', 'BLOCKED', blocked);

  final findings = <(Light, String)>[];
  bool any(Set<String> s, String key) => s.intersection((pre[key] as List).cast<String>().toSet()).isNotEmpty;
  // 3) 증상·컨디션
  if (any(sym, 'red_symptoms')) findings.add((Light.RED, Code.preRedSymptom));
  if (any(sym, 'yellow_symptoms')) findings.add((Light.YELLOW, Code.preYellowSymptom));
  if (any(cond, 'red_conditions')) findings.add((Light.RED, Code.preRedCondition));
  if (any(cond, 'yellow_conditions')) findings.add((Light.YELLOW, Code.preYellowCondition));

  // 4) 측정 출처 등급
  final bpGrade = r['source_grades']['blood_pressure'][vitals.bpSource];
  final hrGrade = r['source_grades']['heart_rate'][vitals.hrSource];
  if (bpGrade == null || hrGrade == null) {
    throw ArgumentError('unknown measurement source: bp=${vitals.bpSource} hr=${vitals.hrSource}');
  }
  final bpUsable = bpGrade == 'A' || bpGrade == 'B';
  if (!bpUsable) findings.add((Light.REMEASURE, Code.preBpSourceNotAllowed));

  // 5) 수치 밴드 + 의사 개인 한도
  final values = {'systolic': vitals.systolic, 'diastolic': vitals.diastolic, 'resting_hr': vitals.restingHr};
  final plausible = <String, num>{};
  for (final metric in _metrics) {
    if (metric != 'resting_hr' && !bpUsable) continue;
    final v = values[metric];
    if (v == null) {
      findings.add((Light.REMEASURE, Code.preMissingValue));
      continue;
    }
    final p = r['plausibility'][metric];
    if (!(p['min'] <= v && v <= p['max'])) {
      findings.add((Light.REMEASURE, Code.preImplausibleValue));
      continue;
    }
    plausible[metric] = v;
    final band = _band(pre['bands'][metric] as List, v);
    final light = lightOf(band['light']);
    final grade = metric == 'resting_hr' ? hrGrade : bpGrade;
    if (grade == 'B' && light == Light.GREEN) {
      // B 등급(워치)은 좋게 나와도 안전 근거로 쓰지 않는다 → low_grade_green(초안: 노랑, 가볍게).
      final alt = r['low_grade_green'][metric == 'resting_hr' ? 'heart_rate' : 'blood_pressure'];
      findings.add((lightOf(alt['light']), alt['code'] as String));
    } else {
      findings.add((light, band['code'] as String));
    }
    final field = _limitField[metric]!;
    final limit = profile.doctorLimits.byField(field);
    final def = pre['doctor_limit_defaults'][field] as num;
    if (limit != null) {
      if (limit > def) {
        findings.add((Light.GREEN, Code.doctorLimitLooserIgnored));
      } else if (v >= limit) {
        findings.add((Light.RED, Code.preOverDoctorLimit));
      }
    }
  }
  if (r['plausibility']['require_systolic_above_diastolic'] == true &&
      plausible.containsKey('systolic') &&
      plausible.containsKey('diastolic') &&
      plausible['systolic']! <= plausible['diastolic']!) {
    findings.add((Light.REMEASURE, Code.preImplausibleValue));
  }

  final outcome = worst(findings.map((f) => f.$1));
  final reasons = <String>[];
  for (final f in findings) {
    if (!reasons.contains(f.$2)) reasons.add(f.$2);
  }
  return _decision(r, 'pre_check', outcome.name, reasons);
}

/// 신호등별 오늘 허용 범위.
Map<String, dynamic> allowance(RuleBundle r, Light light, int plannedMinutes) {
  if (light != Light.GREEN && light != Light.YELLOW) return {'allowed': false, 'max_minutes': 0};
  final a = r['allowance'][light.name];
  final minutes = math.max(a['min_minutes'] as int, (plannedMinutes * (a['minutes_factor'] as num)).floor());
  return {
    'allowed': true,
    'max_minutes': math.min(plannedMinutes, minutes),
    'intensity': a['intensity'],
    'hr_ceiling_pct_cap': a['hr_ceiling_pct_cap'],
  };
}

Decision postCheck(RuleBundle r, num restingHr, num hrAfterRecovery) {
  final slow = hrAfterRecovery - restingHr >= r['post']['elevated_delta_bpm'];
  return _decision(r, 'post_check', slow ? 'SLOW_RECOVERY' : 'RECOVERED',
      [slow ? Code.postSlowRecovery : Code.postRecovered], {'next_intensity_down': slow});
}
