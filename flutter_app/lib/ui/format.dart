/// 界面用的格式化与状态判定（纯函数，可直接测试）。
///
/// 与桌面端 `src/renderer/src/util.ts` 一一对应，保持两边口径一致。

library;

import 'package:intl/intl.dart';

import '../core/clock.dart';
import '../core/types.dart';

String formatScore(double? score, {int digits = 2}) =>
    score == null || score.isNaN ? '—' : score.toStringAsFixed(digits);

/// 整分不显示小数位，读起来更干净。
String formatScoreCompact(double? score) {
  if (score == null || score.isNaN) return '—';
  return score == score.roundToDouble() ? score.toStringAsFixed(0) : score.toStringAsFixed(1);
}

String formatDate(String? iso, {bool withTime = true}) {
  if (iso == null) return '—';
  final t = DateTime.tryParse(iso);
  if (t == null) return '—';
  final local = t.toLocal();
  return withTime
      ? DateFormat('yyyy/M/d HH:mm').format(local)
      : DateFormat('yyyy/M/d').format(local);
}

enum DueTone { overdue, soon, later, none }

class DueInfo {
  const DueInfo(this.text, this.tone);
  final String text;
  final DueTone tone;
}

DueInfo relativeDue(String? iso) {
  if (iso == null) return const DueInfo('无截止时间', DueTone.none);
  final t = DateTime.tryParse(iso);
  if (t == null) return const DueInfo('无截止时间', DueTone.none);

  final diff = t.difference(appNow());
  if (diff.isNegative) {
    return DueInfo('已逾期 ${-diff.inDays} 天', DueTone.overdue);
  }
  if (diff.inHours < 24) {
    final hours = diff.inHours < 1 ? 1 : diff.inHours;
    return DueInfo('今天截止（$hours 小时内）', DueTone.soon);
  }
  if (diff.inDays < 3) {
    return DueInfo('${diff.inDays + 1} 天内截止', DueTone.soon);
  }
  return DueInfo('还有 ${diff.inDays} 天', DueTone.later);
}

/// 已交的作业不再提示逾期。
///
/// 一份交上去、只是还没批改的作业，过了截止时间不该显示「已逾期」——
/// 那只剩老师批改这一步了，显示逾期只是噪音。
DueInfo dueRelative(String? iso, bool done) =>
    done ? const DueInfo('', DueTone.later) : relativeDue(iso);

const _doneStates = {'submitted', 'graded', 'pending_review', 'complete', 'graded_pending'};

/// 学生是否已交（与是否已批改无关）。
bool isCompleted(AssignmentRow row) {
  if (row.excused) return true;
  if (row.score != null) return true;
  if (row.submittedAt != null) return true;
  return _doneStates.contains(row.workflowState.toLowerCase());
}

class SubmissionState {
  const SubmissionState(this.label, this.tone);
  final String label;
  final String tone; // good / info / warn / bad / neutral
}

SubmissionState submissionState(AssignmentRow row) {
  if (row.excused) return const SubmissionState('已免除', 'neutral');
  if (row.score != null) {
    return row.late
        ? const SubmissionState('已评分（迟交）', 'warn')
        : const SubmissionState('已评分', 'good');
  }
  // 先判断是否已交：交上去的作业永远不是「缺交」，
  // 无论 Canvas 在那个字段里放了什么。
  if (isCompleted(row)) {
    return row.late
        ? const SubmissionState('已提交（迟交）待评分', 'warn')
        : const SubmissionState('已提交待评分', 'info');
  }
  if (row.missing) return const SubmissionState('未提交', 'bad');

  final due = row.dueAt == null ? null : DateTime.tryParse(row.dueAt!);
  if (due != null && due.isBefore(appNow())) {
    return const SubmissionState('已逾期未交', 'bad');
  }
  return const SubmissionState('未开始', 'neutral');
}

/// 有成绩的课程的平均分。
double? averageScore(List<CourseSummary> courses) {
  final scored = courses.where((c) => c.currentScore != null).toList();
  if (scored.isEmpty) return null;
  return scored.fold<double>(0, (s, c) => s + c.currentScore!) / scored.length;
}

/// 排序：缺交多的、分低的排前面。
int courseUrgency(CourseSummary a, CourseSummary b) {
  final miss = b.missingCount.compareTo(a.missingCount);
  if (miss != 0) return miss;
  final sa = a.currentScore ?? 101;
  final sb = b.currentScore ?? 101;
  if (sa != sb) return sa.compareTo(sb);
  return a.displayName.compareTo(b.displayName);
}
