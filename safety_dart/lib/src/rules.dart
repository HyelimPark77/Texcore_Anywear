import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

class RuleError implements Exception {
  final String message;
  RuleError(this.message);
  @override
  String toString() => 'RuleError: $message';
}

/// Python json.dumps(sort_keys=True, separators=(",", ":"), ensure_ascii=False)와 같은 표현.
/// 서버가 계산한 번들 해시를 단말에서 다시 계산해 맞춰 보기 위해 쓴다.
String canonicalJson(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonicalJson(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(canonicalJson).join(',')}]';
  if (v is double && v == v.truncateToDouble() && v.isFinite) {
    return '${v.toInt()}.0';
  }
  return jsonEncode(v);
}

/// 서버 /rules/safety 에서 받은 규칙 번들. 판정 수치는 전부 여기서 온다.
class RuleBundle {
  final Map<String, dynamic> data;
  final String version;
  final String sha256;

  RuleBundle._(this.data, this.version, this.sha256);

  bool get approved => data['meta']['status'] == 'approved';

  dynamic operator [](String key) => data[key];

  factory RuleBundle.fromMap(Map<String, dynamic> data, {bool requireApproved = false}) {
    validate(data);
    if (requireApproved && data['meta']['status'] != 'approved') {
      throw RuleError('rule bundle ${data['meta']['version']} is not approved by the advisory board');
    }
    final hash = sha256Of(data);
    return RuleBundle._(data, data['meta']['version'].toString(), hash);
  }

  /// 서버 응답 {version, sha256, rules}. 해시가 맞지 않으면 쓰지 않는다(전송 중 손상·변조).
  factory RuleBundle.fromEnvelope(String body, {bool requireApproved = true}) {
    final env = jsonDecode(body) as Map<String, dynamic>;
    final bundle = RuleBundle.fromMap(env['rules'] as Map<String, dynamic>, requireApproved: requireApproved);
    // 서버는 규칙을 정규화 JSON 그대로 "rules": 뒤에 싣는다. 받은 글자 그대로를 해시하는 것이 가장 정확하다
    // (웹에서는 1과 1.0을 구분할 수 없어 다시 직렬화하면 해시가 달라진다).
    final raw = _rawRules(body);
    final rawHash = raw == null ? null : crypto.sha256.convert(utf8.encode(raw)).toString();
    if (rawHash != env['sha256'] && bundle.sha256 != env['sha256']) {
      throw RuleError('bundle hash mismatch: ${bundle.sha256} != ${env['sha256']}');
    }
    return RuleBundle._(bundle.data, bundle.version, env['sha256'] as String);
  }

  static String? _rawRules(String body) {
    const key = '"rules":';
    final i = body.indexOf(key);
    final end = body.lastIndexOf('}');
    if (i < 0 || end <= i) return null;
    return body.substring(i + key.length, end).trim();
  }

  static String sha256Of(Map<String, dynamic> data) =>
      crypto.sha256.convert(utf8.encode(canonicalJson(data))).toString();
}

void _require(bool cond, String msg) {
  if (!cond) throw RuleError(msg);
}

const _lights = {'GREEN', 'YELLOW', 'RED'};

void _checkBands(String name, List bands) {
  _require(bands.isNotEmpty, '$name: no bands');
  _require(bands.first['lower'] == null, '$name: first band must start at null (-inf)');
  _require(bands.last['upper'] == null, '$name: last band must end at null (+inf)');
  for (var i = 1; i < bands.length; i++) {
    final prev = bands[i - 1], cur = bands[i];
    _require(prev['upper'] != null && prev['upper'] == cur['lower'], '$name: gap or overlap between $prev and $cur');
  }
  for (final b in bands) {
    _require(_lights.contains(b['light']), '$name: bad light ${b['light']}');
    _require((b['code'] ?? '') != '', '$name: band without code');
    if (b['lower'] != null && b['upper'] != null) {
      _require((b['lower'] as num) < (b['upper'] as num), '$name: empty band $b');
    }
  }
}

/// Python rules.validate()와 같은 검사. 단말도 번들을 받을 때 다시 검사한다.
void validate(Map<String, dynamic> d) {
  for (final key in ['meta', 'hard_gate', 'plausibility', 'source_grades', 'low_grade_green', 'precheck', 'allowance', 'session', 'post', 'emergency']) {
    _require(d.containsKey(key), 'missing section: $key');
  }
  _require((d['meta']['version'] ?? '') != '', 'meta.version required');
  _require(['draft', 'approved'].contains(d['meta']['status']), 'meta.status must be draft|approved');
  if (d['meta']['status'] == 'approved') {
    _require((d['meta']['approved_by'] as List? ?? []).isNotEmpty, 'approved bundle needs approved_by');
  }
  // B 등급의 '초록'은 안전 근거가 아니므로 초록으로 둘 수 없다
  for (final kind in ['blood_pressure', 'heart_rate']) {
    _require(['YELLOW', 'REMEASURE', 'RED'].contains(d['low_grade_green'][kind]['light']), 'low_grade_green.$kind: must not be GREEN');
  }
  final pre = d['precheck'];
  for (final metric in ['systolic', 'diastolic', 'resting_hr']) {
    _checkBands(metric, pre['bands'][metric] as List);
    final p = d['plausibility'][metric];
    _require((p['min'] as num) < (p['max'] as num), 'plausibility.$metric: min >= max');
  }
  final flat = [...pre['emergency_symptoms'], ...pre['red_symptoms'], ...pre['yellow_symptoms']];
  _require(flat.length == flat.toSet().length, 'precheck symptom lists overlap');
  _require((pre['red_conditions'] as List).toSet().intersection((pre['yellow_conditions'] as List).toSet()).isEmpty,
      'condition lists overlap');

  final s = d['session'];
  final cp = s['ceiling_pct'];
  _require(0 < cp['initial'] && cp['initial'] <= cp['escalated'] && cp['escalated'] <= cp['absolute_max'] && cp['absolute_max'] <= 0.85,
      'ceiling_pct must satisfy initial <= escalated <= absolute_max <= 0.85');
  _require(s['zone_pct']['lower'] < s['zone_pct']['upper'], 'zone_pct lower >= upper');
  _require(s['rpe']['step_down_at'] < s['rpe']['stop_at'], 'rpe step_down_at must be < stop_at');
  _require(s['stop_ratio_over_ceiling'] > 1.0, 'stop_ratio_over_ceiling must be > 1');
  _require(s['sensor']['fallback_checkin_interval_seconds'] <= s['checkin_interval_seconds'],
      'sensor fallback must ask at least as often as normal check-in');
  for (final g in ['A', 'B', 'C']) {
    _require((s['heart_rate_grades'] as Map).containsKey(g), 'session.heart_rate_grades.$g missing');
  }
  for (final l in ['GREEN', 'YELLOW', 'RED']) {
    _require((d['allowance'] as Map).containsKey(l), 'allowance.$l missing');
  }
  _require(d['allowance']['RED']['allowed'] == false, 'RED must never allow exercise');
  final cap = d['allowance']['YELLOW']['hr_ceiling_pct_cap'];
  if (cap != null) _require(cap <= cp['initial'], 'YELLOW hr cap must not exceed initial ceiling');
}
