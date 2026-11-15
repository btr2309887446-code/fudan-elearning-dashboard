import type { Snapshot } from "../../core/types";
import { buildCourseDetail } from "../../core/scoring";
import { GroupChart, ScoreTrendChart } from "./components/charts";
export function GradeDetails({
  snapshot,
  courseId,
}: {
  snapshot: Snapshot;
  courseId: number;
}) {
  const d = buildCourseDetail(snapshot, courseId);
  if (!d) return null;
  return (
    <>
      <p>当前得分 {d.course.currentScore ?? "—"}%</p>
      <GroupChart groups={d.groups} />
      <h3>得分趋势</h3><ScoreTrendChart rows={d.assignments} />
      {d.assignments.map((a) => (
        <p key={a.id}>
          {a.name}：{a.score ?? "未评分"} / {a.pointsPossible ?? "—"}
        </p>
      ))}
    </>
  );
}
