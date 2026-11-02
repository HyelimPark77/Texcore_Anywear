"""어르신 본인: 동의, 건강 정보, 설정, 보호자 공유 범위. 알림·데이터 공유·삭제는 어르신이 직접 통제한다(8장)."""
import re
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from safety_engine.precheck import gate_reasons

from .. import models as m
from ..deps import AppContext, ctx, elder_user, get_db
from ..engines import safety_profile
from ..services import has_consent

router = APIRouter(prefix="/me", tags=["elder"])

ConsentKind = Literal["health", "guardian_cheer_request", "manager", "location"]
Scope = Literal["emergency_only", "cheer_only", "full"]


class DoctorLimitsIn(BaseModel):
    systolic_max: int | None = Field(None, ge=80, le=220)
    diastolic_max: int | None = Field(None, ge=40, le=130)
    resting_hr_max: int | None = Field(None, ge=40, le=150)
    exercise_hr_ceiling: int | None = Field(None, ge=60, le=180)


class HealthIn(BaseModel):
    conditions: list[str] = []
    parq_risk: bool = False
    doctor_clearance: bool = False
    device: Literal["pacemaker", "icd"] | None = None
    beta_blocker: bool = False
    doctor_limits: DoctorLimitsIn = DoctorLimitsIn()


class SettingsIn(BaseModel):
    preferred_time: str = "09:00"
    anchor: str = Field("time", max_length=32)
    goal: str | None = Field(None, max_length=64)
    fall_concern: bool = False

    @field_validator("preferred_time")
    @classmethod
    def hhmm(cls, v):
        if not re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", v):
            raise ValueError("HH:MM")
        return v


class ConsentIn(BaseModel):
    kind: ConsentKind
    granted: bool


class LinkUpdate(BaseModel):
    status: Literal["active", "revoked"] | None = None
    scope: Scope | None = None


def record_consent(db, c, elder_id, actor_id, kind, granted):
    db.add(m.Consent(elder_id=elder_id, kind=kind, granted=granted, actor_id=actor_id, created_at=c.clock.now()))


def save_health(db, c, profile: m.ElderProfile, body: HealthIn):
    if not has_consent(db, profile.user_id, "health"):
        raise HTTPException(403, "건강 정보 수집 동의가 필요해요")
    health = body.model_dump()
    health["doctor_limits"] = {k: v for k, v in health["doctor_limits"].items() if v is not None}
    profile.health = health
    try:
        gate_reasons(c.engines.safety_rules, safety_profile(profile, c.clock.today()))   # 모르는 질환 이름 거부
    except ValueError as e:
        raise HTTPException(422, str(e))


def save_settings(profile: m.ElderProfile, body: SettingsIn):
    for k, v in body.model_dump().items():
        setattr(profile, k, v)


@router.get("")
def me(user: m.User = Depends(elder_user), db: Session = Depends(get_db)):
    p = db.get(m.ElderProfile, user.id)
    return {"id": user.id, "name": user.name, "birth_year": p.birth_year, "signup_date": p.signup_date,
            "proxy_setup": p.proxy_setup, "has_health": p.health is not None,
            # 본인 건강 답변: 앱이 홈에서 하드 게이트(의사 확인 필요)를 미리 보여 주고, 고칠 수 있게
            "health": p.health,
            "settings": {"preferred_time": p.preferred_time, "anchor": p.anchor, "goal": p.goal,
                         "fall_concern": p.fall_concern}}


@router.post("/consents")
def give_consent(body: ConsentIn, user: m.User = Depends(elder_user), db: Session = Depends(get_db),
                 c: AppContext = Depends(ctx)):
    # 건강 정보 동의 철회 → 이후 수집 중단. 이미 모은 정보 삭제는 DELETE /me/health-data로 따로 요청.
    record_consent(db, c, user.id, user.id, body.kind, body.granted)
    return {"kind": body.kind, "granted": body.granted}


@router.get("/consents")
def consent_history(user: m.User = Depends(elder_user), db: Session = Depends(get_db)):
    rows = db.execute(select(m.Consent).where(m.Consent.elder_id == user.id).order_by(m.Consent.id)).scalars()
    return [{"kind": r.kind, "granted": r.granted, "actor_id": r.actor_id, "at": r.created_at} for r in rows]


@router.put("/health")
def put_health(body: HealthIn, user: m.User = Depends(elder_user), db: Session = Depends(get_db),
               c: AppContext = Depends(ctx)):
    save_health(db, c, db.get(m.ElderProfile, user.id), body)
    return {"saved": True}


@router.delete("/health-data")
def delete_health_data(user: m.User = Depends(elder_user), db: Session = Depends(get_db)):
    """건강 정보·측정·운동 기록 삭제. 판정 로그는 사고 분석용 보존 대상이라 남는다(보존 기간은 법률 검토)."""
    p = db.get(m.ElderProfile, user.id)
    p.health = None
    db.execute(delete(m.ExerciseSession).where(m.ExerciseSession.elder_id == user.id))
    db.execute(delete(m.Precheck).where(m.Precheck.elder_id == user.id))
    return {"deleted": True}


@router.put("/settings")
def put_settings(body: SettingsIn, user: m.User = Depends(elder_user), db: Session = Depends(get_db)):
    save_settings(db.get(m.ElderProfile, user.id), body)
    return {"saved": True}


@router.get("/guardians")
def my_guardians(user: m.User = Depends(elder_user), db: Session = Depends(get_db)):
    links = db.execute(select(m.GuardianLink).where(m.GuardianLink.elder_id == user.id)).scalars()
    return [{"link_id": link.id, "guardian": db.get(m.User, link.guardian_id).name, "status": link.status,
             "scope": link.scope} for link in links]


@router.put("/guardians/{link_id}")
def update_guardian(link_id: int, body: LinkUpdate, user: m.User = Depends(elder_user),
                    db: Session = Depends(get_db)):
    link = db.get(m.GuardianLink, link_id)
    if link is None or link.elder_id != user.id:
        raise HTTPException(404, "연결을 찾을 수 없어요")
    if body.status:
        link.status = body.status
    if body.scope:
        link.scope = body.scope
    return {"link_id": link.id, "status": link.status, "scope": link.scope}
