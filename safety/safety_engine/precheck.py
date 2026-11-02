"""운동 전 판정: 하드 게이트(5-1), 신호등(5-2), 허용 범위, 운동 후 회복(5-3).

모든 함수는 순수 함수다. 같은 규칙 번들 + 같은 입력 → 항상 같은 결과.
"""
import math
from dataclasses import asdict

from .codes import Code, Light, worst
from .types import Decision, Profile, Vitals

_METRICS = ("systolic", "diastolic", "resting_hr")
_LIMIT_FIELD = {"systolic": "systolic_max", "diastolic": "diastolic_max", "resting_hr": "resting_hr_max"}


def _decision(rules, kind, outcome, reasons, inputs, detail=None):
    return Decision(kind=kind, outcome=str(outcome.value if isinstance(outcome, Light) else outcome),
                    reasons=tuple(reasons), rule_version=rules.version, rule_sha256=rules.sha256,
                    inputs=inputs, detail=detail or {})


def _check_known(name, given, known):
    unknown = set(given) - set(known)
    if unknown:
        # 오타·미지원 항목이 조용히 "없음"으로 처리되면 위험하므로 입력 자체를 거부한다.
        raise ValueError(f"unknown {name}: {sorted(unknown)}")


def gate_reasons(rules, profile: Profile):
    g = rules["hard_gate"]
    _check_known("gate condition", profile.conditions, g["conditions_requiring_clearance"])
    reasons = []
    if not profile.doctor_clearance:
        if profile.conditions:
            reasons.append(Code.GATE_CONDITION_NEEDS_CLEARANCE)
        if profile.parq_risk and g["parq_risk_requires_clearance"]:
            reasons.append(Code.GATE_PARQ_RISK)
    # 확인서가 있어도 심박조율기·ICD는 의사가 정한 심박 상한이 있어야 한다.
    if profile.device in g["devices_requiring_doctor_hr_ceiling"] and profile.doctor_limits.exercise_hr_ceiling is None:
        reasons.append(Code.GATE_DEVICE_NEEDS_HR_CEILING)
    return reasons


def hard_gate(rules, profile: Profile) -> Decision:
    reasons = gate_reasons(rules, profile)
    outcome = "BLOCKED" if reasons else "OPEN"
    return _decision(rules, "hard_gate", outcome, reasons or [Code.GATE_OPEN], {"profile": profile.to_dict()})


def _band(bands, value):
    for b in bands:
        if (b["lower"] is None or value >= b["lower"]) and (b["upper"] is None or value < b["upper"]):
            return b
    raise AssertionError("bands are validated to cover all values")


