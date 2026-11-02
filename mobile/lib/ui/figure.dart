// 동작 그림: 옆에서 본 사람 그림이 두 자세 사이를 천천히 오가며 동작을 보여 준다.
// 영상(계획서 4장, 30~60편)이 나오기 전까지 쓰는 그림이고, 영상이 생기면 Move.video 로 바꿔 끼운다.
// 자세 이름 목록은 induction/tests/test_exercise_content.py 의 POSES 와 같아야 한다.
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum Chair { none, seat, hold }

/// 120 × 160 상자 안 관절 좌표(오른쪽을 보고 선 옆모습). near = 앞쪽 팔다리, far = 뒤쪽 팔다리.
class Pose {
  final Map<String, Offset> j;
  final Chair chair;
  const Pose(this.j, this.chair);

  Pose copyWith(Map<String, Offset> changes, {Chair? chair}) => Pose({...j, ...changes}, chair ?? this.chair);
  Pose shift(Offset d) => Pose({for (final e in j.entries) e.key: e.value + d}, chair);

  static Pose lerp(Pose a, Pose b, double t) =>
      Pose({for (final k in a.j.keys) k: Offset.lerp(a.j[k], b.j[k] ?? a.j[k], t)!}, t < 0.5 ? a.chair : b.chair);
}

const _sit = Pose({
  'head': Offset(50, 30), 'neck': Offset(50, 42), 'hip': Offset(50, 90),
  'nElbow': Offset(56, 66), 'nHand': Offset(70, 84), 'fElbow': Offset(52, 66), 'fHand': Offset(66, 84),
  'nKnee': Offset(78, 92), 'nAnkle': Offset(78, 140), 'nToe': Offset(90, 142),
  'fKnee': Offset(74, 92), 'fAnkle': Offset(74, 140), 'fToe': Offset(86, 142),
}, Chair.seat);

const _stand = Pose({
  'head': Offset(50, 16), 'neck': Offset(50, 28), 'hip': Offset(50, 80),
  'nElbow': Offset(53, 54), 'nHand': Offset(56, 78), 'fElbow': Offset(48, 54), 'fHand': Offset(46, 78),
  'nKnee': Offset(52, 115), 'nAnkle': Offset(52, 148), 'nToe': Offset(64, 150),
  'fKnee': Offset(48, 115), 'fAnkle': Offset(48, 148), 'fToe': Offset(60, 150),
}, Chair.none);

final _standHold = _stand.copyWith({
  'nElbow': Offset(64, 52), 'nHand': Offset(80, 64), 'fElbow': Offset(62, 54), 'fHand': Offset(78, 66),
}, chair: Chair.hold);

final Map<String, Pose> poses = {
  'sit': _sit,
  'sit_breath_in': _sit.copyWith({'head': const Offset(49, 27), 'neck': const Offset(50, 40),
      'nElbow': const Offset(62, 62), 'nHand': const Offset(74, 72)}),
  'sit_shrug': _sit.copyWith({'nElbow': const Offset(56, 60), 'nHand': const Offset(70, 78),
      'fElbow': const Offset(52, 60), 'fHand': const Offset(66, 78), 'head': const Offset(50, 31)}),
  'sit_toes_up': _sit.copyWith({'nToe': const Offset(88, 132), 'fToe': const Offset(84, 132)}),
  'sit_knee_up': _sit.copyWith({'nKnee': const Offset(74, 74), 'nAnkle': const Offset(80, 118), 'nToe': const Offset(92, 120)}),
  'sit_knee_up_arm': _sit.copyWith({'nKnee': const Offset(74, 74), 'nAnkle': const Offset(80, 118), 'nToe': const Offset(92, 120),
      'fElbow': const Offset(62, 58), 'fHand': const Offset(74, 50), 'nElbow': const Offset(46, 64), 'nHand': const Offset(40, 80)}),
  'sit_arms_fwd': _sit.copyWith({'nElbow': const Offset(70, 48), 'nHand': const Offset(92, 48)}),
  'sit_leg_ext': _sit.copyWith({'nKnee': const Offset(78, 90), 'nAnkle': const Offset(112, 96), 'nToe': const Offset(114, 84)}),
  'sit_arms_up': _sit.copyWith({'nElbow': const Offset(56, 24), 'nHand': const Offset(58, 4),
      'fElbow': const Offset(50, 24), 'fHand': const Offset(52, 4)}),
  'sit_arms_bent': _sit.copyWith({'nElbow': const Offset(62, 50), 'nHand': const Offset(60, 34),
      'fElbow': const Offset(56, 50), 'fHand': const Offset(54, 34)}),
  'sit_squeeze': _sit.copyWith({'nElbow': const Offset(60, 70), 'nHand': const Offset(74, 92),
      'fElbow': const Offset(56, 70), 'fHand': const Offset(70, 92), 'nKnee': const Offset(76, 92)}),
  'sit_lean_fwd': _sit.copyWith({'head': const Offset(68, 38), 'neck': const Offset(62, 48),
      'nElbow': const Offset(66, 70), 'nHand': const Offset(80, 86), 'fElbow': const Offset(62, 70), 'fHand': const Offset(76, 86)}),
  'sit_reach_up': _sit.copyWith({'nElbow': const Offset(56, 22), 'nHand': const Offset(60, 2)}),
  'stand': _stand,
  'stand_lean': _stand.copyWith({'head': const Offset(57, 17), 'neck': const Offset(56, 29), 'hip': const Offset(54, 80)}),
  'stand_tandem': _stand.copyWith({'nKnee': const Offset(58, 115), 'nAnkle': const Offset(60, 148), 'nToe': const Offset(72, 150),
      'fKnee': const Offset(44, 115), 'fAnkle': const Offset(46, 148), 'fToe': const Offset(58, 150)}),
  'stand_front_chair': _stand.shift(const Offset(18, 0)).copyWith({}, chair: Chair.seat),
  'walk_a': _stand.copyWith({'nKnee': const Offset(60, 114), 'nAnkle': const Offset(68, 148), 'nToe': const Offset(80, 148),
      'fKnee': const Offset(44, 116), 'fAnkle': const Offset(34, 146), 'fToe': const Offset(44, 150),
      'nElbow': const Offset(46, 54), 'nHand': const Offset(38, 74), 'fElbow': const Offset(56, 54), 'fHand': const Offset(64, 72)}),
  'walk_b': _stand.copyWith({'fKnee': const Offset(60, 114), 'fAnkle': const Offset(68, 148), 'fToe': const Offset(80, 148),
      'nKnee': const Offset(44, 116), 'nAnkle': const Offset(34, 146), 'nToe': const Offset(44, 150),
      'fElbow': const Offset(46, 54), 'fHand': const Offset(38, 74), 'nElbow': const Offset(56, 54), 'nHand': const Offset(64, 72)}),
  'stand_hold': _standHold,
  'stand_hold_knee_up': _standHold.copyWith({'nKnee': const Offset(66, 96), 'nAnkle': const Offset(62, 128), 'nToe': const Offset(74, 130)}),
  'stand_hold_heel_up': _standHold.shift(const Offset(0, -8)).copyWith({'nToe': const Offset(64, 150), 'fToe': const Offset(60, 150)}),
  'stand_hold_lean': _standHold.copyWith({'head': const Offset(56, 17), 'neck': const Offset(55, 29), 'hip': const Offset(53, 80)}),
  'stand_hold_one_leg': _standHold.copyWith({'nKnee': const Offset(58, 112), 'nAnkle': const Offset(50, 132), 'nToe': const Offset(62, 134)}),
};

