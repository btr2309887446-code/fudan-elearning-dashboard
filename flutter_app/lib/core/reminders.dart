library;

import 'tasks.dart';

class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.at,
    required this.day,
    required this.title,
    required this.body,
  });
  final int id;
  final DateTime at;
  final String day;
  final String title;
  final String body;
}

int _stableId(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

List<ScheduledReminder> planReminders(
  Iterable<LearningTask> tasks, {
  required DateTime now,
  required String account,
  Set<String> muted = const {},
}) {
  final groups = <String, List<LearningTask>>{};
  final times = <String, DateTime>{};
  final today = beijingDay(now);
  final horizon = today.add(const Duration(days: 30));
  for (final task in tasks) {
    final due = task.dueAt;
    if (task.status != TaskStatus.pending ||
        due == null ||
        muted.contains(task.key) ||
        !due.isAfter(now.toUtc())) {
      continue;
    }
    final deadlineDay = beijingDay(due);
    if (!deadlineDay.isBefore(horizon)) continue;
    final wall = beijingTime(due);
    final early =
        wall.hour < 8 ||
        (wall.hour == 8 &&
            wall.minute == 0 &&
            wall.second == 0 &&
            wall.millisecond == 0 &&
            wall.microsecond == 0);
    final wallTrigger = early
        ? deadlineDay
              .subtract(const Duration(days: 1))
              .add(const Duration(hours: 20))
        : deadlineDay.add(const Duration(hours: 8));
    final trigger = beijingInstant(wallTrigger);
    if (!trigger.isAfter(now.toUtc())) continue;
    final group = '${dayKey(deadlineDay)}:${early ? 'early' : 'morning'}';
    groups.putIfAbsent(group, () => []).add(task);
    times[group] = trigger;
  }
  final result = <ScheduledReminder>[];
  for (final entry in groups.entries) {
    final early = entry.key.endsWith(':early');
    final day = entry.key.split(':').first;
    final items = entry.value;
    final count = items.length;
    final names = items.take(3).map((task) => task.title).join('、');
    result.add(
      ScheduledReminder(
        id: _stableId('$account:${entry.key}'),
        at: times[entry.key]!,
        day: day,
        title: early ? '明早有 $count 项作业截止' : '今天有 $count 项作业截止',
        body: '$names${count > 3 ? '等 $count 项' : ''}。点击查看截止时间。',
      ),
    );
  }
  result.sort((a, b) => a.at.compareTo(b.at));
  return result.take(60).toList();
}
