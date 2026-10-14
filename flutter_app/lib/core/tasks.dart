/// Shared task identity, status and Beijing deadline grouping.
library;

import 'ignored.dart';
import 'types.dart';

const _doneStates = {
  'submitted',
  'graded',
  'pending_review',
  'complete',
  'graded_pending',
};

bool isCompleted(AssignmentRow row) =>
    row.excused ||
    row.score != null ||
    row.submittedAt != null ||
    _doneStates.contains(row.workflowState.toLowerCase());

DateTime beijingTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 8));
DateTime beijingDay(DateTime instant) {
  final time = beijingTime(instant);
  return DateTime.utc(time.year, time.month, time.day);
}

DateTime beijingInstant(DateTime wallTime) =>
    wallTime.toUtc().subtract(const Duration(hours: 8));
DateTime? parseDayKey(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final parts = value.split('-').map(int.parse).toList();
  final day = DateTime.utc(parts[0], parts[1], parts[2]);
  return dayKey(day) == value ? day : null;
}

String dayKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Canvas normally supplies ISO timestamps with an offset. Offset-less values
/// are interpreted as Beijing wall time, never as the machine's time zone.
DateTime? parseDeadline(String? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  if (RegExp(r'(Z|[+-]\d\d:?\d\d)$', caseSensitive: false).hasMatch(value)) {
    return parsed.toUtc();
  }
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  ).subtract(const Duration(hours: 8));
}

enum TaskStatus { pending, submitted, ignored }

enum TaskBucket { overdue, today, week, later, undated }

class LearningTask {
  const LearningTask({
    required this.key,
    required this.title,
    required this.courseName,
    required this.status,
    this.courseId,
    this.dueAt,
    this.url,
    this.assignment,
  });

  final String key;
  final String title;
  final String courseName;
  final int? courseId;
  final TaskStatus status;
  final DateTime? dueAt;
  final String? url;
  final AssignmentRow? assignment;

  TaskBucket bucket(DateTime now) {
    final due = dueAt;
    if (due == null) return TaskBucket.undated;
    if (status == TaskStatus.pending && !due.isAfter(now.toUtc())) {
      return TaskBucket.overdue;
    }
    final day = beijingDay(due);
    final today = beijingDay(now);
    if (day == today) return TaskBucket.today;
    if (day.isAfter(today) &&
        day.isBefore(today.add(const Duration(days: 8)))) {
      return TaskBucket.week;
    }
    return TaskBucket.later;
  }
}

int? defaultTermId(Snapshot snapshot) {
  if (snapshot.terms.isEmpty) return null;
  return snapshot.terms
      .firstWhere((term) => term.isCurrent, orElse: () => snapshot.terms.first)
      .id;
}

List<LearningTask> buildTasks(
  Snapshot snapshot, {
  Set<String> ignored = const {},
  Set<int>? courseIds,
}) {
  final result = <String, LearningTask>{};
  for (final row in snapshot.assignments) {
    if (courseIds != null && !courseIds.contains(row.courseId)) continue;
    final key = assignmentKey(row.courseId, row.id);
    result[key] = LearningTask(
      key: key,
      title: row.name,
      courseName: row.courseName,
      courseId: row.courseId,
      dueAt: parseDeadline(row.dueAt),
      url: row.htmlUrl,
      assignment: row,
      status: ignored.contains(key)
          ? TaskStatus.ignored
          : isCompleted(row)
          ? TaskStatus.submitted
          : TaskStatus.pending,
    );
  }
  for (final entry in snapshot.todo) {
    if (courseIds != null &&
        (entry.courseId != null && !courseIds.contains(entry.courseId))) {
      continue;
    }
    final assignmentId = entry.assignmentId;
    final explicitKey = assignmentId != null && entry.courseId != null
        ? assignmentKey(entry.courseId!, assignmentId)
        : null;
    if (explicitKey != null && result.containsKey(explicitKey)) continue;
    if (explicitKey == null &&
        result.values.any(
          (task) =>
              task.title == entry.title &&
              task.courseId == entry.courseId &&
              task.dueAt == parseDeadline(entry.dueAt),
        )) {
      continue;
    }
    final key =
        explicitKey ??
        'todo:${entry.courseId}:${entry.htmlUrl ?? '${entry.title}:${entry.dueAt}'}';
    if (result.containsKey(key)) continue;
    result[key] = LearningTask(
      key: key,
      title: entry.title,
      courseName: entry.courseName,
      courseId: entry.courseId,
      status: ignored.contains(key) ? TaskStatus.ignored : TaskStatus.pending,
      dueAt: parseDeadline(entry.dueAt),
      url: entry.htmlUrl,
    );
  }
  return result.values.toList()..sort((a, b) {
    final time = a.dueAt == null
        ? (b.dueAt == null ? 0 : 1)
        : b.dueAt == null
        ? -1
        : a.dueAt!.compareTo(b.dueAt!);
    return time != 0 ? time : a.key.compareTo(b.key);
  });
}
