"""시나리오 정답표 생성기.

정답은 계획서 5장 표를 이 파일에 *따로* 옮겨 적은 값으로 만든다(규칙 YAML을 읽지 않음).
그래서 누가 YAML 수치를 바꾸면 정답표와 어긋나 테스트가 깨진다 = 자문단 승인 없는 변경 탐지.

생성물(scenarios/*.csv)이 검수 대상 "정답표"다. 의료 자문단은 CSV의 expected 열을 직접 고치고,
tools/agreement_report.py로 엔진과의 일치율을 본다. 이 스크립트는 초안을 처음 만들 때만 쓴다.

    python tools/generate_scenarios.py
"""
import csv
import itertools
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "scenarios"

G, Y, RM, R, B, EM = "GREEN", "YELLOW", "REMEASURE", "RED", "BLOCKED", "EMERGENCY"
ORDER = [G, Y, RM, R, B, EM]


def worst(*lights):
    return max(lights, key=ORDER.index)


PRE_COLS = ["id", "group", "age", "sbp", "dbp", "hr", "bp_source", "hr_source", "symptoms", "conditions",
            "gate_conditions", "parq_risk", "clearance", "device", "dr_sbp_max", "dr_dbp_max", "dr_hr_max",
            "dr_hr_ceiling", "expected", "expected_codes", "note"]

GREEN_VITALS = dict(sbp=130, dbp=80, hr=70)


