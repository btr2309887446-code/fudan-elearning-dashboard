// Map which Canvas REST routes exist on this instance.
// 401 = route exists but needs auth. 404 = route absent.
const BASE = 'https://elearning.fudan.edu.cn';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

const routes = [
  '/api/v1/courses',
  '/api/v1/courses?enrollment_state=active&include[]=total_scores&per_page=50',
  '/api/v1/users/self',
  '/api/v1/users/self/profile',
  '/api/v1/users/self/enrollments',
  '/api/v1/users/self/todo',
  '/api/v1/users/self/upcoming_events',
  '/api/v1/users/self/course_nicknames',
  '/api/v1/users/self/colors',
  '/api/v1/dashboard/dashboard_cards',
  '/api/v1/planner/items',
  '/api/v1/planner/notes',
  '/api/v1/conversations',
  '/api/v1/calendar_events',
  '/api/v1/courses/1/assignments',
  '/api/v1/courses/1/enrollments',
  '/api/v1/courses/1/students/submissions',
  '/api/v1/courses/1/modules',
  '/api/v1/courses/1/quizzes',
  '/api/v1/courses/1/assignments/1/submissions/self',
  '/api/v1/courses/1/assignment_groups',
  '/api/v1/courses/1/features',
  '/api/v1/search/all_courses',
  '/api/v1/announcements',
  '/api/v1/favorites',
  '/api/v1/groups',
  '/api/v1/files/folders',
  '/api/v1/course_nicknames',
  '/api/v1/accounts/self',
  '/api/v1/accounts/1/courses',
  '/api/v1/outcome_results',
  '/api/v1/progress/1',
  '/login/oauth2/auth?client_id=1&response_type=code&redirect_uri=https%3A%2F%2Felearning.fudan.edu.cn',
  '/.well-known/oauth-authorization-server',
  '/api/v1/mobile_dashboard',
  '/api/v1/users/self/missing_submissions',
  '/api/v1/users/self/groups',
  '/api/v1/courses/1/gradebook_history/days',
  '/api/v1/courses/1/assignments/1/gradeable_students',
  '/api/v1/courses/1/pages',
  '/api/v1/courses/1/discussion_topics',
  '/api/v1/courses/1/files',
  '/api/v1/courses/1/students',
  '/api/v1/courses/1/content_migrations',
  '/api/v1/courses/1/assignment_overrides',
  '/api/v1/courses/1/outcome_results',
  '/api/v1/courses/1/analytics/activity',
];

const rows = [];
for (const r of routes) {
  try {
    const res = await fetch(BASE + r, { redirect: 'manual', headers: { 'User-Agent': UA } });
    let snippet = '';
    if (res.status !== 404) {
      snippet = (await res.text()).replace(/\s+/g, ' ').slice(0, 120);
    }
    rows.push({ route: r, status: res.status, loc: res.headers.get('location'), snippet });
    console.log(`${String(res.status).padEnd(4)} ${r}${snippet ? '  :: ' + snippet : ''}`);
  } catch (e) {
    console.log(`ERR  ${r} :: ${e.message}`);
  }
}
console.log('\n=== summary ===');
console.log('exists(401):', rows.filter((r) => r.status === 401).length);
console.log('missing(404):', rows.filter((r) => r.status === 404).length);
console.log('other:', rows.filter((r) => r.status !== 401 && r.status !== 404).map((r) => `${r.status} ${r.route}`).join(', '));
