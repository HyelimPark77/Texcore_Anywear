"""규칙 번들 로드·검증.

같은 번들을 단말(오프라인 안전 엔진)에도 내려보내므로, 로드 시점에 구조와
일관성을 검사하고 내용 해시를 붙여 판정 로그에 남긴다.
"""
import copy
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import yaml

from .codes import Light

DEFAULT_RULES_PATH = Path(__file__).resolve().parent.parent / "rules" / "safety_rules.yaml"


class RuleError(ValueError):
    pass


@dataclass(frozen=True)
class RuleBundle:
    data: dict
    version: str
    sha256: str

    @property
    def approved(self):
        return self.data["meta"]["status"] == "approved"

    def __getitem__(self, key):
        return self.data[key]

    def to_json(self):
        """단말 배포용 정규화 JSON(키 정렬). 해시도 이 표현으로 계산한다."""
        return json.dumps(self.data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def load_rules(path=DEFAULT_RULES_PATH, require_approved=False):
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return bundle_from_dict(data, require_approved=require_approved)


def bundle_from_dict(data, require_approved=False):
    data = copy.deepcopy(data)
    validate(data)
    if require_approved and data["meta"]["status"] != "approved":
        raise RuleError(f"rule bundle {data['meta']['version']} is not approved by the advisory board")
    canonical = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return RuleBundle(
        data=data,
        version=str(data["meta"]["version"]),
        sha256=hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
    )


def _require(cond, msg):
    if not cond:
        raise RuleError(msg)


def _check_bands(name, bands):
    _require(bands, f"{name}: no bands")
    _require(bands[0]["lower"] is None, f"{name}: first band must start at null (-inf)")
    _require(bands[-1]["upper"] is None, f"{name}: last band must end at null (+inf)")
    for prev, cur in zip(bands, bands[1:]):
        _require(prev["upper"] is not None and prev["upper"] == cur["lower"],
                 f"{name}: gap or overlap between {prev} and {cur}")
    for b in bands:
        _require(b["light"] in (Light.GREEN, Light.YELLOW, Light.RED), f"{name}: bad light {b['light']}")
        _require(b.get("code"), f"{name}: band without code")
        if b["lower"] is not None and b["upper"] is not None:
            _require(b["lower"] < b["upper"], f"{name}: empty band {b}")


def validate(d):
    for key in ("meta", "hard_gate", "plausibility", "source_grades", "low_grade_green", "precheck",
                "allowance", "session", "post", "emergency"):
        _require(key in d, f"missing section: {key}")
    _require(d["meta"].get("version"), "meta.version required")
    _require(d["meta"].get("status") in ("draft", "approved"), "meta.status must be draft|approved")
    if d["meta"]["status"] == "approved":
        _require(d["meta"].get("approved_by"), "approved bundle needs approved_by")

    # B 등급의 '초록'은 안전 근거가 아니므로 초록으로 둘 수 없다
    for kind in ("blood_pressure", "heart_rate"):
        _require(d["low_grade_green"][kind]["light"] in ("YELLOW", "REMEASURE", "RED"),
                 f"low_grade_green.{kind}: must not be GREEN")

    pre = d["precheck"]
    for metric in ("systolic", "diastolic", "resting_hr"):
        _check_bands(metric, pre["bands"][metric])
        p = d["plausibility"][metric]
        _require(p["min"] < p["max"], f"plausibility.{metric}: min >= max")

    # 증상·컨디션 목록은 서로 겹치면 안 된다(같은 입력이 두 등급으로 해석되는 것 방지)
    sym = [pre["emergency_symptoms"], pre["red_symptoms"], pre["yellow_symptoms"]]
    flat = [s for group in sym for s in group]
    _require(len(flat) == len(set(flat)), "precheck symptom lists overlap")
    _require(not set(pre["red_conditions"]) & set(pre["yellow_conditions"]), "condition lists overlap")

    s = d["session"]
    cp = s["ceiling_pct"]
    _require(0 < cp["initial"] <= cp["escalated"] <= cp["absolute_max"] <= 0.85,
             "ceiling_pct must satisfy initial <= escalated <= absolute_max <= 0.85")
    _require(s["zone_pct"]["lower"] < s["zone_pct"]["upper"], "zone_pct lower >= upper")
    _require(s["rpe"]["step_down_at"] < s["rpe"]["stop_at"], "rpe step_down_at must be < stop_at")
    _require(s["stop_ratio_over_ceiling"] > 1.0, "stop_ratio_over_ceiling must be > 1")
    _require(s["sensor"]["fallback_checkin_interval_seconds"] <= s["checkin_interval_seconds"],
             "sensor fallback must ask at least as often as normal check-in")
    for grade in ("A", "B", "C"):
        _require(grade in s["heart_rate_grades"], f"session.heart_rate_grades.{grade} missing")

    for light in ("GREEN", "YELLOW", "RED"):
        _require(light in d["allowance"], f"allowance.{light} missing")
    _require(d["allowance"]["RED"]["allowed"] is False, "RED must never allow exercise")
    cap = d["allowance"]["YELLOW"].get("hr_ceiling_pct_cap")
    if cap is not None:
        _require(cap <= cp["initial"], "YELLOW hr cap must not exceed initial ceiling")
