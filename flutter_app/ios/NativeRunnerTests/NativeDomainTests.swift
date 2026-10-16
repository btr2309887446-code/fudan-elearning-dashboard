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

    func testCalendarAggregationCountsEachBeijingDayOnce() throws {
        let first = NativeTask(id: "a", title: "上午", courseName: "课程", courseID: 1,
                               status: .pending, dueAt: Beijing.parse("2026-10-15T01:00:00+08:00"), url: nil, assignment: nil)
        let second = NativeTask(id: "b", title: "晚上", courseName: "课程", courseID: 1,
                                status: .pending, dueAt: Beijing.parse("2026-10-15T23:00:00+08:00"), url: nil, assignment: nil)
        let other = NativeTask(id: "c", title: "无截止", courseName: "课程", courseID: 1,
                               status: .pending, dueAt: nil, url: nil, assignment: nil)
        let counts = NativeDomain.taskCountsByDay([first, second, other])
        let day = try XCTUnwrap(Beijing.parseKey("2026-10-15"))
        XCTAssertEqual(counts[day], 2)
        XCTAssertEqual(NativeDomain.tasks([first, second, other], on: day).map(\.id), ["a", "b"])
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
        XCTAssertLessThanOrEqual(NativeDomain.truncate(String(repeating: "作业要求 ", count: 20)).count, 100)
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

    func testNativeHTTPManuallyPersistsCookiesAndRedactsTicketTrace() async throws {
        let transport = ScriptedNativeHTTPTransport { request in
            let url = try XCTUnwrap(request.url)
            switch url.path {
            case "/idp/authCenter/authnEngine":
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                return httpReply(url, status: 302, headers: [
                    "Location": "/step",
                    "Set-Cookie": "idp_session=IDP_COOKIE_SECRET; Path=/; Secure, shared=SHARED_COOKIE_SECRET; Domain=.example.edu; Path=/; Secure",
                ])
            case "/step":
                XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("idp_session=IDP_COOKIE_SECRET") == true)
                return httpReply(url, status: 303, headers: [
                    "Location": "https://canvas.example.edu/login/cas?ticket=CAS_TICKET_SECRET",
                ])
            case "/login/cas":
                let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
                XCTAssertFalse(cookie.contains("idp_session"), "host-only IdP cookie must not cross hosts")
                XCTAssertTrue(cookie.contains("shared=SHARED_COOKIE_SECRET"))
                return httpReply(url, status: 302, headers: [
                    "Location": "/api/v1/users/self/profile",
                    "Set-Cookie": "canvas_session=CANVAS_COOKIE_SECRET; Path=/api; Secure",
                ])
            case "/api/v1/users/self/profile":
                let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
                XCTAssertTrue(cookie.contains("canvas_session=CANVAS_COOKIE_SECRET"))
                XCTAssertFalse(cookie.contains("idp_session"))
                return httpReply(url, status: 200)
            default:
                return httpReply(url, status: 404)
            }
        }
        let http = NativeHTTP(transport: transport)
        let engineURL = try XCTUnwrap(URL(string: "https://id.example.edu/idp/authCenter/authnEngine?locale=zh-CN"))
        let (_, response) = try await http.request(engineURL, method: "POST", body: Data("loginToken=TOKEN_SECRET".utf8),
                                                    headers: ["Content-Type": "application/x-www-form-urlencoded"])

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(http.trace.map(\.phase), ["authnEngine", "other", "ticket", "canvas-profile"])
        XCTAssertEqual(http.trace[1].sentCookieNames.sorted(), ["idp_session", "shared"])
        XCTAssertEqual(http.trace[2].sentCookieNames, ["shared"])
        XCTAssertEqual(http.trace[3].sentCookieNames.sorted(), ["canvas_session", "shared"])
        XCTAssertEqual(http.trace[0].bodyShape, ["loginToken": []])
        let encoded = String(decoding: try JSONEncoder().encode(http.trace), as: UTF8.self)
        for secret in ["IDP_COOKIE_SECRET", "SHARED_COOKIE_SECRET", "CANVAS_COOKIE_SECRET", "TOKEN_SECRET", "CAS_TICKET_SECRET"] {
            XCTAssertFalse(encoded.contains(secret))
        }
    }

    func testNativeHTTPRedirectMethodsAndStatusResponses() async throws {
        let transport = ScriptedNativeHTTPTransport { request in
            let url = try XCTUnwrap(request.url)
            if url.path.hasPrefix("/redirect/") {
                let status = Int(url.lastPathComponent) ?? 302
                return httpReply(url, status: status, headers: ["Location": "/target/\(status)"])
            }
            if url.path.hasPrefix("/target/") {
                return httpReply(url, status: 200)
            }
            if url.path.hasPrefix("/status/") {
                return httpReply(url, status: Int(url.lastPathComponent) ?? 500)
            }
            return httpReply(url, status: 404)
        }
        let http = NativeHTTP(transport: transport)
        for status in [301, 302, 303, 307, 308] {
            let url = try XCTUnwrap(URL(string: "https://example.edu/redirect/\(status)"))
            let _ = try await http.request(url, method: "POST", body: Data("x=1".utf8))
        }
        let methods = transport.requests.compactMap { $0.url?.path.hasPrefix("/target/") == true ? $0.httpMethod : nil }
        XCTAssertEqual(methods, ["GET", "GET", "GET", "POST", "POST"])

        for status in [200, 401, 403, 500] {
            let url = try XCTUnwrap(URL(string: "https://example.edu/status/\(status)"))
            let (_, response) = try await http.request(url)
            XCTAssertEqual(response.statusCode, status)
        }
    }

    func testNativeHTTPRejectsRedirectLoopsAndExcessiveHops() async throws {
        let looping = ScriptedNativeHTTPTransport { request in
            let url = try XCTUnwrap(request.url)
            return httpReply(url, status: 302, headers: ["Location": "/loop"])
        }
        let loopURL = try XCTUnwrap(URL(string: "https://example.edu/loop"))
        do {
            _ = try await NativeHTTP(transport: looping).request(loopURL)
            XCTFail("expected redirect loop rejection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("重定向循环")) }

        let chain = ScriptedNativeHTTPTransport { request in
            let url = try XCTUnwrap(request.url)
            let hop = Int(url.lastPathComponent) ?? 0
            return httpReply(url, status: 302, headers: ["Location": "/chain/\(hop + 1)"])
        }
        let start = try XCTUnwrap(URL(string: "https://example.edu/chain/0"))
        do {
            _ = try await NativeHTTP(transport: chain).request(start, maxRedirects: 1)
            XCTFail("expected redirect limit rejection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("重定向次数")) }
    }

    func testLiveFudanPreflightCookieHandoff() async throws {
        func describe(_ items: [NativeHTTPTrace]) -> String {
            items.map {
                "\($0.phase) \($0.method) \($0.url) -> \($0.status) location=\($0.location ?? "-") set=[\($0.setCookieNames.joined(separator: ","))] sent=[\($0.sentCookieNames.joined(separator: ","))]"
            }.joined(separator: "\n")
        }

        let http = NativeHTTP()
        let canvasURL = try XCTUnwrap(URL(string: "https://elearning.fudan.edu.cn/login/cas"))
        let (_, entryResponse) = try await http.request(canvasURL)
        let trace = describe(http.trace)
        XCTAssertEqual(entryResponse.statusCode, 200, trace)
        XCTAssertEqual(entryResponse.url?.host, "id.fudan.edu.cn", trace)

        let cookieNames = Set(http.cookies().map(\.name))
        XCTAssertTrue(cookieNames.contains("_csrf_token"), "Canvas entry cookie was not captured.\n\(trace)")
        XCTAssertTrue(cookieNames.contains("REQID"), "UIS redirect cookie was not captured.\n\(trace)")
        XCTAssertTrue(http.trace.contains { $0.setCookieNames.contains("_csrf_token") }, trace)
        XCTAssertTrue(http.trace.contains { $0.setCookieNames.contains("REQID") }, trace)

        let idpBase = try XCTUnwrap(URL(string: "https://id.fudan.edu.cn"))
        let keyURL = try XCTUnwrap(URL(string: "/idp/authn/getJsPublicKey", relativeTo: idpBase))
        let (_, keyResponse) = try await http.request(keyURL, method: "POST", body: Data("{}".utf8), headers: [
            "Content-Type": "application/json;charset=UTF-8",
            "Accept": "application/json, text/plain, */*",
            "Origin": idpBase.absoluteString,
            "Referer": entryResponse.url!.absoluteString,
        ])
        let finalTrace = describe(http.trace)
        XCTAssertEqual(keyResponse.statusCode, 200, finalTrace)
        let sentCookieNames = Set(try XCTUnwrap(http.trace.last).sentCookieNames)
        XCTAssertTrue(sentCookieNames.contains("REQID"), "UIS cookie was not sent to the next UIS request.\n\(finalTrace)")
        XCTAssertFalse(sentCookieNames.contains("_csrf_token"), "Canvas host-only cookie crossed to the UIS host.\n\(finalTrace)")
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

    func testMonthGridIsCompleteAndUsesBeijingDatesInAnyDeviceTimeZone() throws {
        let originalZone = NSTimeZone.default
        defer { NSTimeZone.default = originalZone }
        for zone in ["America/Los_Angeles", "UTC", "Asia/Shanghai"] {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: zone))
            for (key, count) in [("2024-02-01", 29), ("2026-02-01", 28), ("2026-10-01", 31), ("2027-01-01", 31)] {
                let month = try XCTUnwrap(Beijing.parseKey(key))
                let grid = NativeMonthGrid(month: month)
                let dates = grid.cells.compactMap(\.date)
                XCTAssertEqual(grid.cells.count, 42)
                XCTAssertEqual(Set(grid.cells.map(\.id)).count, 42)
                XCTAssertEqual(Set(dates).count, count)
                XCTAssertEqual(dates.first, month)
                XCTAssertEqual(grid.cells.compactMap(\.number), Array(1...count))
                let firstIndex = try XCTUnwrap(grid.cells.firstIndex(where: { $0.date != nil }))
                XCTAssertEqual(firstIndex, (Beijing.calendar.component(.weekday, from: month) + 5) % 7)
                for date in dates { XCTAssertEqual(Beijing.day(date), date) }
            }
            let october = try XCTUnwrap(Beijing.parseKey("2026-10-01"))
            XCTAssertEqual(Beijing.monthTitle(october), "2026年10月")
            XCTAssertEqual(Beijing.dayTitle(october), "10月1日")
            XCTAssertEqual(Beijing.key(october), "2026-10-01")
        }
    }

    @MainActor
    func testLargeSnapshotIsIndexedOnceAndInvalidatedAfterChanges() async throws {
        let suite = "NativePerformanceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "native.didClearFlutterState.v1")
        let store = NativeAppStore(defaults: defaults)
        var snapshot = snapshotFixture()
        let template = snapshot.assignments[0]
        snapshot.assignments = (0..<5000).map { index in
            var row = template
            row.id = index
            row.dueAt = index % 2 == 0 ? "2026-10-16T10:00:00+08:00" : "2026-10-17T02:00:00.000Z"
            return row
        }
        let applied = await store.applySnapshot(snapshot)
        XCTAssertTrue(applied)
        XCTAssertEqual(store.tasks.count, 5000)
        XCTAssertEqual(store.taskIndex.pendingByCourse[4], 5000)
        let started = ProcessInfo.processInfo.systemUptime
        var observed = 0
        for _ in 0..<10000 { observed += store.tasks.count }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertEqual(observed, 50_000_000)
        XCTAssertLessThan(elapsed, 1.0, "Reading task state during rendering must not reparse the snapshot")
        print("TASK_CACHE_5000_ROWS_10000_READS_SECONDS=\(elapsed)")
        await store.toggleIgnored(snapshot.assignments[0])
        XCTAssertEqual(store.taskIndex.byID["4:0"]?.status, .ignored)
        XCTAssertEqual(store.taskIndex.pendingByCourse[4], 4999)
        await store.toggleIgnored(snapshot.assignments[0])
        XCTAssertEqual(store.taskIndex.byID["4:0"]?.status, .pending)
        var updated = snapshot
        updated.assignments[0].dueAt = "2026-11-01T12:00:00+08:00"
        updated.assignments[0].workflowState = "submitted"
        await store.applySnapshot(updated)
        XCTAssertEqual(store.taskIndex.byID["4:0"]?.dueAt, Beijing.parse("2026-11-01T12:00:00+08:00"))
        XCTAssertEqual(store.taskIndex.byID["4:0"]?.status, .submitted)
        await store.toggleIgnored(updated.assignments[0])
        await store.toggleIgnored(updated.assignments[0])
        XCTAssertEqual(store.taskIndex.byID["4:0"]?.status, .submitted)
        await store.logout()
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertTrue(store.taskIndex.byID.isEmpty)
        XCTAssertNil(store.snapshot)
    }

    func testLargeCalendarAggregationPreservesEveryTask() {
        var snapshot = snapshotFixture()
        let template = snapshot.assignments[0]
        snapshot.assignments = (0..<5000).map { index in
            var row = template
            row.id = index
            row.dueAt = index % 3 == 0 ? nil : (index % 2 == 0 ? "2026-10-15T23:59:00+08:00" : "2026-10-15T16:01:00Z")
            return row
        }
        let index = NativeTaskIndex(snapshot: snapshot)
        let counts = NativeDomain.taskCountsByDay(index.tasks)
        XCTAssertEqual(counts.values.reduce(0, +), snapshot.assignments.filter { $0.dueAt != nil }.count)
        for (day, count) in counts {
            XCTAssertEqual(NativeDomain.tasks(index.tasks, on: day).count, count)
        }
        XCTAssertEqual(index.tasks.count, 5000)
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

private final class ScriptedNativeHTTPTransport: NativeHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sentRequests: [URLRequest] = []
    private let handler: (URLRequest) throws -> NativeHTTPReply

    init(handler: @escaping (URLRequest) throws -> NativeHTTPReply) { self.handler = handler }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return sentRequests
    }

    func send(_ request: URLRequest) async throws -> NativeHTTPReply {
        lock.lock(); sentRequests.append(request); lock.unlock()
        return try handler(request)
    }
}

private func httpReply(_ url: URL, status: Int, headers: [String: String] = [:]) -> NativeHTTPReply {
    let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    return NativeHTTPReply(data: Data("{}".utf8), response: response)
}