def pre_rows():
    rows = []

    def add(group, expected, note, codes="", **kw):
        row = {c: "" for c in PRE_COLS}
        row.update(age=72, bp_source="manual", hr_source="manual", **GREEN_VITALS)
        row.update(kw)
        row.update(group=group, expected=expected, expected_codes=codes, note=note)
        rows.append(row)

    # 수축기: 재측정 <70 | 빨강 <90 | 초록 90~159 | 노랑 160~179 | 빨강 180~260 | 재측정 >260
    sbp = [(60, RM), (69, RM), (70, R), (75, R), (89, R), (89.5, R), (90, G), (91, G), (120, G), (140, G),
           (158, G), (159, G), (159.5, G), (160, Y), (161, Y), (170, Y), (178, Y), (179, Y), (179.5, Y),
           (180, R), (181, R), (200, R), (220, R), (259, R), (260, R), (261, RM), (300, RM)]
    for v, exp in sbp:
        add("sbp_boundary", exp, f"수축기 {v}", sbp=v, dbp=60)

    # 이완기: 재측정 <30 | 빨강 <50 | 초록 50~99 | 노랑 100~109 | 빨강 110~150 | 재측정 >150
    dbp = [(25, RM), (29, RM), (30, R), (40, R), (49, R), (49.5, R), (50, G), (51, G), (80, G), (99, G),
           (99.5, G), (100, Y), (105, Y), (109, Y), (109.5, Y), (110, R), (111, R), (120, R), (129, R),
           (151, RM), (170, RM)]
    for v, exp in dbp:
        add("dbp_boundary", exp, f"이완기 {v}", dbp=v)

    # 안정 시 심박: 재측정 <30 | 빨강 <45 | 노랑 45~49(계획서 공백, 보수적) | 초록 50~99 | 노랑 100~119 | 빨강 120~220
    hr = [(20, RM), (29, RM), (30, R), (40, R), (44, R), (44.5, R), (45, Y), (47, Y), (49, Y), (49.5, Y),
          (50, G), (51, G), (75, G), (99, G), (99.5, G), (100, Y), (110, Y), (119, Y), (119.5, Y), (120, R),
          (121, R), (150, R), (220, R), (221, RM), (250, RM)]
    for v, exp in hr:
        add("hr_boundary", exp, f"안정 시 심박 {v}", hr=v)

    # 수축기 ≤ 이완기 → 재측정
    for s, d, exp in [(95, 95, RM), (100, 99, G), (92, 98, RM), (100, 100, RM)]:
        add("bp_inverted", exp, f"{s}/{d}", sbp=s, dbp=d)

    # 증상
    for s in ["chest_pain", "fainted", "reduced_consciousness", "one_side_weakness", "slurred_speech"]:
        add("symptom", EM, f"급성 위급 증상 {s} → 119", codes="PRE_EMERGENCY_SYMPTOM", symptoms=s)
    for s in ["shortness_of_breath", "dizziness", "severe_unusual_fatigue"]:
        add("symptom", R, f"빨강 증상 {s}", codes="PRE_RED_SYMPTOM", symptoms=s)
    add("symptom", Y, "가벼운 피로", codes="PRE_YELLOW_SYMPTOM", symptoms="mild_fatigue")
    add("symptom", R, "가벼운 피로 + 어지러움", symptoms="mild_fatigue|dizziness")
    add("symptom", EM, "흉통 + 가벼운 피로", symptoms="chest_pain|mild_fatigue")
    add("symptom", EM, "위급 증상은 빨강 수치보다 우선", symptoms="slurred_speech", sbp=190)
    add("symptom", EM, "위급 증상은 비현실 수치보다 우선", symptoms="one_side_weakness", sbp=300)
    add("symptom", EM, "위급 증상은 하드 게이트보다 우선", symptoms="chest_pain", gate_conditions="unstable_angina")
    add("symptom", Y, "가벼운 피로 + 노랑 혈압", symptoms="mild_fatigue", sbp=165)
    add("symptom", R, "숨참 + 노랑 심박", symptoms="shortness_of_breath", hr=105)

    # 컨디션
    for c in ["fever", "acute_illness"]:
        add("condition", R, f"빨강 컨디션 {c}", codes="PRE_RED_CONDITION", conditions=c)
    for c in ["rested_3plus_days", "poor_sleep", "missed_medication"]:
        add("condition", Y, f"노랑 컨디션 {c}", codes="PRE_YELLOW_CONDITION", conditions=c)
    add("condition", Y, "노랑 컨디션 2개", conditions="poor_sleep|missed_medication")
    add("condition", R, "노랑 + 빨강 컨디션", conditions="poor_sleep|fever")
    add("condition", R, "열 + 가벼운 피로", conditions="fever", symptoms="mild_fatigue")

    # 가장 나쁜 항목 따르기: 대표값 교차
    sbp_rep = [(130, G), (170, Y), (185, R), (85, R), (265, RM)]
    dbp_rep = [(80, G), (105, Y), (115, R), (155, RM)]
    hr_rep = [(70, G), (110, Y), (125, R), (225, RM)]
    for (s, es), (d, ed), (h, eh) in itertools.product(sbp_rep, dbp_rep, hr_rep):
        exp = worst(es, ed, eh)
        if s <= d and es != RM and ed != RM:
            exp = worst(exp, RM)
        add("worst_wins", exp, f"{s}/{d}, 심박 {h}", sbp=s, dbp=d, hr=h)

    # 측정 출처·누락
    # 발주사 결정(2026-11-02, 자문단 확인 필요): 워치 혈압 C → B. 정상이어도 노랑, 나쁘면 그대로 반영
    add("source", Y, "워치 혈압이 정상이어도 가볍게(B 등급)", codes="PRE_BP_SOURCE_LOW_GRADE", bp_source="watch")
    add("source", R, "워치 혈압이 높으면 그대로 빨강", codes="PRE_SBP_HIGH", bp_source="watch", sbp=190)
    add("source", Y, "워치 혈압 노랑은 그대로 노랑", codes="PRE_SBP_ELEVATED", bp_source="watch", sbp=165)
    add("source", Y, "워치 혈압 + 워치 심박 모두 정상이면 노랑", bp_source="watch", hr_source="watch")
    add("source", R, "워치 혈압 + 빨강 심박(상완형 맥박)", bp_source="watch", hr=125)
    add("source", R, "워치 혈압 + 빨강 증상", bp_source="watch", symptoms="dizziness")
    add("source", G, "BLE 상완형 혈압계", bp_source="ble_upper_arm", hr_source="ble_upper_arm")
    add("source", G, "가슴 스트랩 심박", hr_source="chest_strap")
    add("source", Y, "워치 심박이 정상이어도 가볍게(B 등급)", codes="PRE_HR_SOURCE_LOW_GRADE", hr_source="watch")
    add("source", Y, "워치 심박 노랑은 반영", hr_source="watch", hr=110)
    add("source", R, "워치 심박 빨강은 반영", hr_source="watch", hr=125)
    add("source", RM, "수축기 누락", codes="PRE_MISSING_VALUE", sbp="")
    add("source", RM, "심박 누락", codes="PRE_MISSING_VALUE", hr="")
    add("source", R, "누락 + 빨강 증상", sbp="", symptoms="shortness_of_breath")

    # 하드 게이트
    gate = ["unstable_angina", "uncontrolled_arrhythmia", "worsening_heart_failure", "recent_myocardial_infarction",
            "recent_cardiac_surgery", "recent_stroke", "severe_aortic_stenosis", "syncope_history"]
    for c in gate:
        add("gate", B, f"{c}, 확인서 없음", codes="GATE_CONDITION_NEEDS_CLEARANCE", gate_conditions=c)
    for c in gate[:4]:
        add("gate", G, f"{c}, 의사 확인서 있음", gate_conditions=c, clearance=1)
    add("gate", B, "문진 위험 응답", codes="GATE_PARQ_RISK", parq_risk=1)
    add("gate", G, "문진 위험 + 확인서", parq_risk=1, clearance=1)
    add("gate", B, "심박조율기, 심박 상한 없음", codes="GATE_DEVICE_NEEDS_HR_CEILING", device="pacemaker")
    add("gate", B, "ICD, 확인서 있어도 상한 없으면 잠금", codes="GATE_DEVICE_NEEDS_HR_CEILING", device="icd", clearance=1)
    add("gate", G, "심박조율기 + 의사 상한", device="pacemaker", dr_hr_ceiling=110)
    add("gate", B, "게이트가 빨강 수치보다 우선", gate_conditions="recent_stroke", sbp=190)

    # 의사 개인 한도: 더 엄격할 때만 적용
    add("doctor_limit", G, "수축기 한도 150, 149", dr_sbp_max=150, sbp=149)
    add("doctor_limit", R, "수축기 한도 150, 150", codes="PRE_OVER_DOCTOR_LIMIT", dr_sbp_max=150, sbp=150)
    add("doctor_limit", R, "수축기 한도 150, 155", dr_sbp_max=150, sbp=155)
    add("doctor_limit", R, "수축기 한도 150, 165(원래 노랑)", dr_sbp_max=150, sbp=165)
    add("doctor_limit", R, "느슨한 한도 200은 무시, 185는 빨강", codes="DOCTOR_LIMIT_LOOSER_IGNORED", dr_sbp_max=200, sbp=185)
    add("doctor_limit", Y, "느슨한 한도 200은 무시, 175는 노랑", codes="DOCTOR_LIMIT_LOOSER_IGNORED", dr_sbp_max=200, sbp=175)
    add("doctor_limit", Y, "기본과 같은 한도 180, 179", dr_sbp_max=180, sbp=179)
    add("doctor_limit", R, "기본과 같은 한도 180, 180", dr_sbp_max=180, sbp=180)
    add("doctor_limit", G, "이완기 한도 90, 89", dr_dbp_max=90, dbp=89)
    add("doctor_limit", R, "이완기 한도 90, 90", dr_dbp_max=90, dbp=90)
    add("doctor_limit", G, "심박 한도 90, 89", dr_hr_max=90, hr=89)
    add("doctor_limit", R, "심박 한도 90, 90", dr_hr_max=90, hr=90)
    add("doctor_limit", R, "느슨한 심박 한도 130은 무시, 125는 빨강", dr_hr_max=130, hr=125)
    add("doctor_limit", RM, "한도가 있어도 비현실 값은 재측정", dr_sbp_max=150, sbp=265)

    for i, row in enumerate(rows, 1):
        row["id"] = f"P{i:03d}"
    return rows