def pre_check(rules, profile: Profile, vitals: Vitals, symptoms=(), conditions=()) -> Decision:
    pre = rules["precheck"]
    symptoms, conditions = frozenset(symptoms), frozenset(conditions)
    _check_known("symptom", symptoms, pre["emergency_symptoms"] + pre["red_symptoms"] + pre["yellow_symptoms"])
    _check_known("condition", conditions, pre["red_conditions"] + pre["yellow_conditions"])
    inputs = {"profile": profile.to_dict(), "vitals": asdict(vitals),
              "symptoms": sorted(symptoms), "conditions": sorted(conditions)}

    # 1) 급성 위급 증상: 수치·게이트와 상관없이 즉시 119 화면
    emergency = sorted(symptoms & set(pre["emergency_symptoms"]))
    if emergency:
        return _decision(rules, "pre_check", Light.EMERGENCY, [Code.PRE_EMERGENCY_SYMPTOM], inputs,
                         {"symptoms": emergency})

    # 2) 하드 게이트
    blocked = gate_reasons(rules, profile)
    if blocked:
        return _decision(rules, "pre_check", Light.BLOCKED, blocked, inputs)

    findings = []  # (light, code)

    # 3) 증상·컨디션
    if symptoms & set(pre["red_symptoms"]):
        findings.append((Light.RED, Code.PRE_RED_SYMPTOM))
    if symptoms & set(pre["yellow_symptoms"]):
        findings.append((Light.YELLOW, Code.PRE_YELLOW_SYMPTOM))
    if conditions & set(pre["red_conditions"]):
        findings.append((Light.RED, Code.PRE_RED_CONDITION))
    if conditions & set(pre["yellow_conditions"]):
        findings.append((Light.YELLOW, Code.PRE_YELLOW_CONDITION))

    # 4) 측정 출처 등급
    bp_grade = rules["source_grades"]["blood_pressure"].get(vitals.bp_source)
    hr_grade = rules["source_grades"]["heart_rate"].get(vitals.hr_source)
    if bp_grade is None or hr_grade is None:
        raise ValueError(f"unknown measurement source: bp={vitals.bp_source} hr={vitals.hr_source}")
    bp_usable = bp_grade in ("A", "B")
    if not bp_usable:
        findings.append((Light.REMEASURE, Code.PRE_BP_SOURCE_NOT_ALLOWED))

    # 5) 수치 밴드 + 의사 개인 한도
    values = {"systolic": vitals.systolic, "diastolic": vitals.diastolic, "resting_hr": vitals.resting_hr}
    plausible = {}
    for metric in _METRICS:
        if metric != "resting_hr" and not bp_usable:
            continue
        v = values[metric]
        if v is None:
            findings.append((Light.REMEASURE, Code.PRE_MISSING_VALUE))
            continue
        p = rules["plausibility"][metric]
        if not (p["min"] <= v <= p["max"]):
            findings.append((Light.REMEASURE, Code.PRE_IMPLAUSIBLE_VALUE))
            continue
        plausible[metric] = v
        band = _band(pre["bands"][metric], v)
        light = Light(band["light"])
        grade = hr_grade if metric == "resting_hr" else bp_grade
        if grade == "B" and light == Light.GREEN:
            # B 등급(워치)은 좋게 나와도 안전 근거로 쓰지 않는다 → low_grade_green(초안: 노랑, 가볍게).
            alt = rules["low_grade_green"]["heart_rate" if metric == "resting_hr" else "blood_pressure"]
            findings.append((Light(alt["light"]), alt["code"]))
        else:
            findings.append((light, band["code"]))

        limit = getattr(profile.doctor_limits, _LIMIT_FIELD[metric])
        default = pre["doctor_limit_defaults"][_LIMIT_FIELD[metric]]
        if limit is not None:
            if limit > default:
                findings.append((Light.GREEN, Code.DOCTOR_LIMIT_LOOSER_IGNORED))
            elif v >= limit:
                findings.append((Light.RED, Code.PRE_OVER_DOCTOR_LIMIT))

    if (rules["plausibility"]["require_systolic_above_diastolic"]
            and "systolic" in plausible and "diastolic" in plausible
            and plausible["systolic"] <= plausible["diastolic"]):
        findings.append((Light.REMEASURE, Code.PRE_IMPLAUSIBLE_VALUE))

    outcome = worst(light for light, _ in findings)
    reasons = []
    for _, code in findings:
        if code not in reasons:
            reasons.append(code)
    return _decision(rules, "pre_check", outcome, reasons, inputs)


def allowance(rules, light, planned_minutes):
    """신호등별 오늘 허용 범위. 유도 엔진은 이 범위 밖을 고를 수 없다."""
    light = Light(light)
    if light not in (Light.GREEN, Light.YELLOW):
        return {"allowed": False, "max_minutes": 0}
    a = rules["allowance"][light.value]
    minutes = max(a["min_minutes"], math.floor(planned_minutes * a["minutes_factor"]))
    return {
        "allowed": True,
        "max_minutes": min(planned_minutes, minutes),
        "intensity": a["intensity"],
        "hr_ceiling_pct_cap": a["hr_ceiling_pct_cap"],
    }


def post_check(rules, resting_hr, hr_after_recovery) -> Decision:
    """운동 후 3분 휴식 심박이 안정 시보다 많이 높게 남으면 다음 운동 강도를 낮춘다."""
    p = rules["post"]
    slow = hr_after_recovery - resting_hr >= p["elevated_delta_bpm"]
    return _decision(rules, "post_check", "SLOW_RECOVERY" if slow else "RECOVERED",
                     [Code.POST_SLOW_RECOVERY if slow else Code.POST_RECOVERED],
                     {"resting_hr": resting_hr, "hr_after_recovery": hr_after_recovery},
                     {"next_intensity_down": slow})
