// 운동 중 심박 출처. 지금은 PC의 watch_bridge.py(디즈먼트 워치 ↔ 블루투스)에서 받는다.
// 안드로이드 에뮬레이터는 PC의 블루투스로 실제 워치에 붙을 수 없어서, PC가 받은 심박을 네트워크로 넘겨받는다.
// 실기기에서는 같은 자리에 블루투스 직접 연결(또는 Health Connect) 구현을 끼운다.
// Diz-SW01은 표준 심박 서비스가 없어(PoC-0 inspect 결과) 실기기에서는 건강 앱 경유(A안)를 쓴다: HealthHeartRateSource.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class HrSample {
  final int bpm;
  final DateTime at;
  final int? battery;
  const HrSample(this.bpm, this.at, {this.battery});
}

abstract class HeartRateSource {
  /// 안전 엔진 센서 등급. 디즈먼트 워치 = B(경고용).
  String get grade;
  String get name;
  bool get connected;

  /// 초 단위로 들어오는 실시간 심박인가. false(건강 앱 경유처럼 몇 분 늦게 오는 값)면
  /// 운동 중 안전 판정에 쓰지 않고 홈 화면에 '최근 심박'으로만 보인다.
  bool get realtime;
  Stream<HrSample> get samples;
  Stream<String> get status; // 화면에 보일 상태 문장
  Future<void> connect();
  Future<void> close();
}

/// PC의 watch_bridge.py 에 WebSocket으로 붙는다. 에뮬레이터에서 PC는 10.0.2.2.
class BridgeHeartRateSource implements HeartRateSource {
  final String url;
  final WebSocketChannel Function(Uri) _open;
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  final _samples = StreamController<HrSample>.broadcast();
  final _status = StreamController<String>.broadcast();
  bool _connected = false;

  BridgeHeartRateSource(this.url, {WebSocketChannel Function(Uri)? open})
      : _open = open ?? WebSocketChannel.connect;

  @override
  String get grade => 'B';
  @override
  String get name => '디즈먼트 워치';
  @override
  bool get connected => _connected;
  @override
  bool get realtime => true;
  @override
  Stream<HrSample> get samples => _samples.stream;
  @override
  Stream<String> get status => _status.stream;

  static const _ko = {
    'connected': '워치 연결됨',
    'connecting': '워치에 연결하는 중',
    'scanning': '워치 찾는 중',
    'not_found': '워치를 못 찾았어요',
    'disconnected': '워치 연결이 끊겼어요',
    'error': '워치 연결 오류',
    'no_heart_rate_service': '이 워치는 표준 심박 서비스가 없어요',
    'starting': '준비 중',
  };

  @override
  Future<void> connect() async {
    await close();
    _status.add('PC 워치 브리지에 연결하는 중');
    final ch = _open(Uri.parse(url));
    _ch = ch;
    try {
      await ch.ready;
    } catch (_) {
      _ch = null;
      _status.add('PC 워치 브리지에 연결하지 못했어요. PC에서 watch_bridge.py serve 를 먼저 실행하세요.');
      rethrow;
    }
    _connected = true;
    _sub = ch.stream.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed());
  }

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (m['type'] == 'hr' && m['bpm'] is num) {
      _samples.add(HrSample((m['bpm'] as num).round(), DateTime.now(), battery: m['battery'] as int?));
    } else if (m['type'] == 'status') {
      _status.add(_ko[m['state']] ?? '${m['state']}');
    }
  }

  void _onClosed() {
    if (!_connected) return;
    _connected = false;
    _status.add('PC 워치 브리지 연결이 끊겼어요');
  }

  @override
  Future<void> close() async {
    _connected = false;
    await _sub?.cancel();
    _sub = null;
    await _ch?.sink.close();
    _ch = null;
  }
}

/// 건강 앱에서 [from, to) 사이 심박 기록을 읽는다. 실제 구현은 health_reader.dart(아이폰 건강 앱 / Health Connect).
typedef HrReader = Future<List<HrSample>> Function(DateTime from, DateTime to);

/// 건강 앱 경유(A안): 워치 → SMART-TIME PRO → 건강 앱 → 여기.
/// SMART-TIME PRO가 동기화할 때만 값이 들어와 몇 분씩 늦다. 그래서 realtime=false — 운동 중 판정에는 쓰지 않는다.
class HealthHeartRateSource implements HeartRateSource {
  final Future<bool> Function() authorize;
  final HrReader read;
  final Duration pollEvery;
  final Duration lookBack;
  final DateTime Function() _now;
  final _samples = StreamController<HrSample>.broadcast();
  final _status = StreamController<String>.broadcast();
  Timer? _timer;
  DateTime? _lastAt;
  bool _connected = false;

  HealthHeartRateSource({
    required this.authorize,
    required this.read,
    this.pollEvery = const Duration(minutes: 1),
    this.lookBack = const Duration(hours: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  @override
  String get grade => 'B';
  @override
  String get name => '디즈먼트 워치(건강 앱)';
  @override
  bool get connected => _connected;
  @override
  bool get realtime => false;
  @override
  Stream<HrSample> get samples => _samples.stream;
  @override
  Stream<String> get status => _status.stream;

  @override
  Future<void> connect() async {
    await close();
    _status.add('건강 앱 권한 확인 중');
    if (!await authorize()) {
      _status.add('건강 앱 심박 읽기를 허용해 주세요');
      throw StateError('health permission denied');
    }
    _connected = true;
    await poll();
    _timer = Timer.periodic(pollEvery, (_) => poll());
  }

  /// 새로 들어온 기록 중 가장 최근 것 하나만 내보낸다(이미 보낸 것보다 새것일 때만).
  Future<void> poll() async {
    if (!_connected) return;
    final to = _now();
    final List<HrSample> got;
    try {
      got = await read(_lastAt ?? to.subtract(lookBack), to);
    } catch (_) {
      _status.add('건강 앱에서 심박을 읽지 못했어요');
      return;
    }
    final fresh = got.where((s) => _lastAt == null || s.at.isAfter(_lastAt!)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (fresh.isEmpty) {
      if (_lastAt == null) _status.add('건강 앱에 최근 심박이 없어요. SMART-TIME PRO를 열어 동기화해 주세요');
      return;
    }
    _lastAt = fresh.last.at;
    _samples.add(fresh.last);
  }

  @override
  Future<void> close() async {
    _connected = false;
    _timer?.cancel();
    _timer = null;
  }
}
