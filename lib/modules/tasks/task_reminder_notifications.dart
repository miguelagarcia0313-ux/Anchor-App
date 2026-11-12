import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class TaskReminderNotification {
  const TaskReminderNotification({
    required this.taskId,
    required this.title,
    required this.body,
    required this.scheduledAt,
  });

  final String taskId;
  final String title;
  final String body;
  final DateTime scheduledAt;

  String get payload =>
      'anchor-task-reminder:$taskId:${scheduledAt.toUtc().millisecondsSinceEpoch}';
}

abstract interface class TaskReminderNotifications {
  Future<void> initialize();

  Future<bool> reconcile(
    Iterable<TaskReminderNotification> reminders, {
    required bool requestPermission,
  });
}

class LocalTaskReminderNotifications implements TaskReminderNotifications {
  LocalTaskReminderNotifications._();

  static final instance = LocalTaskReminderNotifications._();
  static const _payloadPrefix = 'anchor-task-reminder:';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  bool _isSupported = false;

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _isSupported =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!_isSupported) return;

    final initialized = await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    if (initialized != true) {
      throw StateError('Could not initialize reminder notifications.');
    }

    tz_data.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));
  }

  @override
  Future<bool> reconcile(
    Iterable<TaskReminderNotification> reminders, {
    required bool requestPermission,
  }) async {
    await initialize();
    if (!_isSupported) return true;

    final desiredReminders = <String, TaskReminderNotification>{};
    final notificationIds = <int>{};
    for (final reminder in reminders) {
      if (!reminder.scheduledAt.isAfter(DateTime.now())) continue;
      final notificationId = _notificationId(reminder.taskId);
      if (!notificationIds.add(notificationId)) {
        throw StateError('Reminder notification ID collision.');
      }
      desiredReminders[reminder.payload] = reminder;
    }

    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      final payload = notification.payload;
      if (payload?.startsWith(_payloadPrefix) == true &&
          !desiredReminders.containsKey(payload)) {
        await _plugin.cancel(notification.id);
      }
    }

    if (desiredReminders.isEmpty) return true;
    if (requestPermission && !await _requestPermissions()) return false;

    for (final reminder in desiredReminders.values) {
      await _plugin.zonedSchedule(
        _notificationId(reminder.taskId),
        reminder.title,
        reminder.body,
        tz.TZDateTime.from(reminder.scheduledAt, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders',
            'Task reminders',
            channelDescription: 'Notifications for upcoming task reminders',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminder.payload,
      );
    }
    return true;
  }

  Future<bool> _requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  static int _notificationId(String taskId) {
    var hash = 0x811c9dc5;
    for (final codeUnit in taskId.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }
}
