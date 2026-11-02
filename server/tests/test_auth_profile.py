from datetime import timedelta

from app import models as m


def _code(w, phone):
    return [s for s in w.gw.sent if s.channel == "sms" and s.to_phone == phone][-1].data["code"]


def test_signup_then_login_same_account(w):
    h1, uid1 = w.login("010-1111-2222")
    h2, uid2 = w.login("01011112222")
    assert uid1 == uid2
    assert w.client.get("/me", headers=h2).json()["birth_year"] == 1952
    assert "health" in w.client.get("/me", headers=h2).json()


def test_wrong_code_and_lockout(w):
    w.client.post("/auth/otp/request", json={"phone": "01055556666"})
    good = _code(w, "01055556666")
    for _ in range(5):
        r = w.client.post("/auth/otp/verify", json={"phone": "01055556666", "code": "000000" if good != "000000" else "111111",
                                                     "role": "elder", "name": "a", "birth_year": 1950})
        assert r.status_code == 400
    r = w.client.post("/auth/otp/verify", json={"phone": "01055556666", "code": good, "role": "elder", "name": "a",
                                                 "birth_year": 1950})
    assert r.status_code == 400   # 5회 틀리면 그 코드는 못 씀


def test_code_expires(w):
    w.client.post("/auth/otp/request", json={"phone": "01055556666"})
    code = _code(w, "01055556666")
    w.clock.set(w.clock.now() + timedelta(minutes=4))
    r = w.client.post("/auth/otp/verify", json={"phone": "01055556666", "code": code, "role": "elder", "name": "a",
                                                 "birth_year": 1950})
    assert r.status_code == 400


def test_signup_needs_name_role_and_birth_year(w):
    w.client.post("/auth/otp/request", json={"phone": "01055556666"})
    r = w.client.post("/auth/otp/verify", json={"phone": "01055556666", "code": _code(w, "01055556666")})
    assert r.status_code == 422


def test_roles_enforced(w):
    g, _ = w.login("01033334444", role="guardian", name="딸")
    assert w.client.get("/me/today", headers=g).status_code == 403
    e, _ = w.login("01011112222")
    assert w.client.get("/guardian/elders", headers=e).status_code == 403
    assert w.client.get("/admin/users", headers=e).status_code == 403
    assert w.client.get("/me/today").status_code == 401
    assert w.client.get("/me/today", headers={"Authorization": "Bearer nope"}).status_code == 401


def test_health_requires_consent_and_known_conditions(w):
    h, _ = w.login("01011112222")
    assert w.client.put("/me/health", json={}, headers=h).status_code == 403
    w.client.post("/me/consents", json={"kind": "health", "granted": True}, headers=h)
    assert w.client.put("/me/health", json={"conditions": ["angina"]}, headers=h).status_code == 422
    assert w.client.put("/me/health", json={"conditions": ["recent_stroke"]}, headers=h).status_code == 200
    # 동의 철회 → 측정도 받지 않음
    w.client.post("/me/consents", json={"kind": "health", "granted": False}, headers=h)
    r = w.client.post("/me/prechecks", json={"systolic": 130, "diastolic": 80, "resting_hr": 70}, headers=h)
    assert r.status_code == 403
    history = w.client.get("/me/consents", headers=h).json()
    assert [c["granted"] for c in history] == [True, False]


def test_precheck_before_health_profile(w):
    h, _ = w.login("01011112222")
    w.client.post("/me/consents", json={"kind": "health", "granted": True}, headers=h)
    r = w.client.post("/me/prechecks", json={"systolic": 130, "diastolic": 80, "resting_hr": 70}, headers=h)
    assert r.status_code == 409


def test_delete_health_data_keeps_decision_log(w):
    h, uid = w.elder()
    w.exercise(h)
    assert w.client.delete("/me/health-data", headers=h).status_code == 200
    with w.ctx.sessionmaker() as db:
        assert db.get(m.ElderProfile, uid).health is None
        assert db.query(m.Precheck).filter_by(elder_id=uid).count() == 0
        assert db.query(m.ExerciseSession).filter_by(elder_id=uid).count() == 0
        assert db.query(m.DecisionLogRow).filter_by(user_id=uid).count() > 0

