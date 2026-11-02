"""모바일 운동 콘텐츠(mobile/assets/exercises.json)가 유도 엔진 규칙·문구 가드레일과 어긋나지 않는지.

콘텐츠는 앱이 화면·음성으로 그대로 내보내므로 문구 풀과 같은 검사를 받는다.
"""
import json
from pathlib import Path

import pytest

from induction_engine import load_config, violations

CONTENT = json.loads((Path(__file__).resolve().parents[2] / "mobile/assets/exercises.json").read_text(encoding="utf-8"))
CFG = load_config()
MOVES = CONTENT["moves"]
POSES = {  # mobile/lib/ui/figure.dart 의 poses 와 같아야 한다
    "sit", "sit_breath_in", "sit_shrug", "sit_toes_up", "sit_knee_up", "sit_knee_up_arm", "sit_arms_fwd",
    "sit_leg_ext", "sit_arms_up", "sit_arms_bent", "sit_squeeze", "sit_lean_fwd", "sit_reach_up",
    "stand", "stand_lean", "stand_tandem", "stand_front_chair", "walk_a", "walk_b",
    "stand_hold", "stand_hold_knee_up", "stand_hold_heel_up", "stand_hold_lean", "stand_hold_one_leg",
}


def plan_moves(plan):
    return plan["warmup"] + plan["main"] + plan["cooldown"]


def test_every_engine_activity_has_content():
    assert {a["id"] for a in CFG.rules["activities"]} == set(CONTENT["activities"])


def test_activity_names_match_engine():
    assert {a["id"]: a["name"] for a in CFG.rules["activities"]} == {k: v["name"] for k, v in CONTENT["activities"].items()}


@pytest.mark.parametrize("activity", CFG.rules["activities"], ids=lambda a: a["id"])
def test_activity_moves_respect_engine_limits(activity):
    """앉아서 하는 운동에 서는 동작이, 붙잡고 하는 운동에 붙잡지 않는 동작이 섞이면 안 된다(낙상 걱정·두려움 단계)."""
    plan = CONTENT["activities"][activity["id"]]
    assert plan["main"], "본 운동 동작이 없다"
    for mid in plan_moves(plan):
        move = MOVES[mid]
        if activity["seated"]:
            assert move["seated"], f"{mid}: 앉아서 하는 운동에 선 동작"
        if activity["supported"]:
            assert move["supported"], f"{mid}: 붙잡고 하는 운동에 붙잡지 않는 동작"


@pytest.mark.parametrize("mid", list(MOVES))
def test_move_is_complete(mid):
    m = MOVES[mid]
    assert m["how"] and m["cues"] and m["caution"]
    assert 15 <= m["seconds"] <= 180
    assert m["tempo_seconds"] > 0
    assert len(m["poses"]) == 2 and set(m["poses"]) <= POSES
    if m["seated"]:
        assert all(p.startswith("sit") for p in m["poses"]), "앉은 동작 그림은 앉은 자세"


@pytest.mark.parametrize("mid", list(MOVES))
def test_move_text_passes_guardrails(mid):
    m = MOVES[mid]
    for text in [m["name"], m["caution"], *m["how"], *m["cues"]]:
        assert violations(CFG, text) == [], text
