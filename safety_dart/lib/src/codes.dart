/// 판정 결과·행동·사유 코드. 문자열 값은 Python 기준 구현(safety_engine/codes.py)과 같다.
enum Light { GREEN, YELLOW, REMEASURE, RED, BLOCKED, EMERGENCY }

/// RED가 REMEASURE보다 우선: 확실한 위험 신호가 하나라도 있으면 쉬기가 안전한 쪽.
int severity(Light l) => l.index;

Light worst(Iterable<Light> lights) =>
    lights.fold(Light.GREEN, (a, b) => severity(b) > severity(a) ? b : a);

Light lightOf(String name) => Light.values.byName(name);

enum ActionKind {
  SLOW_DOWN,
  STEP_DOWN,
  PAUSE,
  STOP,
  EMERGENCY_119,
  ASK_RPE,
  GUARDIAN_ALERT,
  LOUD_PROMPT,
  SENSOR_FALLBACK,
  SENSOR_RESTORED,
}

class Code {
  static const gateOpen = 'GATE_OPEN';
  static const gateConditionNeedsClearance = 'GATE_CONDITION_NEEDS_CLEARANCE';
  static const gateParqRisk = 'GATE_PARQ_RISK';
  static const gateDeviceNeedsHrCeiling = 'GATE_DEVICE_NEEDS_HR_CEILING';

  static const preEmergencySymptom = 'PRE_EMERGENCY_SYMPTOM';
  static const preRedSymptom = 'PRE_RED_SYMPTOM';
  static const preYellowSymptom = 'PRE_YELLOW_SYMPTOM';
  static const preRedCondition = 'PRE_RED_CONDITION';
  static const preYellowCondition = 'PRE_YELLOW_CONDITION';
  static const preMissingValue = 'PRE_MISSING_VALUE';
  static const preImplausibleValue = 'PRE_IMPLAUSIBLE_VALUE';
  static const preBpSourceNotAllowed = 'PRE_BP_SOURCE_NOT_ALLOWED';
  static const preHrSourceLowGrade = 'PRE_HR_SOURCE_LOW_GRADE';
  static const preBpSourceLowGrade = 'PRE_BP_SOURCE_LOW_GRADE';
  static const preOverDoctorLimit = 'PRE_OVER_DOCTOR_LIMIT';
  static const doctorLimitLooserIgnored = 'DOCTOR_LIMIT_LOOSER_IGNORED';

  static const hrOverCeiling = 'HR_OVER_CEILING';
  static const hrNotRecovered = 'HR_NOT_RECOVERED';
  static const hrFarOverCeiling = 'HR_FAR_OVER_CEILING';
  static const hrSuddenChange = 'HR_SUDDEN_CHANGE';
  static const rpeHard = 'RPE_HARD';
  static const rpeVeryHard = 'RPE_VERY_HARD';
  static const stopSymptom = 'STOP_SYMPTOM';
  static const emergencySymptom = 'EMERGENCY_SYMPTOM';
  static const userStop = 'USER_STOP';
  static const checkinDue = 'CHECKIN_DUE';
  static const noResponse = 'NO_RESPONSE';
  static const sensorGap = 'SENSOR_GAP';
  static const sensorImplausible = 'SENSOR_IMPLAUSIBLE';
  static const sensorOk = 'SENSOR_OK';

  static const postRecovered = 'POST_RECOVERED';
  static const postSlowRecovery = 'POST_SLOW_RECOVERY';

  static const emUserOk = 'EM_USER_OK';
  static const emUserNotOk = 'EM_USER_NOT_OK';
  static const emNoResponse = 'EM_NO_RESPONSE';
  static const emSevereSymptom = 'EM_SEVERE_SYMPTOM';
  static const em119Confirmed = 'EM_119_CONFIRMED';
  static const em119NoConfirm = 'EM_119_NO_CONFIRM';
}
