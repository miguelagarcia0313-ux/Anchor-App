import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class TaskNotification {
  const TaskNotification({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.minutesBefore,
  });

  final String id;
  final String title;
  final DateTime dueAt;
  final int minutesBefore;
}

class NotificationPermissionStatus {
  const NotificationPermissionStatus({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
  });

  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
}

class TaskNotificationService {
  TaskNotificationService._();

  static final instance = TaskNotificationService._();

  static const _payloadPrefix = 'anchor_task:';
  static const _channelId = 'task_reminders';
  static const _channelName = 'Task reminders';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform) return;

    timezone_data.initializeTimeZones();
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(timezone.getLocation(localTimezone.identifier));

    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    if (initialized != true) {
      throw StateError('Unable to initialize task notifications.');
    }
    _initialized = true;
  }

  Future<NotificationPermissionStatus> requestPermissions() async {
    if (!_initialized) {
      throw StateError('Task notifications have not been initialized.');
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) {
        return const NotificationPermissionStatus(
          notificationsAllowed: false,
          exactAlarmsAllowed: false,
        );
      }
      final notificationsAllowed =
          await android.requestNotificationsPermission() ?? false;
      if (!notificationsAllowed) {
        return const NotificationPermissionStatus(
          notificationsAllowed: false,
          exactAlarmsAllowed: false,
        );
      }

      var exactAlarmsAllowed =
          await android.canScheduleExactNotifications() ?? true;
      if (!exactAlarmsAllowed) {
        await android.requestExactAlarmsPermission();
        exactAlarmsAllowed =
            await android.canScheduleExactNotifications() ?? false;
      }
      return NotificationPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: exactAlarmsAllowed,
      );
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final notificationsAllowed =
        await ios?.requestPermissions(alert: true, sound: true) ?? false;
    return NotificationPermissionStatus(
      notificationsAllowed: notificationsAllowed,
      exactAlarmsAllowed: true,
    );
  }

  Future<void> synchronize(Iterable<TaskNotification> reminders) async {
    if (!_initialized) return;

    final reminderList = reminders.toList();
    final reminderIds = reminderList.map(_notificationId).toSet();
    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.payload?.startsWith(_payloadPrefix) == true &&
          !reminderIds.contains(notification.id)) {
        await _plugin.cancel(id: notification.id);
      }
    }

    var exactAlarmsAllowed = true;
    if (defaultTargetPlatform == TargetPlatform.android) {
      exactAlarmsAllowed =
          await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.canScheduleExactNotifications() ??
          true;
    }
    for (final reminder in reminderList) {
      final id = _notificationId(reminder);
      final notificationAt = reminder.dueAt.toLocal().subtract(
        Duration(minutes: reminder.minutesBefore),
      );
      if (!notificationAt.isAfter(DateTime.now())) {
        await _plugin.cancel(id: id);
        continue;
      }

      await _plugin.zonedSchedule(
        id: id,
        title: reminder.title,
        body: 'Due in ${_durationLabel(reminder.minutesBefore)}.',
        scheduledDate: timezone.TZDateTime.from(notificationAt, timezone.local),
        payload: '$_payloadPrefix${reminder.id}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Notifications for upcoming tasks and reminders',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: exactAlarmsAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  int _notificationId(TaskNotification reminder) {
    var hash = 0x811c9dc5;
    for (final codeUnit in reminder.id.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  String _durationLabel(int minutes) => switch (minutes) {
    60 => '1 hour',
    120 => '2 hours',
    1440 => '1 day',
    10080 => '1 week',
    _ => '$minutes minutes',
  };

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}
