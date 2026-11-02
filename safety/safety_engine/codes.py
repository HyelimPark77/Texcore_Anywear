"""판정 결과·행동·사유 코드.

사유 코드는 로그·분쟁 분석용 고정 식별자다. 화면 문구는 여기 두지 않고
UI 문구 풀(발주사 검수)에서 코드로 찾아 쓴다.
"""
from enum import Enum


class Light(str, Enum):
    """운동 전 판정 결과. SEVERITY가 클수록 우선한다."""
    GREEN = "GREEN"            # 계획대로
    YELLOW = "YELLOW"          # 저강도·시간 단축
    REMEASURE = "REMEASURE"    # 판정 불가, 다시 재기
    RED = "RED"                # 오늘은 쉬기
    BLOCKED = "BLOCKED"        # 하드 게이트: 의사 확인 전 운동 기능 잠금
    EMERGENCY = "EMERGENCY"    # 119 안내 화면


# RED가 REMEASURE보다 우선: 확실한 위험 신호가 하나라도 있으면 "쉬기"가 안전한 쪽이다.
SEVERITY = {
    Light.GREEN: 0,
    Light.YELLOW: 1,
    Light.REMEASURE: 2,
    Light.RED: 3,
    Light.BLOCKED: 4,
    Light.EMERGENCY: 5,
}


def worst(lights):
    return max(lights, key=SEVERITY.__getitem__, default=Light.GREEN)


class ActionKind(str, Enum):
    """운동 중 모니터가 앱에 내리는 행동."""
    SLOW_DOWN = "SLOW_DOWN"              # "천천히 하세요", 강도 한 단계 낮춤
    STEP_DOWN = "STEP_DOWN"              # 강도 한 단계 낮춤(RPE·센서 오류)
    PAUSE = "PAUSE"                      # 일시정지, 앉아서 휴식, 재개 여부 질문
    STOP = "STOP"                        # 즉시 중단 → 응급 흐름(괜찮으세요?)
    EMERGENCY_119 = "EMERGENCY_119"      # 즉시 중단 → 119 화면
    ASK_RPE = "ASK_RPE"                  # "숨이 차세요? 말은 하실 수 있나요?"
    GUARDIAN_ALERT = "GUARDIAN_ALERT"    # 보호자 알림
    LOUD_PROMPT = "LOUD_PROMPT"          # 큰 소리 안내
    SENSOR_FALLBACK = "SENSOR_FALLBACK"  # 심박 끊김: 확인 질문 늘림
    SENSOR_RESTORED = "SENSOR_RESTORED"


class Code:
    # 하드 게이트
    GATE_OPEN = "GATE_OPEN"
    GATE_CONDITION_NEEDS_CLEARANCE = "GATE_CONDITION_NEEDS_CLEARANCE"
    GATE_PARQ_RISK = "GATE_PARQ_RISK"
    GATE_DEVICE_NEEDS_HR_CEILING = "GATE_DEVICE_NEEDS_HR_CEILING"

    # 운동 전
    PRE_EMERGENCY_SYMPTOM = "PRE_EMERGENCY_SYMPTOM"
    PRE_RED_SYMPTOM = "PRE_RED_SYMPTOM"
    PRE_YELLOW_SYMPTOM = "PRE_YELLOW_SYMPTOM"
    PRE_RED_CONDITION = "PRE_RED_CONDITION"
    PRE_YELLOW_CONDITION = "PRE_YELLOW_CONDITION"
    PRE_MISSING_VALUE = "PRE_MISSING_VALUE"
    PRE_IMPLAUSIBLE_VALUE = "PRE_IMPLAUSIBLE_VALUE"
    PRE_BP_SOURCE_NOT_ALLOWED = "PRE_BP_SOURCE_NOT_ALLOWED"
    PRE_HR_SOURCE_LOW_GRADE = "PRE_HR_SOURCE_LOW_GRADE"
    PRE_BP_SOURCE_LOW_GRADE = "PRE_BP_SOURCE_LOW_GRADE"
    PRE_OVER_DOCTOR_LIMIT = "PRE_OVER_DOCTOR_LIMIT"
    DOCTOR_LIMIT_LOOSER_IGNORED = "DOCTOR_LIMIT_LOOSER_IGNORED"
    # 밴드 코드(PRE_SBP_OK 등)는 규칙 파일에 정의

    # 운동 중
    HR_OVER_CEILING = "HR_OVER_CEILING"
    HR_NOT_RECOVERED = "HR_NOT_RECOVERED"
    HR_FAR_OVER_CEILING = "HR_FAR_OVER_CEILING"
    HR_SUDDEN_CHANGE = "HR_SUDDEN_CHANGE"
    RPE_HARD = "RPE_HARD"
    RPE_VERY_HARD = "RPE_VERY_HARD"
    STOP_SYMPTOM = "STOP_SYMPTOM"
    EMERGENCY_SYMPTOM = "EMERGENCY_SYMPTOM"
    USER_STOP = "USER_STOP"
    CHECKIN_DUE = "CHECKIN_DUE"
    NO_RESPONSE = "NO_RESPONSE"
    SENSOR_GAP = "SENSOR_GAP"
    SENSOR_IMPLAUSIBLE = "SENSOR_IMPLAUSIBLE"
    SENSOR_OK = "SENSOR_OK"

    # 운동 후
    POST_RECOVERED = "POST_RECOVERED"
    POST_SLOW_RECOVERY = "POST_SLOW_RECOVERY"

    # 응급 흐름
    EM_USER_OK = "EM_USER_OK"
    EM_USER_NOT_OK = "EM_USER_NOT_OK"
    EM_NO_RESPONSE = "EM_NO_RESPONSE"
    EM_SEVERE_SYMPTOM = "EM_SEVERE_SYMPTOM"
    EM_119_CONFIRMED = "EM_119_CONFIRMED"
    EM_119_NO_CONFIRM = "EM_119_NO_CONFIRM"
