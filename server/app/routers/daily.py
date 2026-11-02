"""어르신 하루 한 바퀴: 오늘 → 운동 전 점검(안전 엔진) → 오늘의 계획(유도 엔진) → 운동 → 칭찬 → 보호자 공유.

운동 중 판정은 단말 안전 엔진이 오프라인으로 한다. 서버는 기록을 받아 판정 로그에 남기고 보호자에게 알린다.
서버도 운동 시작 시 오늘 판정을 다시 확인해 허용 범위 밖의 세션을 열지 않는다.
"""
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from induction_engine import completion_message, day_reward, plan_today, streak
from safety_engine import Vitals

from .. import models as m
from ..deps import AppContext, ctx, elder_user, get_db
from ..engines import _as_aware, build_history, induction_profile, ladder_state, record_message_use, safety_profile
from ..services import (ALL_SCOPES, FULL, alert_guardians, days_back, has_consent, plan_to_dict, run_daily_for,
                        today_rewards, user_state)

router = APIRouter(prefix="/me", tags=["elder-daily"])
Source = Literal["manual", "ble_upper_arm", "chest_strap", "watch"]


class PrecheckIn(BaseModel):
    systolic: float | None = None
    diastolic: float | None = None
    resting_hr: float | None = None
    bp_source: Source = "manual"
    hr_source: Source = "manual"
    symptoms: list[str] = []
    conditions: list[str] = []


class SessionStartIn(BaseModel):
    precheck_id: int
    easier: bool = False          # "더 쉬운 걸로"


class DeviceEvent(BaseModel):
    t: float
    event: str
    value: float | str | None = None
    actions: list[dict] = []


class EventsIn(BaseModel):
    events: list[DeviceEvent] = Field(max_length=2000)


class FinishIn(BaseModel):
    completed: bool
    minutes: float = Field(ge=0)
    max_rpe: int | None = Field(None, ge=6, le=20)
    stopped: bool = False
    resting_hr: float | None = None
    hr_after_recovery: float | None = None


class EmergencyIn(BaseModel):
    code: str = Field(max_length=32)            # EM_USER_NOT_OK | EM_NO_RESPONSE | EM_119_CONFIRMED | ...
    severe: bool = False
    snapshot: dict = {}                          # 마지막 혈압·심박 등
    location: dict | None = None                 # 위치 동의가 있을 때만 보호자에게 전달, 저장 안 함


def _elder_profile(db, user):
    return db.get(m.ElderProfile, user.id)


def _require_health(db, user):
    if not has_consent(db, user.id, "health"):
        raise HTTPException(403, "건강 정보 수집 동의가 필요해요")
    if _elder_profile(db, user).health is None:
        raise HTTPException(409, "먼저 기본 건강 정보를 입력해 주세요")


@router.get("/today")
def today(user: m.User = Depends(elder_user), db: Session = Depends(get_db), c: AppContext = Depends(ctx)):
    day = c.clock.today()
    daily = run_daily_for(db, c, user, day)
    profile = _elder_profile(db, user)
    cheer = db.execute(select(m.Cheer).where(m.Cheer.elder_id == user.id, m.Cheer.played_at.is_(None))
                       .order_by(m.Cheer.id.desc())).scalars().first()
    steps = c.engines.induction["ladder"]["steps_minutes"]
    return {"date": day, "state": user_state(c, db, profile, day),
            "ladder": {**daily["ladder"], "minutes": steps[profile.ladder_level]},
            "reengagement": daily["reengagement"], "ask_time_change": daily["notifications"]["ask_time_change"],
            "rewards": today_rewards(db, user.id, day), "has_new_cheer": cheer is not None}


@router.post("/prechecks")
def precheck(body: PrecheckIn, user: m.User = Depends(elder_user), db: Session = Depends(get_db),
             c: AppContext = Depends(ctx)):
    _require_health(db, user)
    day = c.clock.today()
    run_daily_for(db, c, user, day)
    profile = _elder_profile(db, user)
    try:
        decision = c.engines.safety(db, user.id).pre_check(
            safety_profile(profile, day),
            Vitals(body.systolic, body.diastolic, body.resting_hr, body.bp_source, body.hr_source),
            body.symptoms, body.conditions)
    except ValueError as e:
        raise HTTPException(422, str(e))

    history = build_history(db, user.id, day)
    plan = plan_today(c.engines.induction, c.engines.safety_rules, induction_profile(db, profile),
                      ladder_state(profile), history, decision, day, c.weather(user.id, day))
    record_message_use(db, user.id, day, plan.message)
    row = m.Precheck(elder_id=user.id, day=day, created_at=c.clock.now(), inputs=body.model_dump(),
                     outcome=decision.outcome, reasons=list(decision.reasons), rule_version=decision.rule_version,
                     plan=plan_to_dict(plan))
    db.add(row)
    db.flush()

    alerted = 0
    if decision.outcome == "EMERGENCY":
        alerted = alert_guardians(db, c, user, "emergency", {"code": "PRE_EMERGENCY_SYMPTOM"}, ALL_SCOPES,
                                  "급한 증상을 알려 오셨어요. 바로 연락해 보세요.", call=True)
    return {"precheck_id": row.id, "outcome": decision.outcome, "reasons": list(decision.reasons),
            "rule_version": decision.rule_version, "plan": row.plan, "guardians_alerted": alerted}


