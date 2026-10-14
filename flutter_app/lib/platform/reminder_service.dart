import '../core/reminders.dart';

abstract class ReminderService {
  Future<bool> requestPermission();
  Future<void> replace(List<ScheduledReminder> reminders);
  Future<void> cancelAll();
}

class NoopReminderService implements ReminderService {
  const NoopReminderService();
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> replace(List<ScheduledReminder> reminders) async {}
  @override
  Future<void> cancelAll() async {}
}

class UnavailableReminderService extends NoopReminderService {
  const UnavailableReminderService();
  @override
  Future<bool> requestPermission() async =>
      throw StateError('Reminder service unavailable');
}
