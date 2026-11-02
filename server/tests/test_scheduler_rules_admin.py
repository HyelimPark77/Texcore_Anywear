from datetime import time

from app import models as m
from app.config import KST
from conftest import World


def _notes(w, uid, day=None):
    with w.ctx.sessionmaker() as db:
        q = db.query(m.Notification).filter_by(elder_id=uid)
        if day is not None:
            q = q.filter_by(day=day)
        return q.order_by(m.Notification.id).all()


def run_daily(w, admin_h):
    r = w.client.post("/admin/jobs/daily", headers=admin_h)
    assert r.status_code == 200, r.text
    return r.json()["elders"]


def test_daily_job_idempotent_and_schedules_within_window(w):
    admin = w.admin()
    h, uid = w.elder(settings={"preferred_time": "06:00"})
    first = run_daily(w, admin)
    second = run_daily(w, admin)
    assert first == second
    notes = _notes(w, uid)
    assert len(notes) == 2
    times = [n.scheduled_at.replace(tzinfo=KST).time() if n.scheduled_at.tzinfo is None else
             n.scheduled_at.astimezone(KST).time() for n in notes]
    assert times == [time(7, 0), time(19, 0)]          # 06:00 요청 → 07:00으로 당김
    assert [n.intent for n in notes] == ["reminder", "evening_mini"]


def test_dispatch_sends_due_and_cancels_after_exercise(w):
    admin = w.admin()
    h, uid = w.elder(settings={"preferred_time": "09:00"})
    run_daily(w, admin)
    w.at(hour=8, minute=59)
    assert w.client.post("/admin/jobs/dispatch", headers=admin).json() == {"sent": 0, "cancelled": 0}
    w.at(hour=9, minute=0)
    assert w.client.post("/admin/jobs/dispatch", headers=admin).json() == {"sent": 1, "cancelled": 0}
    assert [s.body for s in w.gw.sent if s.to_user_id == uid and s.channel == "push"]
    w.at(hour=10)
    w.exercise(h)                                       # 운동하면 저녁 "1분만" 알림 취소
    w.at(hour=19, minute=5)
    assert w.client.post("/admin/jobs/dispatch", headers=admin).json() == {"sent": 0, "cancelled": 0}
    assert [n.cancelled for n in _notes(w, uid)] == [False, True]


def test_ignored_notifications_reduce_to_one(w):
    admin = w.admin()
    h, uid = w.elder(settings={"preferred_time": "09:00"})
    for d in range(2):
        w.at(days=d, hour=6)
        run_daily(w, admin)
        w.at(days=d, hour=9)
        w.client.post("/admin/jobs/dispatch", headers=admin)
        w.at(days=d, hour=19)
        w.client.post("/admin/jobs/dispatch", headers=admin)
    w.at(days=2, hour=6)
    result = run_daily(w, admin)[str(uid)]
    assert result["notifications"]["fatigued"] and result["notifications"]["count"] == 1
    assert w.client.get("/me/today", headers=h).json()["ask_time_change"] is True


def test_opened_notification_counts(w):
    admin = w.admin()
    h, uid = w.elder(settings={"preferred_time": "09:00"})
    for d in range(2):
        w.at(days=d, hour=6)
        run_daily(w, admin)
        w.at(days=d, hour=9)
        w.client.post("/admin/jobs/dispatch", headers=admin)
        nid = _notes(w, uid)[-2].id
        w.at(days=d, hour=9, minute=20)
        w.client.post(f"/me/notifications/{nid}/opened", headers=h)
        w.at(days=d, hour=19)
        w.client.post("/admin/jobs/dispatch", headers=admin)
    w.at(days=2, hour=6)
    assert run_daily(w, admin)[str(uid)]["notifications"]["fatigued"] is False


