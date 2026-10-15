import XCTest
@testable import NativeRunner

final class NativeDomainTests: XCTestCase {
    func testBeijingParsesOffsetAndOffsetlessCanvasDeadlines() throws {
        let offset = try XCTUnwrap(Beijing.parse("2026-10-15T00:00:00+08:00"))
        let wall = try XCTUnwrap(Beijing.parse("2026-10-15T00:00:00"))
        XCTAssertEqual(offset, wall)
        XCTAssertEqual(Beijing.key(Beijing.day(offset)), "2026-10-15")
        XCTAssertEqual(Beijing.parseKey("2026-02-29"), nil)
    }

    func testTasksMergeExplicitTodoIdentityAndApplyIgnoredStatus() {
        let assignment = NativeAssignment(id: 8, courseID: 4, courseName: "数学", name: "实验报告",
                                          groupID: 1, groupName: "平时", dueAt: "2026-10-16T10:00:00Z",
                                          pointsPossible: 10, groupWeight: 0, score: nil, grade: nil,
                                          submittedAt: nil, gradedAt: nil, workflowState: "unsubmitted",
                                          late: false, missing: false, excused: false,
                                          omitFromFinalGrade: false, htmlURL: nil, descriptionExcerpt: nil)
        let todo = NativeTodo(title: "实验报告", courseName: "数学", kind: "assignment",
                              courseID: 4, assignmentID: 8, dueAt: assignment.dueAt,
                              pointsPossible: 10, htmlURL: nil)
        let snapshot = NativeSnapshot(fetchedAt: Date(),
                                      profile: NativeProfile(id: 9, name: "学生"),
                                      courses: [], terms: [], assignments: [assignment], todo: [todo],
                                      warnings: [], reusedCourseCount: 0)
        let key = NativeDomain.assignmentKey(4, 8)
        let tasks = NativeDomain.tasks(in: snapshot, ignored: [key])
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.status, .ignored)
        XCTAssertEqual(tasks.first?.id, key)
    }

    func testDeadlineBucketsUseBeijingDay() throws {
        let now = try XCTUnwrap(Beijing.parse("2026-10-15T07:30:00+08:00"))
        let today = NativeTask(id: "a", title: "今日", courseName: "课程", courseID: 1,
                               status: .pending, dueAt: Beijing.parse("2026-10-15T23:59:00+08:00"), url: nil, assignment: nil)
        let week = NativeTask(id: "b", title: "本周", courseName: "课程", courseID: 1,
                              status: .pending, dueAt: Beijing.parse("2026-10-20T12:00:00+08:00"), url: nil, assignment: nil)
        let overdue = NativeTask(id: "c", title: "过期", courseName: "课程", courseID: 1,
                                 status: .pending, dueAt: Beijing.parse("2026-10-14T23:00:00+08:00"), url: nil, assignment: nil)
        XCTAssertEqual(today.bucket(now: now), .today)
        XCTAssertEqual(week.bucket(now: now), .week)
        XCTAssertEqual(overdue.bucket(now: now), .overdue)
    }

    func testDefaultTermSelectionAndTermCourseCounts() throws {
        let now = try XCTUnwrap(Beijing.parse("2026-10-15T12:00:00+08:00"))
        let api = CanvasAPI(http: NativeHTTP())
        let courses = [
            courseFixture(id: 1, termID: 2026, name: "秋季一"),
            courseFixture(id: 2, termID: 2026, name: "秋季二"),
            courseFixture(id: 3, termID: 2025, name: "春季"),
        ]
        let terms = api.makeTerms(courses, now: now)
        XCTAssertEqual(terms.first(where: { $0.isCurrent })?.id, 2026)
        XCTAssertEqual(terms.first(where: { $0.id == 2026 })?.courseCount, 2)
    }

    func testWeightedScoreRenormalizesOnlyGradedGroups() {
        let result = NativeDomain.weightedScore([
            (weight: 60, earned: 300, possible: 400),
            (weight: 40, earned: 0, possible: 0),
        ])
        XCTAssertEqual(try XCTUnwrap(result), 75, accuracy: 0.001)
        XCTAssertNil(NativeDomain.weightedScore([(weight: 100, earned: 0, possible: 0)]))
    }

    func testIgnoredAndExcusedWorkDoesNotBecomeACompletedPendingTask() throws {
        var snapshot = snapshotFixture()
        snapshot.assignments[0].excused = true
        let task = try XCTUnwrap(NativeDomain.tasks(in: snapshot).first)
        XCTAssertEqual(task.status, .submitted)
    }

    func testFileTreePreservesNestedFoldersAndHiddenFilesAreExcluded() {
        let folder = NativeFileFolder(id: 2, name: "实验", parentID: 1)
        let root = NativeFileFolder(id: 1, name: "资料", parentID: nil)
        let visible = NativeFile(id: 10, name: "报告.pdf", url: URL(string: "https://example.com/10")!, size: 99,
                                 contentType: "application/pdf", folderID: 2, hidden: false)
        let hidden = NativeFile(id: 11, name: "locked", url: URL(string: "https://example.com/11")!, size: 0,
                                contentType: nil, folderID: 2, hidden: true)
        let tree = NativeFileTree.build(folders: [folder, root], files: [visible, hidden])
        XCTAssertEqual(NativeFileTree.flatten(tree).map(\.id), [10])
        XCTAssertEqual(NativeFileTree.flatten(tree).first?.id, visible.id)
        XCTAssertEqual(tree.children.first?.children.first?.children.first?.path, "资料/实验/报告.pdf")
    }

    func testReminderPlannerUsesMorningAndEarlyDeadlineSchedulesAndMute() throws {
        let now = try XCTUnwrap(Beijing.parse("2026-10-14T07:00:00+08:00"))
        let morning = NativeTask(id: "1:1", title: "报告", courseName: "课程", courseID: 1,
                                 status: .pending, dueAt: Beijing.parse("2026-10-15T10:00:00+08:00"), url: nil, assignment: nil)
        let early = NativeTask(id: "1:2", title: "小测", courseName: "课程", courseID: 1,
                               status: .pending, dueAt: Beijing.parse("2026-10-15T08:00:00+08:00"), url: nil, assignment: nil)
        let muted = NativeTask(id: "1:3", title: "静音", courseName: "课程", courseID: 1,
                               status: .pending, dueAt: Beijing.parse("2026-10-15T09:00:00+08:00"), url: nil, assignment: nil)
        let reminders = NativeReminderPlanner.make(tasks: [morning, early, muted], now: now,
                                                   account: "55", muted: [muted.id])
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.map(\.day).sorted(), ["2026-10-15", "2026-10-15"])
        XCTAssertTrue(reminders.contains { $0.title.contains("明早") && $0.at == Beijing.parse("2026-10-14T20:00:00+08:00") })
        XCTAssertTrue(reminders.contains { $0.title.contains("今天") && $0.at == Beijing.parse("2026-10-15T08:00:00+08:00") })
    }

    func testUISErrorClassificationAndSummaryFallback() {
        XCTAssertEqual(NativeUISAuthenticator.classify("用户名或密码错误", code: 401).localizedDescription, "学号或密码不正确。")
        XCTAssertEqual(NativeUISAuthenticator.classify("账号已锁定", code: 401).localizedDescription, "账号已被锁定，请等待自动解锁或联系信息办。")
        XCTAssertEqual(NativeDomain.truncate(String(repeating: "作业要求 ", count: 20)).count, 100)
        XCTAssertEqual(NativeDomain.summarize("<p>第一段</p><p>第二段 &amp; 更多</p>"), "第一段\n第二段 & 更多")
        XCTAssertEqual(NativeDomain.summarize("&#8220;要求&#8221; &#x2022; &#x1F4D6;"), "“要求” • 📖")
    }

    func testCookieHeaderHonorsDomainPathSecureAndRedirectAllowList() throws {
        let cookies = [
            NativeCookie(name: "canvas", value: "secret", domain: ".fudan.edu.cn", path: "/api", secure: true, expires: nil),
            NativeCookie(name: "idp", value: "private", domain: "id.fudan.edu.cn", path: "/", secure: true, expires: nil),
        ]
        let canvasURL = try XCTUnwrap(URL(string: "https://elearning.fudan.edu.cn/api/v1/profile"))
        XCTAssertEqual(NativeCookieHeader.value(cookies, for: canvasURL, permittedDomains: [".fudan.edu.cn"]), "canvas=secret")
        let lookalike = try XCTUnwrap(URL(string: "https://evilfudan.edu.cn/api/v1/profile"))
        XCTAssertNil(NativeCookieHeader.value(cookies, for: lookalike))
        let wrongPath = try XCTUnwrap(URL(string: "https://elearning.fudan.edu.cn/account"))
        XCTAssertNil(NativeCookieHeader.value(cookies, for: wrongPath, permittedDomains: [".fudan.edu.cn"]))
    }

    func testPaginationLinkSelectsOnlyNextRelation() throws {
        let header = #"<https://elearning.fudan.edu.cn/api/v1/courses?page=2>; rel="next", <https://elearning.fudan.edu.cn/api/v1/courses?page=9>; rel="last""#
        XCTAssertEqual(CanvasAPI.nextLink(header)?.query, "page=2")
        XCTAssertNil(CanvasAPI.nextLink(#"<https://example.com/page>; rel="last""#))
    }

    func testDownloadPathsSanitizeAndAvoidCaseInsensitiveCollisions() throws {
        let first = NativeFile(id: 1, name: "CON.pdf", url: URL(string: "https://example.com/1")!,
                               size: 1, contentType: nil, folderID: nil, hidden: false)
        let second = NativeFile(id: 2, name: "con.PDF", url: URL(string: "https://example.com/2")!,
                                size: 1, contentType: nil, folderID: nil, hidden: false)
        let node1 = NativeFileNode(id: "file:1", name: first.name, path: "第一章/CON.pdf", file: first, children: [])
        let node2 = NativeFileNode(id: "file:2", name: second.name, path: "第一章/con.PDF", file: second, children: [])
        let paths = NativeDownloadPaths.plan(term: "../学期", course: "课程:一", nodes: [node1, node2]).map(\.relativePath)
        XCTAssertEqual(paths, ["_学期/课程_一/第一章/_CON.pdf", "_学期/课程_一/第一章/_con (2).PDF"])
        XCTAssertFalse(paths.contains { $0.contains("..") || $0.contains(":") })
    }

    func testRSAHelperProducesPkcs1CiphertextLength() throws {
        let key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAozt/zqIrfEMZunYPG8+owatRWD+a4cH80KiRlx30BHDk3CPlpakQKM9B2vyB4dp/RgVz/WAg1Y0Y9M+DodsCMdtVBRvxQV1umX/ykYiV4qH3svRyilbkoTO8hdxARm5o13LoinDlOUqIvr8xEMItxfQ5ENwj0eWWrWZWGgcAgx9fEF2N6od6p0a5pwxqHsoNYJ2gyLSyu3KdNU/JFtJvmnos49EAsMEARzuM5j9cGLxuckjviJqpHN1kl9nlpUnfTvx9dVbdgci+2knsMcJorzzobXALZiklXISfMJc+Tqmy1/SsAUiYqQRif4PI8Y40V85N86l7GfFUdTixVkDPawIDAQAB"
        let encrypted = try RSAHelper.encrypt("复旦测试Password!", publicKeyBase64: key)
        XCTAssertEqual(Data(base64Encoded: encrypted)?.count, 256)
    }

    private func snapshotFixture() -> NativeSnapshot {
        let row = NativeAssignment(id: 8, courseID: 4, courseName: "数学", name: "实验报告",
                                   groupID: 1, groupName: "平时", dueAt: nil,
                                   pointsPossible: 10, groupWeight: 0, score: nil, grade: nil,
                                   submittedAt: nil, gradedAt: nil, workflowState: "unsubmitted",
                                   late: false, missing: false, excused: false,
                                   omitFromFinalGrade: false, htmlURL: nil, descriptionExcerpt: nil)
        return NativeSnapshot(fetchedAt: Date(), profile: NativeProfile(id: 1, name: "学生"),
                              courses: [], terms: [], assignments: [row], todo: [],
                              warnings: [], reusedCourseCount: 0)
    }

    private func courseFixture(id: Int, termID: Int, name: String) -> NativeCourse {
        NativeCourse(id: id, name: name, displayName: name, courseCode: "", termName: "学期 \(termID)",
                     termID: termID, termStartAt: termID == 2026 ? "2026-09-01T00:00:00+08:00" : "2025-02-01T00:00:00+08:00",
                     termEndAt: termID == 2026 ? "2027-01-31T23:59:59+08:00" : "2025-07-01T23:59:59+08:00",
                     nickname: nil, startAt: nil, endAt: nil, currentScore: nil, finalScore: nil,
                     currentGrade: nil, finalGrade: nil, earnedPoints: nil, possiblePointsGraded: nil,
                     assignmentCount: 0, submittedCount: 0, gradedCount: 0, missingCount: 0,
                     lateCount: 0, upcomingCount: 0)
    }
}