def limits_rows():
    """심박 상한. Tanaka 208-0.7×나이, 시작 4주 70%, 승급 76%, 베타차단제 85%, 노랑 64% 상한."""
    rows = []

    def floor(x):
        return math.floor(round(x, 6))

    def add(age, weeks=0, escalation=0, beta=0, light=G, dr_ceiling="", device="", note=""):
        mx = 208 - 0.7 * age
        if beta:
            pct, mode = 0.85, "anomaly_only"
        elif weeks >= 4 and escalation:
            pct, mode = 0.76, "zone"
        else:
            pct, mode = 0.70, "zone"
        if light == Y:
            pct = min(pct, 0.64)
        ceiling = floor(mx * pct)
        if dr_ceiling != "":
            ceiling = min(ceiling, dr_ceiling)
        rows.append(dict(age=age, weeks=weeks, escalation=escalation, beta_blocker=beta, light=light,
                         dr_hr_ceiling=dr_ceiling, device=device, expected_ceiling=ceiling,
                         expected_mode=mode, note=note))

    for age in [60, 65, 68, 70, 72, 75, 78, 80, 85, 90]:
        add(age, note="시작 4주 70%")
        add(age, weeks=6, escalation=1, note="승급 76%")
        add(age, beta=1, note="베타차단제: 구간 끔, 85% 이상 감지")
    add(70, weeks=3, escalation=1, note="승급 승인돼도 4주 전이면 70%")
    add(70, weeks=4, escalation=1, note="4주째 + 승인 → 76%")
    add(70, weeks=8, escalation=0, note="승인 없으면 계속 70%")
    for age in [65, 70, 75, 80, 85]:
        add(age, light=Y, note="노랑: 64% 상한")
    add(70, weeks=6, escalation=1, light=Y, note="승급자도 노랑이면 64%")
    add(70, beta=1, light=Y, note="베타차단제 + 노랑 → 64%")
    add(70, dr_ceiling=100, note="의사 상한이 더 낮으면 의사 값")
    add(70, dr_ceiling=130, note="의사 상한이 더 높으면 규칙 값")
    add(70, weeks=6, escalation=1, dr_ceiling=115, note="승급 120 vs 의사 115")
    add(75, device="pacemaker", dr_ceiling=105, note="심박조율기: 의사 상한")
    add(68, device="icd", dr_ceiling=100, note="ICD: 의사 상한")
    for i, row in enumerate(rows, 1):
        row["id"] = f"L{i:03d}"
    return rows


