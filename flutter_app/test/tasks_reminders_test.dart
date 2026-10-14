import 'package:flutter_test/flutter_test.dart';
import 'package:fudan_elearning/core/clock.dart';
import 'package:fudan_elearning/core/demo.dart';
import 'package:fudan_elearning/core/reminders.dart';
import 'package:fudan_elearning/core/tasks.dart';
import 'package:fudan_elearning/core/types.dart';
import 'package:fudan_elearning/core/session.dart';
import 'package:fudan_elearning/platform/reminder_service.dart';
import 'package:fudan_elearning/state/app_state.dart';

LearningTask task(
  String key,
  String due, {
  TaskStatus status = TaskStatus.pending,
}) => LearningTask(
  key: key,
  title: key,
  courseName: '课程',
  courseId: 1,
  status: status,
  dueAt: parseDeadline(due),
);

class FakeReminders implements ReminderService {
  bool granted = true;
  int requests = 0;
  int cancellations = 0;
  List<ScheduledReminder> scheduled = [];
  @override
  Future<bool> requestPermission() async {
    requests++;
    return granted;
  }

  @override
  Future<void> replace(List<ScheduledReminder> reminders) async {
    scheduled = reminders;
  }

  @override
  Future<void> cancelAll() async {
    cancellations++;
    scheduled = [];
  }
}

Snapshot snapshotWith(
  List<AssignmentRow> rows, {
  List<TodoEntry> todo = const [],
}) {
  final demo = buildDemoSnapshot();
  return Snapshot(
    fetchedAt: demo.fetchedAt,
    profile: demo.profile,
    courses: demo.courses,
    terms: demo.terms,
    assignments: rows,
    todo: todo,
  );
}

AssignmentRow row(
  int course,
  int id, {
  String name = '作业',
  String? due,
  String state = 'unsubmitted',
  bool excused = false,
  bool missing = false,
}) => AssignmentRow(
  id: id,
  courseId: course,
  courseName: '课程',
  name: name,
  groupId: 1,
  groupName: '作业',
  dueAt: due,
  workflowState: state,
  excused: excused,
  missing: missing,
);

