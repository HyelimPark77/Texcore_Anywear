// 운동 알림(6-3): 서버 유도 엔진이 정한 오늘 알림(하루 최대 2개, 07~20시, 앵커 시각)을 기기 알림으로 건다.
// 디즈먼트 워치는 SMART-TIME PRO가 휴대폰 알림을 진동으로 전달하므로, 기기 알림이 곧 워치 알림이다(W4).
// 발송·무시 기록은 서버가 맡고(dispatch_due), 앱은 누른 알림만 알린다(POST /me/notifications/{id}/opened).
import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Reminder {
  final int id;
  final DateTime at;
  final String text;
  final bool cancelIfDone;
  const Reminder(this.id, this.at, this.text, {this.cancelIfDone = true});

  factory Reminder.fromJson(Map<String, dynamic> j) =>
      Reminder(j['id'] as int, DateTime.parse(j['at'] as String), j['text'] as String, cancelIfDone: j['cancel_if_done'] != false);
}

abstract class Reminders {
  /// 알림 허락 묻기. 허락하지 않으면 false(앱은 그대로 쓸 수 있다).
  Future<bool> requestPermission();

  /// 걸려 있던 오늘 알림을 지우고 [items] 중 아직 오지 않은 것만 다시 건다.
  Future<void> replace(List<Reminder> items);

  /// 오늘 운동을 마쳤으면 '했으면 안 보내는' 알림을 지운다.
  Future<void> cancelDone();

  /// 어르신이 누른 알림 번호.
  Stream<int> get opened;
}

class PlatformReminders implements Reminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _opened = StreamController<int>.broadcast();
  final _scheduled = <Reminder>[];
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestSoundPermission: false, requestBadgePermission: false),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = int.tryParse(r.payload ?? '');
        if (id != null) _opened.add(id);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final id = int.tryParse(launch?.notificationResponse?.payload ?? '');
    if (launch?.didNotificationLaunchApp == true && id != null) scheduleMicrotask(() => _opened.add(id));
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true, badge: false) ??
        await android?.requestNotificationsPermission() ??
        false;
  }

  static const _details = NotificationDetails(
    iOS: DarwinNotificationDetails(presentSound: true),
    android: AndroidNotificationDetails('exercise', '운동 알림', importance: Importance.high, priority: Priority.high),
  );

  @override
  Future<void> replace(List<Reminder> items) async {
    await _init();
    await _plugin.cancelAll();
    _scheduled.clear();
    final now = DateTime.now();
    for (final r in items.where((r) => r.at.isAfter(now))) {
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: '운동친구',
        body: r.text,
        payload: '${r.id}',
      );
      _scheduled.add(r);
    }
  }

  @override
  Future<void> cancelDone() async {
    await _init();
    for (final r in _scheduled.where((r) => r.cancelIfDone).toList()) {
      await _plugin.cancel(id: r.id);
      _scheduled.remove(r);
    }
  }

  @override
  Stream<int> get opened => _opened.stream;
}