def misc_rows():
    rows = []
    for rest, after, exp in [(70, 89, "RECOVERED"), (70, 90, "SLOW_RECOVERY"), (70, 91, "SLOW_RECOVERY"),
                             (60, 79, "RECOVERED"), (60, 80, "SLOW_RECOVERY"), (80, 95, "RECOVERED"),
                             (80, 100, "SLOW_RECOVERY"), (75, 75, "RECOVERED")]:
        rows.append(dict(kind="post_check", a=rest, b=after, expected=exp,
                         note=f"안정 {rest}, 3분 휴식 후 {after}"))
    for light, planned, exp in [(G, 10, 10), (G, 3, 3), (G, 30, 30), (Y, 10, 5), (Y, 3, 3), (Y, 5, 3),
                                (Y, 8, 4), (Y, 15, 7), (Y, 30, 15), (R, 10, 0), (RM, 10, 0), (B, 10, 0),
                                (EM, 10, 0)]:
        rows.append(dict(kind="allowance", a=light, b=planned, expected=exp,
                         note=f"{light} 계획 {planned}분 → 최대 {exp}분"))
    for i, row in enumerate(rows, 1):
        row["id"] = f"M{i:03d}"
    return rows


def write(name, rows, cols):
    with open(OUT / name, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    print(f"{name}: {len(rows)}")


if __name__ == "__main__":
    write("precheck.csv", pre_rows(), PRE_COLS)
    write("hr_limits.csv", limits_rows(), ["id", "age", "weeks", "escalation", "beta_blocker", "light",
                                          "dr_hr_ceiling", "device", "expected_ceiling", "expected_mode", "note"])
    write("post_and_allowance.csv", misc_rows(), ["id", "kind", "a", "b", "expected", "note"])
