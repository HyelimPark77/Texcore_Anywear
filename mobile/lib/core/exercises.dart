// 운동 콘텐츠: assets/exercises.json 을 읽어 세션 시간을 '준비 → 본 운동 → 마무리' 동작 순서로 나눈다.
// 어떤 운동을 할지는 서버 유도 엔진이 정하고(activity id), 여기서는 그 운동을 어떻게 안내할지만 정한다.
// 콘텐츠 문구 검사·동작 제한(앉은 운동엔 앉은 동작만)은 induction/tests/test_exercise_content.py.
import 'dart:convert';

class Move {
  final String id, name, caution;
  final bool seated, supported;
  final int seconds;
  final List<String> poses, how, cues;
  final double tempoSeconds;
  final String? video;

  const Move({
    required this.id,
    required this.name,
    required this.caution,
    required this.seated,
    required this.supported,
    required this.seconds,
    required this.poses,
    required this.how,
    required this.cues,
    required this.tempoSeconds,
    this.video,
  });

  factory Move.fromJson(String id, Map<String, dynamic> j) => Move(
        id: id,
        name: j['name'] as String,
        caution: j['caution'] as String,
        seated: j['seated'] as bool,
        supported: j['supported'] as bool,
        seconds: j['seconds'] as int,
        poses: List<String>.from(j['poses'] as List),
        how: List<String>.from(j['how'] as List),
        cues: List<String>.from(j['cues'] as List),
        tempoSeconds: (j['tempo_seconds'] as num).toDouble(),
        video: j['video'] as String?,
      );
}

enum Phase { warmup, main, cooldown }

const phaseNames = {Phase.warmup: '몸 풀기', Phase.main: '본 운동', Phase.cooldown: '마무리'};
// 받침에 맞춘 안내 문장("본 운동이에요" / "마무리예요")
const phaseIntros = {Phase.warmup: '이제 몸 풀기예요. ', Phase.main: '이제 본 운동이에요. ', Phase.cooldown: '이제 마무리예요. '};

/// 세션 안의 한 구간: [start, start+seconds) 초 동안 [move]를 한다.
class Segment {
  final Move move;
  final Phase phase;
  final int start, seconds;
  const Segment(this.move, this.phase, this.start, this.seconds);
  int get end => start + seconds;
}

class ExerciseLibrary {
  final String version;
  final int cueEverySeconds;
  final Map<String, Move> moves;
  final Map<String, Map<Phase, List<String>>> activities;

  /// 운동 이름(유도 엔진 activities 의 name 과 같다).
  final Map<String, String> activityNames;

  ExerciseLibrary(this.version, this.cueEverySeconds, this.moves, this.activities, this.activityNames);

  /// 그 운동의 본 운동 첫 동작(결과 화면 미리 보기용).
  Move? firstMainMove(String activityId) {
    final ids = activities[activityId]?[Phase.main];
    return ids == null || ids.isEmpty ? null : moves[ids.first];
  }

  factory ExerciseLibrary.parse(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    final moves = {
      for (final e in (j['moves'] as Map<String, dynamic>).entries) e.key: Move.fromJson(e.key, e.value as Map<String, dynamic>),
    };
    final activities = {
      for (final e in (j['activities'] as Map<String, dynamic>).entries)
        e.key: {
          for (final p in Phase.values) p: List<String>.from((e.value as Map<String, dynamic>)[p.name] as List),
        },
    };
    final names = {
      for (final e in (j['activities'] as Map<String, dynamic>).entries) e.key: (e.value as Map<String, dynamic>)['name'] as String,
    };
    return ExerciseLibrary(j['version'] as String, j['cue_every_seconds'] as int, moves, activities, names);
  }

  /// 총 [totalSeconds]를 동작 순서로 나눈다.
  /// 3분 이상이면 몸 풀기·마무리를 각각 전체의 약 1/6(30~90초)씩 두고, 본 운동은 동작을 돌아가며 채운다.
  /// 그보다 짧은 세션('더 쉬운 걸로' 1분 등)은 본 운동 첫 동작만 한다.
  List<Segment> plan(String activityId, int totalSeconds) {
    final a = activities[activityId];
    if (a == null || totalSeconds <= 0) return const [];
    final main = [for (final id in a[Phase.main]!) moves[id]!];
    if (totalSeconds < 180) return [Segment(main.first, Phase.main, 0, totalSeconds)];

    final edge = (totalSeconds ~/ 6).clamp(30, 90);
    final out = <Segment>[];
    var t = 0;
    void fill(Phase phase, List<Move> pool, int budget, {required bool cycle}) {
      final end = t + budget;
      var i = 0;
      while (t < end && (cycle || i < pool.length)) {
        final m = pool[i % pool.length];
        var len = m.seconds.clamp(1, end - t);
        if (end - (t + len) < 20) len = end - t; // 20초 미만 자투리는 앞 동작에 붙인다
        out.add(Segment(m, phase, t, len));
        t += len;
        i++;
      }
      // 몸 풀기·마무리 동작이 예산보다 짧으면 마지막 동작을 늘린다
      if (t < end && out.isNotEmpty) {
        final last = out.removeLast();
        out.add(Segment(last.move, last.phase, last.start, last.seconds + end - t));
        t = end;
      }
    }

    fill(Phase.warmup, [for (final id in a[Phase.warmup]!) moves[id]!], edge, cycle: false);
    fill(Phase.main, main, totalSeconds - 2 * edge, cycle: true);
    fill(Phase.cooldown, [for (final id in a[Phase.cooldown]!) moves[id]!], edge, cycle: false);
    return out;
  }
}

/// 지금 [elapsed]초에 해당하는 구간 번호. 끝났으면 마지막 구간.
int segmentAt(List<Segment> plan, int elapsed) {
  for (var i = 0; i < plan.length; i++) {
    if (elapsed < plan[i].end) return i;
  }
  return plan.length - 1;
}