@router.post("/sessions")
def start_session(body: SessionStartIn, user: m.User = Depends(elder_user), db: Session = Depends(get_db),
                  c: AppContext = Depends(ctx)):
    day = c.clock.today()
    pre = db.get(m.Precheck, body.precheck_id)
    if pre is None or pre.elder_id != user.id:
        raise HTTPException(404, "점검 기록을 찾을 수 없어요")
    if pre.day != day:
        raise HTTPException(409, "오늘 다시 재 주세요")
    if pre.outcome not in ("GREEN", "YELLOW") or (pre.plan or {}).get("action") != "EXERCISE":
        raise HTTPException(409, "오늘은 운동하지 않는 날이에요")
    plan = pre.plan
    minutes, activity_id = plan["minutes"], plan["activity_id"]
    if body.easier:
        minutes, activity_id = plan["easier"]["minutes"], plan["easier"]["activity_id"]

    profile = _elder_profile(db, user)
    weeks = (day - profile.signup_date).days // 7
    limits, _ = c.engines.safety(db, user.id).start_session(
        safety_profile(profile, day), hr_grade=None, light=pre.outcome, weeks_since_start=weeks,
        escalation_approved=profile.hr_escalation_approved)
    activity = c.engines.induction.activity(activity_id)
    s = m.ExerciseSession(elder_id=user.id, precheck_id=pre.id, day=day, activity_id=activity_id,
                          kind=activity["kind"], level=profile.ladder_level, planned_minutes=minutes,
                          hr_limits=limits, started_at=c.clock.now())
    db.add(s)
    db.flush()
    return {"session_id": s.id, "minutes": minutes,
            "activity": {"id": activity_id, "name": activity["name"], "kind": activity["kind"]},
            "hr_limits": limits, "light": pre.outcome,
            "rules": {"version": c.engines.safety_rules.version, "sha256": c.engines.safety_rules.sha256}}


def _own_session(db, user, session_id):
    s = db.get(m.ExerciseSession, session_id)
    if s is None or s.elder_id != user.id:
        raise HTTPException(404, "운동 기록을 찾을 수 없어요")
    return s


@router.post("/sessions/{session_id}/events")
def session_events(session_id: int, body: EventsIn, user: m.User = Depends(elder_user),
                   db: Session = Depends(get_db), c: AppContext = Depends(ctx)):
    """단말 안전 엔진이 낸 행동을 판정 로그에 남긴다. 무응답 알림은 서버가 보호자에게 전달."""
    s = _own_session(db, user, session_id)
    eng = c.engines.safety(db, user.id)
    no_response = False
    for e in body.events:
        eng.record("device_session_event", {"session_id": s.id, **e.model_dump()})
        no_response |= any(a.get("kind") == "GUARDIAN_ALERT" for a in e.actions)
    alerted = 0
    if no_response:
        alerted = alert_guardians(db, c, user, "no_response", {"session_id": s.id}, ALL_SCOPES,
                                  "운동 중 3분 동안 응답이 없어요. 확인해 주세요.", call=True)
    return {"stored": len(body.events), "guardians_alerted": alerted}


