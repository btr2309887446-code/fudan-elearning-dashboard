import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../core/reminders.dart';
import '../core/tasks.dart';
import 'reminder_service.dart';

class IosReminderService implements ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  void Function(String day)? onOpen;
  String? initialDay;
  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final day = response.payload;
        if (day != null && parseDayKey(day) != null) onOpen?.call(day);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      initialDay = launch?.notificationResponse?.payload;
    }
  }

  @override
  Future<bool> requestPermission() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true) ??
      false;
  @override
  Future<void> replace(List<ScheduledReminder> reminders) async {
    await _plugin.cancelAll();
    final location = tz.getLocation('Asia/Shanghai');
    for (final reminder in reminders) {
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        scheduledDate: tz.TZDateTime.from(reminder.at, location),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(
            threadIdentifier: 'assignment-deadlines',
            presentBanner: true,
            presentList: true,
            presentAlert: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: reminder.day,
      );
    }
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
