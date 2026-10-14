import 'package:flutter/services.dart';
import '../core/tasks.dart';

enum CalendarResult { saved, cancelled, denied, unavailable }

abstract class CalendarService {
  Future<CalendarResult> add(LearningTask task);
}

class IosCalendarService implements CalendarService {
  static const _channel = MethodChannel('cn.edu.fudan.elearning/calendar');
  @override
  Future<CalendarResult> add(LearningTask task) async {
    if (task.dueAt == null) return CalendarResult.unavailable;
    try {
      final result = await _channel.invokeMethod<String>('add', {
        'title': '作业截止：${task.title}',
        'course': task.courseName,
        'due': task.dueAt!.millisecondsSinceEpoch / 1000,
        'url': task.url,
      });
      return CalendarResult.values.firstWhere(
        (value) => value.name == result,
        orElse: () => CalendarResult.unavailable,
      );
    } on PlatformException {
      return CalendarResult.unavailable;
    } on MissingPluginException {
      return CalendarResult.unavailable;
    }
  }
}

class DemoCalendarService implements CalendarService {
  const DemoCalendarService();
  @override
  Future<CalendarResult> add(LearningTask task) async => CalendarResult.saved;
}