def test_ladder_promotes_after_a_week(w):
    admin = w.admin()
    h, uid = w.elder()
    for d in (1, 2, 4, 6):                              # 최근 7일(1~7일) 안에 4회
        w.at(days=d, hour=9)
        w.exercise(h)
    w.at(days=7, hour=6)
    result = run_daily(w, admin)[str(uid)]
    assert result["ladder"]["code"] == "LADDER_UP" and result["ladder"]["level"] == 1
    assert "5분" in result["ladder"]["message"]
    w.at(days=7, hour=9)
    assert w.precheck(h)["plan"]["minutes"] == 5


def test_reengagement_cheer_request_needs_full_scope_and_consent(w):
    admin = w.admin()
    h, uid = w.elder()
    full, gfull = w.guardian(h, phone="01033334444", scope="full")
    w.exercise(h)                                       # 0일차 운동 후 쉼
    w.at(days=4, hour=6)                                # 1·2·3일 미실행 → 3일 단계
    r = run_daily(w, admin)[str(uid)]["reengagement"]
    assert r["tier"] == "MISSED_3" and "request_guardian_cheer" in r["withheld"]
    assert w.pushes(gfull, "cheer_request") == []

    w2 = World()
    admin2 = w2.admin()
    h2, uid2 = w2.elder()
    w2.client.post("/me/consents", json={"kind": "guardian_cheer_request", "granted": True}, headers=h2)
    _, g2 = w2.guardian(h2, scope="full")
    w2.exercise(h2)
    w2.at(days=4, hour=6)
    r2 = run_daily(w2, admin2)[str(uid2)]["reengagement"]
    assert r2["guardian_actions"] == ["request_guardian_cheer"]
    assert len(w2.pushes(g2, "cheer_request")) == 1


def test_two_week_lapse(w):
    admin = w.admin()
    h, uid = w.elder()
    cheer, gcheer = w.guardian(h, phone="01055556666", scope="cheer_only")
    full, gfull = w.guardian(h, phone="01033334444", scope="full")
    w.exercise(h)
    w.at(days=15, hour=6)
    r = run_daily(w, admin)[str(uid)]
    assert r["ladder"]["code"] == "LADDER_RESTART" and r["ladder"]["restart_pending"]
    assert r["reengagement"]["prompts"] == ["restart_offer"]
    assert len(w.pushes(gfull, "lapse")) == 1 and w.pushes(gcheer, "lapse") == []
    w.client.post("/me/ladder/restart", headers=h)
    assert w.client.get("/me/today", headers=h).json()["ladder"]["minutes"] == 3


def test_week_view(w):
    h, uid = w.elder()
    w.exercise(h)
    w.at(days=1)
    w.precheck(h, sbp=185)
    w.at(days=2)
    week = w.client.get("/me/week", headers=h).json()
    assert [d["stamp"] for d in week["days"]][-3:] == [True, True, False]
    assert week["streak"] == 2


# ---- 규칙 번들 ----
def test_draft_rules_not_served_in_production():
    w = World(allow_draft=False)
    r = w.client.get("/rules/safety")
    assert r.status_code == 503 and "draft" in r.json()["detail"]
    assert w.client.get("/rules/safety/version").json()["status"] == "draft"


def test_rules_bundle_and_etag(w):
    r = w.client.get("/rules/safety")
    assert r.status_code == 200
    body = r.json()
    assert body["sha256"] == w.ctx.engines.safety_rules.sha256 and body["rules"]["meta"]["version"] == body["version"]
    again = w.client.get("/rules/safety", headers={"If-None-Match": r.headers["etag"]})
    assert again.status_code == 304


def test_admin_views(w):
    admin = w.admin()
    h, uid = w.elder()
    w.precheck(h, sbp=185)
    logs = w.client.get(f"/admin/decision-log?user_id={uid}&kind=pre_check", headers=admin).json()
    assert logs[0]["payload"]["outcome"] == "RED" and logs[0]["rule_version"] == "0.2.0-draft"
    assert w.client.get("/admin/decision-log/verify", headers=admin).json() == {"ok": True, "broken_at": None}