/// 두 자세를 [tempoSeconds]마다 오간다. 화면 읽기에는 [label](동작 이름)로 읽힌다.
class MoveFigure extends StatefulWidget {
  final List<String> poseNames;
  final double tempoSeconds;
  final String label;
  final bool animate;
  const MoveFigure({super.key, required this.poseNames, required this.tempoSeconds, required this.label, this.animate = true});

  @override
  State<MoveFigure> createState() => _MoveFigureState();
}

class _MoveFigureState extends State<MoveFigure> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(MoveFigure old) {
    super.didUpdateWidget(old);
    if (old.tempoSeconds != widget.tempoSeconds || old.animate != widget.animate) _sync();
  }

  void _sync() {
    _c.duration = Duration(milliseconds: (widget.tempoSeconds * 1000).round());
    // 기기 '동작 줄이기' 설정이면 움직이지 않는다
    if (widget.animate && !(WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations)) {
      _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = poses[widget.poseNames.first] ?? _sit;
    final b = poses[widget.poseNames.last] ?? a;
    final color = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      container: true,
      label: '${widget.label} 그림',
      image: true,
      child: AspectRatio(
        aspectRatio: 120 / 160,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: _FigurePainter(Pose.lerp(a, b, Curves.easeInOut.transform(_c.value)), color),
          ),
        ),
      ),
    );
  }
}

class _FigurePainter extends CustomPainter {
  final Pose pose;
  final Color color;
  _FigurePainter(this.pose, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / 120, size.height / 160);
    canvas.scale(s);
    final line = Paint()
      ..color = color
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final far = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final furniture = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final j = pose.j;

    canvas.drawLine(const Offset(4, 154), const Offset(116, 154), furniture); // 바닥
    switch (pose.chair) {
      case Chair.seat:
        canvas.drawLine(const Offset(30, 96), const Offset(72, 96), furniture);
        canvas.drawLine(const Offset(30, 96), const Offset(30, 48), furniture);
        canvas.drawLine(const Offset(32, 96), const Offset(32, 152), furniture);
        canvas.drawLine(const Offset(70, 96), const Offset(70, 152), furniture);
      case Chair.hold:
        canvas.drawLine(const Offset(82, 62), const Offset(82, 152), furniture);
        canvas.drawLine(const Offset(82, 106), const Offset(114, 106), furniture);
        canvas.drawLine(const Offset(112, 106), const Offset(112, 152), furniture);
      case Chair.none:
        break;
    }

    void limb(Paint p, List<String> ks) {
      final path = Path()..moveTo(j[ks.first]!.dx, j[ks.first]!.dy);
      for (final k in ks.skip(1)) {
        path.lineTo(j[k]!.dx, j[k]!.dy);
      }
      canvas.drawPath(path, p);
    }

    limb(far, ['hip', 'fKnee', 'fAnkle', 'fToe']);
    limb(far, ['neck', 'fElbow', 'fHand']);
    limb(line, ['neck', 'hip']);
    limb(line, ['hip', 'nKnee', 'nAnkle', 'nToe']);
    limb(line, ['neck', 'nElbow', 'nHand']);
    canvas.drawCircle(j['head']!, 10, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FigurePainter old) => old.pose != pose || old.color != color;
}