@router.post("/sessions/{session_id}/finish")
def finish_session(session_id: int, body: FinishIn, user: m.User = Depends(elder_user),
                   db: Session = Depends(get_db), c: AppContext = Depends(ctx)):
    s = _own_session(db, user, session_id)
    if s.finished_at is not None:
        raise HTTPException(409, "이미 끝난 운동이에요")
    if body.minutes > s.planned_minutes + 1:
        raise HTTPException(422, "계획보다 긴 기록은 받을 수 없어요")
    day = c.clock.today()
    s.finished_at, s.completed, s.minutes = c.clock.now(), body.completed, body.minutes
    s.max_rpe, s.stopped = body.max_rpe, body.stopped
    if body.resting_hr is not None and body.hr_after_recovery is not None:
        post = c.engines.safety(db, user.id).post_check(body.resting_hr, body.hr_after_recovery)
        s.slow_recovery = post.detail["next_intensity_down"]
    db.flush()

    if s.completed:
        for n in db.execute(select(m.Notification).where(
                m.Notification.elder_id == user.id, m.Notification.day == day,
                m.Notification.sent_at.is_(None), m.Notification.cancel_if_done.is_(True))).scalars():
            n.cancelled = True
        # 공유 범위 '전체'인 보호자에게만 "오늘 운동했어요" 한 줄
        alert_guardians(db, c, user, "daily_done", {"text": "오늘 운동했어요"}, FULL, "오늘 운동했어요")

    profile = _elder_profile(db, user)
    history = build_history(db, user.id, day)
    praise = completion_message(c.engines.induction, induction_profile(db, profile), history, day)
    record_message_use(db, user.id, day, praise)
    cheer = db.execute(select(m.Cheer).where(m.Cheer.elder_id == user.id, m.Cheer.played_at.is_(None))
                       .order_by(m.Cheer.id.desc())).scalars().first()
    cheer_out = None
    if cheer is not None:
        cheer.played_at = c.clock.now()
        cheer_out = {"from": db.get(m.User, cheer.guardian_id).name, "text": cheer.text, "audio_url": cheer.audio_url}
    return {"message": praise.text, "slow_recovery": s.slow_recovery, "cheer": cheer_out,
            "rewards": today_rewards(db, user.id, day)}


@router.post("/emergency")
def emergency(body: EmergencyIn, user: m.User = Depends(elder_user), db: Session = Depends(get_db),
              c: AppContext = Depends(ctx)):
    """단말 응급 흐름(5-4)의 결과: 아니에요·무응답·119 발신. 모든 연결 보호자에게 전화+푸시."""
    location = body.location if has_consent(db, user.id, "location") else None
    c.engines.safety(db, user.id).record("emergency_report", {
        "code": body.code, "severe": body.severe, "snapshot": body.snapshot,
        "location_sent": location is not None})
    text = "119 연결이 필요할 수 있어요. 바로 확인해 주세요." if body.severe else "운동 중 몸이 불편하다고 하셨어요. 연락해 보세요."
    n = alert_guardians(db, c, user, "emergency", {"code": body.code, "severe": body.severe,
                                                   "snapshot": body.snapshot},
                        ALL_SCOPES, text, location=location, call=True)
    return {"guardians_alerted": n, "location_sent": location is not None}


@router.get("/week")
def week(user: m.User = Depends(elder_user), db: Session = Depends(get_db), c: AppContext = Depends(ctx)):
    day = c.clock.today()
    history = build_history(db, user.id, day)
    days = []
    for d in days_back(day, 7):
        r = day_reward(history, d)
        mins = sum(s.minutes for s in history.sessions if s.day == d and s.completed)
        days.append({"date": d, "stamp": r["stamp"], "reasons": r["reasons"], "minutes": round(mins)})
    return {"days": days, "streak": streak(history, day)}


@router.get("/notifications")
def upcoming(user: m.User = Depends(elder_user), db: Session = Depends(get_db), c: AppContext = Depends(ctx)):
    """오늘 예약된 알림(유도 엔진이 정한 시각·문구, 하루 최대 2개). 앱이 기기 알림으로 걸어 둔다.
    워치(SMART-TIME PRO)가 휴대폰 알림을 진동으로 전달하므로 워치 알림도 된다. 발송·취소 기록은 dispatch_due가 맡는다."""
    day = c.clock.today()
    run_daily_for(db, c, user, day)
    rows = db.execute(select(m.Notification).where(
        m.Notification.elder_id == user.id, m.Notification.day == day, m.Notification.cancelled.is_(False),
        m.Notification.sent_at.is_(None)).order_by(m.Notification.scheduled_at)).scalars()
    return [{"id": n.id, "at": _as_aware(n.scheduled_at).isoformat(), "text": n.text, "intent": n.intent,
             "cancel_if_done": n.cancel_if_done} for n in rows]


@router.post("/notifications/{notification_id}/opened")
def opened(notification_id: int, user: m.User = Depends(elder_user), db: Session = Depends(get_db),
           c: AppContext = Depends(ctx)):
    n = db.get(m.Notification, notification_id)
    if n is None or n.elder_id != user.id:
        raise HTTPException(404, "알림을 찾을 수 없어요")
    if n.opened_at is None:
        n.opened_at = c.clock.now()
    return {"opened": True}


@router.post("/ladder/restart")
def restart(user: m.User = Depends(elder_user), db: Session = Depends(get_db)):
    """"새로 시작" 제안에 "다시 하기"를 고름. "쉬기"를 고르면 이 호출을 하지 않는다(제안이 남아 있음)."""
    p = _elder_profile(db, user)
    p.ladder_restart_pending = False
    return {"level": p.ladder_level}