void main() {
  setUp(() => appNow = () => DateTime.utc(2026, 3, 15, 0));
  tearDown(() => appNow = DateTime.now);

  group('统一任务模型', () {
    test('不同课程的相同作业 ID 不合并，Canvas 待办按完整 ID 去重', () {
      final data = snapshotWith(
        [row(1, 7), row(2, 7)],
        todo: const [
          TodoEntry(
            title: '作业',
            courseName: '课程',
            kind: 'assignment',
            courseId: 1,
            assignmentId: 7,
          ),
        ],
      );
      expect(buildTasks(data).map((task) => task.key), ['1:7', '2:7']);
    });
    test('不同日期的同名待办不会被标题匹配吞掉', () {
      final data = snapshotWith(
        [row(1, 7, due: '2026-03-15T18:00:00+08:00')],
        todo: const [
          TodoEntry(
            title: '作业',
            courseName: '课程',
            kind: 'quiz',
            courseId: 1,
            dueAt: '2026-03-16T18:00:00+08:00',
            htmlUrl: 'https://example.test/quiz/9',
          ),
        ],
      );
      expect(buildTasks(data), hasLength(2));
    });
    test('已提交未评分、已免除不算逾期，手动忽略状态一致', () {
      final tasks = buildTasks(
        snapshotWith([
          row(
            1,
            1,
            due: '2026-03-14T18:00:00+08:00',
            state: 'submitted',
            missing: true,
          ),
          row(1, 2, excused: true),
          row(1, 3),
        ]),
        ignored: {'1:3'},
      );
      expect(
        tasks.firstWhere((task) => task.key == '1:1').status,
        TaskStatus.submitted,
      );
      expect(
        tasks.firstWhere((task) => task.key == '1:2').status,
        TaskStatus.submitted,
      );
      expect(
        tasks.firstWhere((task) => task.key == '1:3').status,
        TaskStatus.ignored,
      );
      expect(
        tasks.any((task) => task.bucket(appNow()) == TaskBucket.overdue),
        isFalse,
      );
    });
    test('北京午夜分组不受 UTC 日期影响，解析无时区与非法日期', () {
      final due = parseDeadline('2026-03-15T23:59:00Z')!;
      expect(dayKey(beijingDay(due)), '2026-03-16');
      expect(parseDeadline('2026-03-15T08:00:00'), DateTime.utc(2026, 3, 15));
      expect(parseDeadline('invalid'), isNull);
      expect(parseDayKey('2026-03-16'), DateTime.utc(2026, 3, 16));
      expect(parseDayKey('2026-02-31'), isNull);
    });
    test('明确的时间分组、无截止与刚好截止', () {
      final now = DateTime.utc(2026, 3, 15, 4);
      expect(
        task('a', '2026-03-15T12:00:00+08:00').bucket(now),
        TaskBucket.overdue,
      );
      expect(
        task('b', '2026-03-15T23:59:00+08:00').bucket(now),
        TaskBucket.today,
      );
      expect(
        task('c', '2026-03-22T23:59:00+08:00').bucket(now),
        TaskBucket.week,
      );
      expect(
        task('d', '2026-03-23T00:00:00+08:00').bucket(now),
        TaskBucket.later,
      );
      expect(
        const LearningTask(
          key: 'x',
          title: 'x',
          courseName: 'x',
          status: TaskStatus.pending,
        ).bucket(now),
        TaskBucket.undated,
      );
    });
  });
  group('每日汇总提醒', () {
    test('同一天多项作业合并为一条八点日报，ID 在重复同步后稳定', () {
      final tasks = [
        task('a', '2026-03-16T18:00:00+08:00'),
        task('b', '2026-03-16T23:59:00+08:00'),
      ];
      final planned = planReminders(tasks, now: appNow(), account: '1');
      expect(planned, hasLength(1));
      expect(planned.single.at, DateTime.utc(2026, 3, 16));
      expect(planned.single.title, '今天有 2 项作业截止');
      expect(
        planned.single.id,
        planReminders(tasks.reversed, now: appNow(), account: '1').single.id,
      );
      expect(
        planned.single.id,
        isNot(planReminders(tasks, now: appNow(), account: '2').single.id),
      );
    });
    for (final time in ['00:00:00', '07:59:59', '08:00:00']) {
      test('$time 截止在前晚二十点提醒', () {
        final planned = planReminders(
          [task('early', '2026-03-16T$time+08:00')],
          now: appNow(),
          account: '1',
        );
        expect(planned.single.at, DateTime.utc(2026, 3, 15, 12));
        expect(planned.single.day, '2026-03-16');
      });
    }
    test('08:00:01 属于当天日报', () {
      final planned = planReminders(
        [task('after', '2026-03-16T08:00:01+08:00')],
        now: appNow(),
        account: '1',
      );
      expect(planned.single.at, DateTime.utc(2026, 3, 16));
    });
    test('已错过的触发时间、已提交、无需提交、静音、无日期不提醒', () {
      final planned = planReminders(
        [
          task('past', '2026-03-15T18:00:00+08:00'),
          task(
            'submitted',
            '2026-03-16T18:00:00+08:00',
            status: TaskStatus.submitted,
          ),
          task(
            'ignored',
            '2026-03-16T18:00:00+08:00',
            status: TaskStatus.ignored,
          ),
          task('muted', '2026-03-16T18:00:00+08:00'),
          const LearningTask(
            key: 'undated',
            title: 'x',
            courseName: 'x',
            status: TaskStatus.pending,
          ),
        ],
        now: appNow(),
        account: '1',
        muted: {'muted'},
      );
      expect(planned, isEmpty);
    });
    test('截止修改会改变触发日期，候选只取三十天且最多六十条', () {
      final before = planReminders(
        [task('a', '2026-03-16T18:00:00+08:00')],
        now: appNow(),
        account: '1',
      );
      final after = planReminders(
        [task('a', '2026-03-17T18:00:00+08:00')],
        now: appNow(),
        account: '1',
      );
      expect(before.single.id, isNot(after.single.id));
      final tasks = [
        for (var i = 0; i < 80; i++)
          for (final hour in [7, 18])
            task(
              '$i-$hour',
              '${dayKey(DateTime.utc(2026, 3, 16).add(Duration(days: i)))}T${hour.toString().padLeft(2, '0')}:00:00+08:00',
            ),
      ];
      final planned = planReminders(tasks, now: appNow(), account: '1');
      expect(planned.length, lessThanOrEqualTo(60));
      expect(planned.every((r) => r.day.compareTo('2026-04-14') < 0), isTrue);
    });
  });
  group('偏好与平台服务', () {
    test('旧版隐藏未提交迁移为已提交筛选，提醒缺省关闭', () {
      final prefs = AppPrefs.fromJson({
        'hideUnsubmitted': true,
        'ignoredAssignments': ['1:7'],
      });
      expect(prefs.taskFilter, 'submitted');
      expect(prefs.remindersEnabled, isFalse);
      expect(prefs.ignoredAssignments, ['1:7']);
      expect(AppPrefs.fromJson(prefs.toJson()).taskFilter, 'submitted');
    });
    test('权限拒绝不启用通知，之后允许可重试，退出清除提醒', () async {
      final service = FakeReminders()..granted = false;
      final state = AppState(
        store: MemoryStore(),
        demo: true,
        reminders: service,
      );
      await state.boot();
      expect(service.requests, 0);
      await state.setRemindersEnabled(true);
      expect(state.prefs.remindersEnabled, isFalse);
      expect(state.reminderPermissionDenied, isTrue);
      service.granted = true;
      await state.setRemindersEnabled(true);
      expect(state.prefs.remindersEnabled, isTrue);
      expect(service.scheduled, isNotEmpty);
      await state.logout();
      expect(state.prefs.remindersEnabled, isFalse);
      expect(service.scheduled, isEmpty);
    });
    test('无需提交和单项静音会重新安排，日期跳转拒绝非法输入', () async {
      final service = FakeReminders();
      final state = AppState(
        store: MemoryStore(),
        demo: true,
        reminders: service,
      );
      await state.boot();
      await state.setRemindersEnabled(true);
      final before = service.scheduled.map((r) => r.body).join();
      final open = state.tasks.firstWhere(
        (task) =>
            task.status == TaskStatus.pending &&
            task.assignment != null &&
            task.dueAt != null &&
            task.dueAt!.isAfter(appNow().add(const Duration(days: 1))),
      );
      await state.toggleTaskReminder(open.key);
      expect(service.scheduled.map((r) => r.body).join(), isNot(before));
      await state.toggleTaskReminder(open.key);
      await state.toggleIgnoredAssignment(
        open.assignment!.courseId,
        open.assignment!.id,
      );
      expect(service.scheduled.map((r) => r.body).join(), isNot(before));
      state.openReminderDay('2026-02-31');
      expect(state.pendingReminderDay, isNull);
      state.openReminderDay('2026-03-16');
      expect(state.pendingReminderDay, '2026-03-16');
    });
  });
}
