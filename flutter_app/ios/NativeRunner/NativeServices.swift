import Foundation
import Security

enum NativeError: LocalizedError {
    case http(Int, String)
    case protocolFailure(String)
    case authExpired
    case missingSession

    var errorDescription: String? {
        switch self {
        case let .http(code, message): "HTTP \(code)：\(message)"
        case let .protocolFailure(message): message
        case .authExpired: "登录状态已失效，请重新登录。"
        case .missingSession: "请先登录复旦统一身份认证。"
        }
    }
}

struct NativeCookie: Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var secure: Bool
    var expires: Date?
    var hostOnly: Bool

    init(name: String, value: String, domain: String, path: String, secure: Bool,
         expires: Date?, hostOnly: Bool? = nil) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.secure = secure
        self.expires = expires
        self.hostOnly = hostOnly ?? !domain.hasPrefix(".")
    }

    private enum CodingKeys: String, CodingKey { case name, value, domain, path, secure, expires, hostOnly }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        value = try values.decode(String.self, forKey: .value)
        domain = try values.decode(String.self, forKey: .domain)
        path = try values.decodeIfPresent(String.self, forKey: .path) ?? "/"
        secure = try values.decodeIfPresent(Bool.self, forKey: .secure) ?? false
        expires = try values.decodeIfPresent(Date.self, forKey: .expires)
        hostOnly = try values.decodeIfPresent(Bool.self, forKey: .hostOnly) ?? !domain.hasPrefix(".")
    }

    var properties: [HTTPCookiePropertyKey: Any] {
        var value: [HTTPCookiePropertyKey: Any] = [.name: name, .value: self.value, .domain: domain, .path: path]
        if secure { value[.secure] = "TRUE" }
        if let expires { value[.expires] = expires }
        return value
    }
}

enum NativeCookieHeader {
    static func value(_ cookies: [NativeCookie], for url: URL, permittedDomains: Set<String>? = nil) -> String? {
        guard let host = url.host?.lowercased(),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let matching = cookies.filter { cookie in
            (permittedDomains == nil || permittedDomains!.contains(cookie.domain)) &&
            domain(cookie, matches: host) &&
            (!cookie.secure || url.scheme?.lowercased() == "https") &&
            path(cookie.path, matches: url.path) &&
            (cookie.expires.map { $0 > Date() } ?? true)
        }
        guard !matching.isEmpty else { return nil }
        return matching.sorted { $0.path.count > $1.path.count }
            .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private static func domain(_ cookie: NativeCookie, matches host: String) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if cookie.hostOnly { return host == domain }
        return host == domain || host.hasSuffix(".\(domain)")
    }

    private static func path(_ cookiePath: String, matches requestPath: String) -> Bool {
        let path = cookiePath.isEmpty ? "/" : cookiePath
        guard requestPath.hasPrefix(path) else { return false }
        return path.hasSuffix("/") || requestPath.count == path.count || requestPath.dropFirst(path.count).first == "/"
    }
}

enum NativeResponseCookies {
    static func headers(_ response: HTTPURLResponse) -> [String] {
        var headers: [String] = []
        for item in response.allHeaderFields {
            guard let key = item.key as? String,
                  key.caseInsensitiveCompare("Set-Cookie") == .orderedSame else { continue }
            if let value = item.value as? String {
                headers.append(contentsOf: splitCombined(value))
            } else if let value = item.value as? [String] {
                headers.append(contentsOf: value)
            } else if let value = item.value as? [Any] {
                headers.append(contentsOf: value.compactMap { $0 as? String })
            }
        }
        return headers
    }

    static func parse(_ response: HTTPURLResponse) -> [NativeCookie] {
        guard let url = response.url else { return [] }
        return headers(response).flatMap { header in
            HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: url).map { cookie in
                let hasDomain = header.split(separator: ";").contains { part in
                    part.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("domain=")
                }
                return NativeCookie(name: cookie.name, value: cookie.value, domain: cookie.domain,
                                    path: cookie.path, secure: cookie.isSecure, expires: cookie.expiresDate,
                                    hostOnly: !hasDomain)
            }
        }
    }

    private static func splitCombined(_ value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #",(?=\s*[^;,\s]+=)"#) else { return [value] }
        let range = NSRange(value.startIndex..., in: value)
        let pieces = regex.matches(in: value, range: range).compactMap { Range($0.range, in: value) }
        guard !pieces.isEmpty else { return [value] }
        var output: [String] = []
        var start = value.startIndex
        for piece in pieces {
            output.append(String(value[start..<piece.lowerBound]).trimmingCharacters(in: .whitespaces))
            start = piece.upperBound
        }
        output.append(String(value[start...]).trimmingCharacters(in: .whitespaces))
        return output.filter { !$0.isEmpty }
    }
}

struct NativeHTTPTrace: Codable, Equatable {
    var phase: String
    var method: String
    var url: String
    var status: Int
    var location: String?
    var setCookieNames: [String]
    var sentCookieNames: [String]
    var origin: String?
    var referer: String?
    var bodyShape: [String: [String]]
    var authCode: String?
    var loginTokenPresent: Bool?
    var secondFactorRequired: Bool?
    var ticketFound: Bool?
    var ticketHost: String?
    var captchaCheckVerified: Bool?
    var captchaRequired: Bool?
}

struct NativeHTTPReply: @unchecked Sendable {
    var data: Data
    var response: HTTPURLResponse
}

protocol NativeHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> NativeHTTPReply
}

private final class NativeURLSessionTransport: NSObject, NativeHTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!

    override init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        super.init()
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> NativeHTTPReply {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativeError.protocolFailure("服务器没有返回 HTTP 响应。")
        }
        return NativeHTTPReply(data: data, response: http)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class NativeHTTP: @unchecked Sendable {
    fileprivate static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private let lock = NSLock()
    private let transport: NativeHTTPTransport
    private var cookieRecords: [NativeCookie]
    private var recordedTrace: [NativeHTTPTrace] = []

    init(cookies: [NativeCookie] = [], transport: NativeHTTPTransport? = nil) {
        cookieRecords = cookies
        self.transport = transport ?? NativeURLSessionTransport()
    }

    var trace: [NativeHTTPTrace] {
        lock.lock(); defer { lock.unlock() }
        return recordedTrace
    }

    func request(_ url: URL, method: String = "GET", body: Data? = nil,
                 headers: [String: String] = [:], maxRedirects: Int = 12) async throws -> (Data, HTTPURLResponse) {
        var currentURL = url
        var currentMethod = method.uppercased()
        var currentBody = body
        var visited = Set([url.absoluteString])
        var redirects = 0

        while true {
            var request = URLRequest(url: currentURL)
            request.httpMethod = currentMethod
            request.httpBody = currentBody
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            let currentCookies = cookies()
            let cookieHeader = NativeCookieHeader.value(currentCookies, for: currentURL)
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

            let reply = try await transport.send(request)
            let setCookieHeaders = NativeResponseCookies.headers(reply.response)
            let parsedCookies = NativeResponseCookies.parse(reply.response)
            store(parsedCookies)
            let location = reply.response.value(forHTTPHeaderField: "Location")
            appendTrace(NativeHTTPTrace(
                phase: Self.phase(for: currentURL, previous: trace),
                method: currentMethod,
                url: Self.redactedURL(currentURL),
                status: reply.response.statusCode,
                location: location.flatMap { URL(string: $0, relativeTo: currentURL)?.absoluteURL }.map(Self.redactedURL),
                setCookieNames: setCookieHeaders.compactMap(Self.cookieName),
                sentCookieNames: cookieHeader.map(Self.cookieNames) ?? [],
                origin: Self.redactedHeaderURL(headers.first(where: { $0.key.caseInsensitiveCompare("Origin") == .orderedSame })?.value),
                referer: Self.redactedHeaderURL(headers.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?.value),
                bodyShape: Self.bodyShape(currentBody, contentType: headers.first(where: { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame })?.value),
                authCode: nil, loginTokenPresent: nil, secondFactorRequired: nil,
                ticketFound: nil, ticketHost: nil, captchaCheckVerified: nil, captchaRequired: nil
            ))

            guard [301, 302, 303, 307, 308].contains(reply.response.statusCode), let location else {
                return (reply.data, reply.response)
            }
            guard redirects < maxRedirects else { throw NativeError.protocolFailure("重定向次数超过上限。") }
            guard let nextURL = URL(string: location, relativeTo: currentURL)?.absoluteURL else {
                throw NativeError.protocolFailure("服务器返回了无效的重定向地址。")
            }
            guard visited.insert(nextURL.absoluteString).inserted else {
                throw NativeError.protocolFailure("检测到重定向循环。")
            }
            if reply.response.statusCode == 303 || ((reply.response.statusCode == 301 || reply.response.statusCode == 302) && currentMethod != "GET" && currentMethod != "HEAD") {
                if currentMethod != "HEAD" { currentMethod = "GET" }
                currentBody = nil
            }
            currentURL = nextURL
            redirects += 1
        }
    }

    func cookies() -> [NativeCookie] {
        lock.lock(); defer { lock.unlock() }
        return cookieRecords.filter { $0.expires.map { $0 > Date() } ?? true }
    }

    private func store(_ cookies: [NativeCookie]) {
        guard !cookies.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        for cookie in cookies {
            cookieRecords.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            if cookie.expires.map({ $0 > Date() }) ?? true { cookieRecords.append(cookie) }
        }
    }

    private func appendTrace(_ item: NativeHTTPTrace) {
        lock.lock(); defer { lock.unlock() }
        recordedTrace.append(item)
    }

    func annotateLast(_ update: (inout NativeHTTPTrace) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !recordedTrace.isEmpty else { return }
        update(&recordedTrace[recordedTrace.count - 1])
    }

    private static func phase(for url: URL, previous: [NativeHTTPTrace]) -> String {
        let path = url.path
        if path == "/login/cas" { return previous.contains(where: { $0.phase == "authnEngine" }) ? "ticket" : "canvas-entry" }
        if path.contains("verifyCodeIsNeed") { return "captcha-precheck" }
        if path.contains("authExecute") { return "authExecute" }
        if path.contains("authnEngine") { return "authnEngine" }
        if path.contains("getJsPublicKey") || path.contains("queryAuthMethods") { return "auth-setup" }
        if path.contains("/users/self/profile") { return "canvas-profile" }
        return "other"
    }

    private static func redactedURL(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? "<invalid-url>"
    }

    private static func redactedHeaderURL(_ value: String?) -> String? {
        guard let value else { return nil }
        guard let url = URL(string: value) else { return "<invalid-url>" }
        return redactedURL(url)
    }

    private static func cookieName(_ header: String) -> String? {
        let name = header.split(separator: "=", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? nil : name
    }

    private static func cookieNames(_ header: String) -> [String] {
        header.split(separator: ";").compactMap { cookieName(String($0)) }
    }

    private static func bodyShape(_ body: Data?, contentType: String?) -> [String: [String]] {
        guard let body, !body.isEmpty else { return [:] }
        if contentType?.lowercased().contains("json") == true,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            return object.mapValues { value in
                (value as? [String: Any]).map { Array($0.keys).sorted() } ?? []
            }
        }
        guard let value = String(data: body, encoding: .utf8) else { return [:] }
        let names = URLComponents(string: "?\(value)")?.queryItems?.map(\.name) ?? []
        return Dictionary(names.map { ($0, [String]()) }, uniquingKeysWith: { first, _ in first })
    }
}

enum NativeSecrets {
    private static let service = Bundle.main.bundleIdentifier ?? "cn.edu.fudan.fudanElearning"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String?, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

}

final class NativeUISAuthenticator {
    struct Preparation {
        var captchaRequired: Bool
        var captchaImage: String?
        var captchaCheckVerified: Bool
    }

    private struct LoginContext {
        var http: NativeHTTP
        var spaURL: String
        var lck: String
        var entityID: String
        var chainCode: String
        var moduleCode: String
        var requestType: String
        var publicKey: String
    }

    private var context: LoginContext?
    private var currentHTTP: NativeHTTP?
    private let canvasBase = URL(string: "https://elearning.fudan.edu.cn")!
    private let idBase = URL(string: "https://id.fudan.edu.cn")!

    var trace: [NativeHTTPTrace] { currentHTTP?.trace ?? [] }

    func prepare(username: String) async throws -> Preparation {
        let http = NativeHTTP()
        currentHTTP = http
        let (entryData, entryResponse) = try await http.request(canvasBase.appendingPathComponent("login/cas"))
        _ = entryData
        guard let spaURL = entryResponse.url, spaURL.host == "id.fudan.edu.cn",
              let parts = URLComponents(url: spaURL, resolvingAgainstBaseURL: false),
              let fragmentQuery = parts.fragment?.split(separator: "?", maxSplits: 1).dropFirst().first,
              let idp = URLComponents(string: "https://id.fudan.edu.cn/?\(fragmentQuery)"),
              let lck = idp.queryItems?.first(where: { $0.name == "lck" })?.value,
              let entityID = idp.queryItems?.first(where: { $0.name == "entityId" })?.value else {
            throw NativeError.protocolFailure("无法从统一身份认证页面读取登录参数。")
        }

        let keyData = try await postJSON("/idp/authn/getJsPublicKey", object: [:], http: http, referer: spaURL.absoluteString)
        guard let publicKey = CanvasJSON.string(CanvasJSON.object(keyData)["data"]), !publicKey.isEmpty else {
            throw NativeError.protocolFailure("无法获取统一身份认证的加密公钥。")
        }
        let methodsData = try await postJSON("/idp/authn/queryAuthMethods", object: ["lck": lck, "entityId": entityID], http: http, referer: spaURL.absoluteString)
        let methodsBody = CanvasJSON.object(methodsData)
        if CanvasJSON.bool(methodsBody["second"]) {
            throw NativeError.protocolFailure("该账号启用了二次验证，本应用暂不支持。请先在浏览器完成一次登录。")
        }
        let methods = CanvasJSON.array(methodsBody["data"])
        guard let method = methods.first(where: {
            CanvasJSON.string($0["moduleCode"]) == "userAndPwd" || (($0["moduleCodes"] as? [String]) ?? []).contains("userAndPwd")
        }), let chainCode = CanvasJSON.string(method["authChainCode"]) else {
            throw NativeError.protocolFailure("该账号没有开放用户名密码认证方式。")
        }
        let codes = (method["moduleCodes"] as? [String]) ?? []
        let moduleCode = codes.first ?? CanvasJSON.string(method["moduleCode"]) ?? "userAndPwd"
        context = LoginContext(http: http, spaURL: spaURL.absoluteString, lck: lck,
                              entityID: entityID, chainCode: chainCode,
                              moduleCode: moduleCode,
                              requestType: CanvasJSON.string(methodsBody["requestType"]) ?? "chain_type",
                              publicKey: publicKey)

        do {
            let captchaData = try await postJSON("/idp/authn/verifyCodeIsNeed", object: [
                "lang": "zh_CN", "loginName": username,
                "chainCode": chainCode, "authModuleCode": moduleCode,
            ], http: http, referer: spaURL.absoluteString)
            let captcha = CanvasJSON.object(captchaData)
            let required = CanvasJSON.bool(captcha["result"])
            http.annotateLast { $0.captchaCheckVerified = true; $0.captchaRequired = required }
            return Preparation(captchaRequired: required, captchaImage: CanvasJSON.string(captcha["pic"]), captchaCheckVerified: true)
        } catch {
            // 验证码预检失败不能阻断登录；真正提交前仍由 UIS 判断。
            return Preparation(captchaRequired: false, captchaImage: nil, captchaCheckVerified: false)
        }
    }

    func complete(username: String, password: String, captcha: String?) async throws -> ([NativeCookie], String) {
        var stage = "读取 UIS 登录状态"
        do {
        guard let context else { throw NativeError.protocolFailure("登录状态已过期，请重新准备后再试。") }
        self.context = nil
        stage = "加密 UIS 密码"
        let encrypted = try RSAHelper.encrypt(password, publicKeyBase64: context.publicKey)
        let body: [String: Any] = [
            "authModuleCode": context.moduleCode,
            "authChainCode": context.chainCode,
            "entityId": context.entityID,
            "requestType": context.requestType,
            "lck": context.lck,
            "authPara": ["loginName": username, "password": encrypted, "verifyCode": captcha ?? ""],
        ]
        stage = "UIS 账号密码验证"
        let result = CanvasJSON.object(try await postJSON("/idp/authn/authExecute", object: body, http: context.http, referer: context.spaURL))
        let authCode = result["code"].map { String(describing: $0) }
        let tokenPresent = !(CanvasJSON.string(result["loginToken"]) ?? "").isEmpty
        let secondFactor = CanvasJSON.bool(result["second"])
        context.http.annotateLast {
            $0.authCode = authCode
            $0.loginTokenPresent = tokenPresent
            $0.secondFactorRequired = secondFactor
        }
        if secondFactor {
            throw NativeError.protocolFailure("该账号需要二次验证，本应用暂不支持。")
        }
        guard "\(result["code"] ?? "")" == "200", let token = CanvasJSON.string(result["loginToken"]), !token.isEmpty else {
            throw Self.classify(result["message"] as? String, code: result["code"])
        }
        stage = "UIS 换取 CAS 服务票据"
        var form = URLRequest(url: URL(string: "/idp/authCenter/authnEngine?locale=zh-CN", relativeTo: idBase)!)
        form.httpMethod = "POST"
        form.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        form.setValue(context.spaURL, forHTTPHeaderField: "Referer")
        var formComponents = URLComponents()
        formComponents.queryItems = [URLQueryItem(name: "loginToken", value: token)]
        form.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)
        let (htmlData, _) = try await context.http.request(form.url!, method: form.httpMethod!, body: form.httpBody,
                                                           headers: ["Content-Type": "application/x-www-form-urlencoded", "Origin": idBase.absoluteString, "Referer": context.spaURL])
        let html = String(decoding: htmlData, as: UTF8.self)
        guard let action = Self.attribute(in: Self.tag(id: "logon", html: html), name: "action"),
              let ticket = Self.attribute(in: Self.tag(id: "ticket", html: html), name: "value"),
              var target = URLComponents(string: action) else {
            context.http.annotateLast { $0.ticketFound = false }
            throw NativeError.protocolFailure("登录成功，但没有从认证服务器返回页面中找到服务票据。")
        }
        context.http.annotateLast { $0.ticketFound = true; $0.ticketHost = target.host }
        var items = target.queryItems ?? []
        items.removeAll { $0.name == "ticket" }
        items.append(URLQueryItem(name: "ticket", value: ticket))
        target.queryItems = items
        guard let ticketURL = target.url else { throw NativeError.protocolFailure("服务票据链接无效。") }
        stage = "Canvas CAS 服务票据校验"
        let (_, finalResponse) = try await context.http.request(ticketURL)
        guard finalResponse.url?.host == "elearning.fudan.edu.cn" else {
            throw NativeError.protocolFailure("票据校验后没有返回 eLearning。")
        }
        return (context.http.cookies(), finalResponse.url?.absoluteString ?? "")
        } catch {
            throw NativeError.protocolFailure("\(stage)失败：\(error.localizedDescription)")
        }
    }

    private func postJSON(_ path: String, object: [String: Any], http: NativeHTTP, referer: String) async throws -> Any {
        let url = URL(string: path, relativeTo: idBase)!
        let (data, response) = try await http.request(url, method: "POST", body: try JSONSerialization.data(withJSONObject: object), headers: [
            "Content-Type": "application/json", "Accept": "application/json",
            "Origin": idBase.absoluteString, "Referer": referer,
        ])
        guard (200..<300).contains(response.statusCode) else {
            throw Self.classify(String(decoding: data, as: UTF8.self), code: response.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func classify(_ message: String?, code: Any?) -> NativeError {
        let value = message ?? ""
        if value.contains("用户名或密码错误") || value.contains("密码有误") { return .protocolFailure("学号或密码不正确。") }
        if value.contains("验证码") { return .protocolFailure("统一身份认证要求输入验证码，请重新登录并填写验证码。") }
        if value.contains("锁定") || value.contains("冻结") { return .protocolFailure("账号已被锁定，请等待自动解锁或联系信息办。") }
        if value.contains("维护") { return .protocolFailure("统一身份认证正在维护，请稍后再试。") }
        return .protocolFailure("统一身份认证返回未预期的结果（code=\(code ?? "?")）。\(value)")
    }

    private static func tag(id: String, html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: id)
        let pattern = #"<[a-zA-Z][\w:-]*\b[^>]*\bid\s*=\s*(["'])"# + escaped + #"\1[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else { return nil }
        return String(html[range])
    }

    private static func attribute(in tag: String?, name: String) -> String? {
        guard let tag else { return nil }
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for index in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: index), in: tag) { return String(tag[range]) }
        }
        return nil
    }
}

enum RSAHelper {
    static func encrypt(_ plaintext: String, publicKeyBase64: String) throws -> String {
        guard let der = Data(base64Encoded: publicKeyBase64), let raw = subjectPublicKey(der) else {
            throw NativeError.protocolFailure("统一身份认证公钥格式无效。")
        }
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
                                         kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(raw as CFData, attributes as CFDictionary, &error) else {
            if let failure = error?.takeRetainedValue() { throw failure as Error }
            throw NativeError.protocolFailure("无法读取统一身份认证公钥。")
        }
        let algorithm = SecKeyAlgorithm.rsaEncryptionPKCS1
        guard SecKeyIsAlgorithmSupported(key, .encrypt, algorithm),
              let encrypted = SecKeyCreateEncryptedData(key, algorithm, Data(plaintext.utf8) as CFData, &error) as Data? else {
            if let failure = error?.takeRetainedValue() { throw failure as Error }
            throw NativeError.protocolFailure("无法加密登录密码。")
        }
        return encrypted.base64EncodedString()
    }

    private static func subjectPublicKey(_ der: Data) -> Data? {
        var outerCursor = 0
        guard let outer = readTLV(der, cursor: &outerCursor), outer.tag == 0x30 else { return nil }
        var cursor = 0
        guard readTLV(outer.bytes, cursor: &cursor)?.tag == 0x30,
              let bitString = readTLV(outer.bytes, cursor: &cursor), bitString.tag == 0x03,
              bitString.bytes.count > 1, bitString.bytes[bitString.bytes.startIndex] == 0 else { return nil }
        return bitString.bytes.dropFirst()
    }

    private static func readTLV(_ data: Data, cursor: inout Int) -> (tag: UInt8, bytes: Data)? {
        guard cursor + 2 <= data.count else { return nil }
        let tag = data[cursor]
        cursor += 1
        var length = Int(data[cursor])
        cursor += 1
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count > 0, count <= 4, cursor + count <= data.count else { return nil }
            length = 0
            for _ in 0..<count { length = (length << 8) | Int(data[cursor]); cursor += 1 }
        }
        guard cursor + length <= data.count else { return nil }
        let bytes = data.subdata(in: cursor..<(cursor + length))
        cursor += length
        return (tag, bytes)
    }
}

struct CanvasAPI {
    let http: NativeHTTP
    static let base = URL(string: "https://elearning.fudan.edu.cn")!

    func get(_ path: String, query: [URLQueryItem] = []) async throws -> Any {
        var components = URLComponents(url: URL(string: path, relativeTo: Self.base)!, resolvingAgainstBaseURL: true)!
        components.queryItems = query.isEmpty ? nil : query
        return try await json(components.url!)
    }

    func pages(_ path: String, query: [URLQueryItem] = []) async throws -> [[String: Any]] {
        var components = URLComponents(url: URL(string: path, relativeTo: Self.base)!, resolvingAgainstBaseURL: true)!
        components.queryItems = query
        var next = components.url
        var output: [[String: Any]] = []
        var pages = 0
        while let url = next, pages < 40 {
            let (data, response) = try await http.request(url, headers: ["Accept": "application/json"])
            guard (200..<300).contains(response.statusCode) else { throw responseError(data, response: response) }
            let value = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            output.append(contentsOf: value)
            next = Self.nextLink(response.value(forHTTPHeaderField: "Link"))
            pages += 1
        }
        return output
    }

    func json(_ url: URL) async throws -> Any {
        let (data, response) = try await http.request(url, headers: ["Accept": "application/json"])
        guard (200..<300).contains(response.statusCode) else { throw responseError(data, response: response) }
        do { return try JSONSerialization.jsonObject(with: data) }
        catch { throw NativeError.protocolFailure("Canvas 返回了无法解析的数据。") }
    }

    private func responseError(_ data: Data, response: HTTPURLResponse) -> NativeError {
        let text = String(decoding: data, as: UTF8.self)
        if response.statusCode == 401 || response.statusCode == 403 { return .http(response.statusCode, "无权访问或登录状态已失效") }
        return .http(response.statusCode, String(text.prefix(180)))
    }

    static func nextLink(_ value: String?) -> URL? {
        guard let value else { return nil }
        for part in value.split(separator: ",") {
            let text = String(part)
            guard text.range(of: #"rel\s*=\s*"?next"?"#, options: [.regularExpression, .caseInsensitive], range: nil) != nil,
                  let start = text.firstIndex(of: "<"), let end = text.firstIndex(of: ">"), start < end else { continue }
            return URL(string: String(text[text.index(after: start)..<end]))
        }
        return nil
    }

    func buildSnapshot(previous: NativeSnapshot?, full: Bool, scope: String,
                       progress: @escaping @Sendable (Int, Int, String) -> Void) async throws -> NativeSnapshot {
        let profile: [String: Any]
        do {
            profile = CanvasJSON.object(try await get("/api/v1/users/self/profile"))
        } catch {
            if Self.isAuthStatus(error) { throw NativeError.authExpired }
            throw error
        }
        let includes = ["enrollments", "term", "total_scores"]
        var wireCourses = try await pages("/api/v1/courses", query: [
            URLQueryItem(name: "include[]", value: includes[0]),
            URLQueryItem(name: "include[]", value: includes[1]),
            URLQueryItem(name: "include[]", value: includes[2]),
            URLQueryItem(name: "per_page", value: "100"),
        ])
        do {
            wireCourses += try await pages("/api/v1/courses", query: [
                URLQueryItem(name: "include[]", value: includes[0]),
                URLQueryItem(name: "include[]", value: includes[1]),
                URLQueryItem(name: "include[]", value: includes[2]),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "enrollment_state", value: "completed"),
            ])
        } catch { }
        var unique: [Int: [String: Any]] = [:]
        for course in wireCourses where CanvasJSON.string(course["workflow_state"]) == "available" {
            if let id = CanvasJSON.int(course["id"]) { unique[id] = course }
        }
        wireCourses = Array(unique.values)
        if wireCourses.isEmpty {
            wireCourses = try await pages("/api/v1/courses", query: [URLQueryItem(name: "per_page", value: "100")])
                .filter { CanvasJSON.string($0["workflow_state"]) == "available" }
        }
        var nicknames: [Int: String] = [:]
        if let names = try? await pages("/api/v1/users/self/course_nicknames", query: [URLQueryItem(name: "per_page", value: "100")]) {
            for item in names {
                if let id = CanvasJSON.int(item["course_id"]) {
                    nicknames[id] = CanvasJSON.string(item["nickname"]).flatMap { $0.isEmpty ? nil : $0 } ?? CanvasJSON.string(item["name"])
                }
            }
        }
        let now = Date()
        let oldCourses = Dictionary(uniqueKeysWithValues: (previous?.courses ?? []).map { ($0.id, $0) })
        let oldRows = Dictionary(grouping: previous?.assignments ?? [], by: \.courseID)
        var courses: [NativeCourse] = []
        var rows: [NativeAssignment] = []
        var warnings: [String] = []
        var reusedCourseCount = 0
        let shouldReuse = !full && scope != "all"
        for (index, wire) in wireCourses.sorted(by: { (CanvasJSON.string($0["name"]) ?? "") < (CanvasJSON.string($1["name"]) ?? "") }).enumerated() {
            guard let id = CanvasJSON.int(wire["id"]) else { continue }
            let termWire = CanvasJSON.object(wire["term"])
            let termID = CanvasJSON.int(termWire["id"]) ?? CanvasJSON.int(wire["enrollment_term_id"])
            let termEnd = CanvasJSON.string(termWire["end_at"]) ?? CanvasJSON.string(wire["end_at"])
            let cached = oldCourses[id]
            if shouldReuse, let cached, let end = Beijing.parse(termEnd ?? cached.termEndAt), end < now,
               let savedRows = oldRows[id] {
                courses.append(cached)
                rows.append(contentsOf: savedRows)
                reusedCourseCount += 1
                progress(index + 1, wireCourses.count, cached.displayName)
                continue
            }
            let displayName = nicknames[id] ?? CanvasJSON.string(wire["name"]) ?? "课程 \(id)"
            async let groupsResult = pages("/api/v1/courses/\(id)/assignment_groups", query: [URLQueryItem(name: "per_page", value: "100")])
            async let assignmentsResult = pages("/api/v1/courses/\(id)/assignments", query: [
                URLQueryItem(name: "include[]", value: "submission"),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "order_by", value: "due_at"),
            ])
            let groups: [[String: Any]]
            do { groups = try await groupsResult }
            catch {
                try await confirmSessionAfterAuthStatus(error)
                warnings.append("\(displayName)：作业分组获取失败（\(error.localizedDescription)）")
                groups = []
            }
            let assignments: [[String: Any]]
            do { assignments = try await assignmentsResult }
            catch {
                try await confirmSessionAfterAuthStatus(error)
                warnings.append("\(displayName)：作业列表获取失败（\(error.localizedDescription)）")
                assignments = []
            }
            let groupMap = Dictionary(uniqueKeysWithValues: groups.compactMap { item -> (Int, [String: Any])? in
                guard let id = CanvasJSON.int(item["id"]) else { return nil }; return (id, item)
            })
            let nativeRows = assignments.compactMap { raw -> NativeAssignment? in
                guard let aid = CanvasJSON.int(raw["id"]) else { return nil }
                let sub = CanvasJSON.object(raw["submission"])
                let groupID = CanvasJSON.int(raw["assignment_group_id"]) ?? 0
                let group = groupMap[groupID] ?? [:]
                let excused = CanvasJSON.bool(sub["excused"])
                let score = excused ? nil : CanvasJSON.double(sub["score"])
                return NativeAssignment(id: aid, courseID: id, courseName: displayName,
                                        name: CanvasJSON.string(raw["name"]) ?? "",
                                        groupID: groupID,
                                        groupName: CanvasJSON.string(group["name"]) ?? "未分组",
                                        dueAt: CanvasJSON.string(raw["due_at"]),
                                        pointsPossible: CanvasJSON.double(raw["points_possible"]),
                                        groupWeight: CanvasJSON.double(group["group_weight"]) ?? 0,
                                        score: score, grade: CanvasJSON.string(sub["grade"]),
                                        submittedAt: CanvasJSON.string(sub["submitted_at"]),
                                        gradedAt: CanvasJSON.string(sub["graded_at"]),
                                        workflowState: CanvasJSON.string(sub["workflow_state"]) ?? "unsubmitted",
                                        late: CanvasJSON.bool(sub["late"]), missing: CanvasJSON.bool(sub["missing"]),
                                        excused: excused, omitFromFinalGrade: CanvasJSON.bool(raw["omit_from_final_grade"]),
                                        htmlURL: CanvasJSON.string(raw["html_url"]),
                                        descriptionExcerpt: NativeDomain.truncate(NativeDomain.summarize(CanvasJSON.string(raw["description"])), limit: 600))
            }
            rows.append(contentsOf: nativeRows)
            courses.append(makeCourse(wire, id: id, displayName: displayName, nickname: nicknames[id], termID: termID,
                                      termWire: termWire, rows: nativeRows))
            progress(index + 1, wireCourses.count, displayName)
        }
        var todos: [NativeTodo] = []
        if let items = try? await get("/api/v1/users/self/todo") as? [[String: Any]] {
            let names = Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0.displayName) })
            for item in items {
                let assignment = CanvasJSON.object(item["assignment"])
                let quiz = CanvasJSON.object(item["quiz"])
                let isAssignment = !assignment.isEmpty
                let payload = isAssignment ? assignment : quiz
                guard !payload.isEmpty else { continue }
                let courseID = CanvasJSON.int(item["course_id"]) ?? CanvasJSON.int(assignment["course_id"])
                todos.append(NativeTodo(title: CanvasJSON.string(payload["name"]) ?? CanvasJSON.string(payload["title"]) ?? "",
                                        courseName: names[courseID ?? -1] ?? "课程 \(courseID ?? 0)",
                                        kind: isAssignment ? "assignment" : "quiz", courseID: courseID,
                                        assignmentID: CanvasJSON.int(assignment["id"]),
                                        dueAt: CanvasJSON.string(payload["due_at"]),
                                        pointsPossible: CanvasJSON.double(payload["points_possible"]),
                                        htmlURL: CanvasJSON.string(payload["html_url"]) ?? CanvasJSON.string(item["html_url"])))
            }
        }
        courses.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        rows.sort { (Beijing.parse($0.dueAt) ?? .distantPast) > (Beijing.parse($1.dueAt) ?? .distantPast) }
        let terms = makeTerms(courses, now: now)
        let todoSorted = todos.sorted { (Beijing.parse($0.dueAt) ?? .distantFuture) < (Beijing.parse($1.dueAt) ?? .distantFuture) }
        return NativeSnapshot(fetchedAt: Date(),
                              profile: NativeProfile(id: CanvasJSON.int(profile["id"]) ?? 0,
                                                     name: CanvasJSON.string(profile["name"]) ?? "复旦同学",
                                                     loginID: CanvasJSON.string(profile["login_id"]),
                                                     primaryEmail: CanvasJSON.string(profile["primary_email"])),
                              courses: courses, terms: terms, assignments: rows, todo: todoSorted,
                              warnings: warnings, reusedCourseCount: reusedCourseCount)
    }

    private static func isAuthStatus(_ error: Error) -> Bool {
        guard let native = error as? NativeError, case let .http(code, _) = native else { return false }
        return code == 401 || code == 403
    }

    private func confirmSessionAfterAuthStatus(_ error: Error) async throws {
        guard Self.isAuthStatus(error) else { return }
        do {
            _ = try await get("/api/v1/users/self/profile")
        } catch {
            if Self.isAuthStatus(error) { throw NativeError.authExpired }
        }
    }

    private func makeCourse(_ wire: [String: Any], id: Int, displayName: String, nickname: String?, termID: Int?, termWire: [String: Any], rows: [NativeAssignment]) -> NativeCourse {
        let enrollments = CanvasJSON.array(wire["enrollments"])
        let enrollment = enrollments.first(where: {
            CanvasJSON.string($0["type"]) == "StudentEnrollment" || CanvasJSON.string($0["role"]) == "StudentEnrollment"
        }) ?? enrollments.first ?? [:]
        let grades = CanvasJSON.object(enrollment["grades"])
        var groupTotals: [Int: (weight: Double, earned: Double, possible: Double)] = [:]
        for row in rows {
            var total = groupTotals[row.groupID] ?? (row.groupWeight, 0, 0)
            if !row.excused && !row.omitFromFinalGrade,
               let score = row.score, let points = row.pointsPossible, points > 0 {
                total.earned += score; total.possible += points
            }
            groupTotals[row.groupID] = total
        }
        let weighted = NativeDomain.weightedScore(Array(groupTotals.values))
        let earned = groupTotals.values.reduce(0) { $0 + $1.earned }
        let possible = groupTotals.values.reduce(0) { $0 + $1.possible }
        let computedCurrent = CanvasJSON.double(enrollment["computed_current_score"]) ?? CanvasJSON.double(grades["current_score"])
        let computedFinal = CanvasJSON.double(enrollment["computed_final_score"]) ?? CanvasJSON.double(grades["final_score"])
        let termName = CanvasJSON.string(termWire["name"]).flatMap { $0.isEmpty ? nil : $0 } ?? (termID == nil ? "未指定学期" : "学期 #\(termID!)")
        return NativeCourse(id: id, name: CanvasJSON.string(wire["name"]) ?? "", displayName: displayName,
                            courseCode: CanvasJSON.string(wire["course_code"]) ?? "", termName: termName, termID: termID,
                            termStartAt: CanvasJSON.string(termWire["start_at"]), termEndAt: CanvasJSON.string(termWire["end_at"]),
                            nickname: nickname, startAt: CanvasJSON.string(wire["start_at"]), endAt: CanvasJSON.string(wire["end_at"]),
                            currentScore: computedCurrent ?? weighted, finalScore: computedFinal,
                            currentGrade: CanvasJSON.string(enrollment["computed_current_grade"]) ?? CanvasJSON.string(grades["current_grade"]),
                            finalGrade: CanvasJSON.string(enrollment["computed_final_grade"]) ?? CanvasJSON.string(grades["final_grade"]),
                            earnedPoints: possible > 0 ? earned : nil, possiblePointsGraded: possible > 0 ? possible : nil,
                            assignmentCount: rows.count, submittedCount: rows.filter { $0.workflowState != "unsubmitted" }.count,
                            gradedCount: rows.filter { $0.score != nil }.count, missingCount: rows.filter(\.missing).count,
                            lateCount: rows.filter(\.late).count,
                            upcomingCount: rows.filter { Beijing.parse($0.dueAt).map { $0 > Date() } ?? false }.count)
    }

    func makeTerms(_ courses: [NativeCourse], now: Date) -> [NativeTerm] {
        var terms: [Int?: NativeTerm] = [:]
        for course in courses {
            if var term = terms[course.termID] {
                term.courseCount += 1
                if let start = course.termStartAt, term.startAt == nil || (Beijing.parse(start) ?? .distantFuture) < (Beijing.parse(term.startAt) ?? .distantFuture) { term.startAt = start }
                if let end = course.termEndAt, term.endAt == nil || (Beijing.parse(end) ?? .distantPast) > (Beijing.parse(term.endAt) ?? .distantPast) { term.endAt = end }
                terms[course.termID] = term
            } else {
                terms[course.termID] = NativeTerm(id: course.termID, name: course.termName,
                                                  startAt: course.termStartAt, endAt: course.termEndAt,
                                                  isCurrent: false, courseCount: 1)
            }
        }
        var result = Array(terms.values).sorted {
            let a = Beijing.parse($0.startAt) ?? .distantPast
            let b = Beijing.parse($1.startAt) ?? .distantPast
            return a == b ? ($0.id ?? -1) > ($1.id ?? -1) : a > b
        }
        let currentIndex = result.firstIndex(where: {
            guard let start = Beijing.parse($0.startAt), let end = Beijing.parse($0.endAt) else { return false }
            return start <= now && now <= end
        }) ?? result.firstIndex(where: { Beijing.parse($0.startAt).map { $0 <= now } ?? false }) ?? result.indices.first
        if let currentIndex { result[currentIndex].isCurrent = true }
        let duplicateNames = Dictionary(grouping: result.indices, by: { result[$0].name }).filter { $0.value.count > 1 }
        for indices in duplicateNames.values {
            for index in indices { result[index].name += "（#\(result[index].id.map(String.init) ?? "无")）" }
        }
        return result
    }
}

struct NativeFile: Identifiable, Hashable {
    var id: Int
    var name: String
    var url: URL
    var size: Int64
    var contentType: String?
    var folderID: Int?
    var hidden: Bool
}

struct NativeFileFolder: Identifiable, Hashable {
    var id: Int
    var name: String
    var parentID: Int?
    var position: Int? = nil
}

struct NativeFileNode: Identifiable, Hashable {
    var id: String
    var name: String
    var path: String
    var file: NativeFile?
    var children: [NativeFileNode]
    var isFolder: Bool { file == nil }
}

enum NativeFileTree {
    static func build(folders: [NativeFileFolder], files: [NativeFile]) -> NativeFileNode {
        let folderPositions = Dictionary(uniqueKeysWithValues: folders.compactMap { folder in
            folder.position.map { (folder.id, $0) }
        })
        func sort(_ nodes: [NativeFileNode]) -> [NativeFileNode] {
            nodes.sorted {
                if $0.isFolder != $1.isFolder { return $0.isFolder }
                if $0.isFolder {
                    let lhsID = Int($0.id.dropFirst("folder:".count))
                    let rhsID = Int($1.id.dropFirst("folder:".count))
                    let lhs = lhsID.flatMap { folderPositions[$0] }
                    let rhs = rhsID.flatMap { folderPositions[$0] }
                    if let lhs, let rhs, lhs != rhs { return lhs < rhs }
                    if lhs != nil && rhs == nil { return true }
                    if lhs == nil && rhs != nil { return false }
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        let foldersByParent = Dictionary(grouping: folders, by: \.parentID)
        let filesByFolder = Dictionary(grouping: files.filter { !$0.hidden }, by: \.folderID)
        func children(parent: Int?, prefix: String, ancestors: Set<Int>) -> [NativeFileNode] {
            var nodes = (filesByFolder[parent] ?? []).map { file in
                NativeFileNode(id: "file:\(file.id)", name: file.name,
                               path: [prefix, file.name].filter { !$0.isEmpty }.joined(separator: "/"),
                               file: file, children: [])
            }
            for folder in foldersByParent[parent] ?? [] where !ancestors.contains(folder.id) {
                let path = [prefix, folder.name].filter { !$0.isEmpty }.joined(separator: "/")
                nodes.append(NativeFileNode(id: "folder:\(folder.id)", name: folder.name, path: path,
                                            file: nil, children: children(parent: folder.id, prefix: path,
                                                                         ancestors: ancestors.union([folder.id]))))
            }
            return sort(nodes)
        }
        return NativeFileNode(id: "root", name: "课程文件", path: "", file: nil,
                              children: children(parent: nil, prefix: "", ancestors: []))
    }

    static func flatten(_ node: NativeFileNode) -> [NativeFile] {
        if let file = node.file { return [file] }
        return node.children.flatMap(flatten)
    }

    static func flattenNodes(_ node: NativeFileNode) -> [NativeFileNode] {
        if node.file != nil { return [node] }
        return node.children.flatMap(flattenNodes)
    }
}

struct NativeDownloadProgress {
    var total = 0
    var completed = 0
    var skipped = 0
    var failed = 0
    var bytesReceived: Int64 = 0
    var bytesTotal: Int64 = 0
    var currentName = ""
    var currentReceived: Int64 = 0
    var currentTotal: Int64 = 0
}

struct NativeDownloadTarget {
    var file: NativeFile
    var relativePath: String
}

enum NativeDownloadPaths {
    static func plan(term: String, course: String, nodes: [NativeFileNode]) -> [NativeDownloadTarget] {
        var used: Set<String> = []
        return nodes.compactMap { node in
            guard let file = node.file else { return nil }
            let folder = node.path.split(separator: "/").dropLast().map { sanitize(String($0)) }
            let name = sanitize(file.name)
            let base = ([sanitize(term), sanitize(course)] + folder).filter { !$0.isEmpty }
            let parent = base.joined(separator: "/")
            let dot = name.lastIndex(of: ".")
            let hasExtension = dot.map { $0 != name.startIndex } ?? false
            let stem = dot.map { String(name[..<$0]) } ?? name
            let suffix = dot.map { String(name[$0...]) } ?? ""
            var candidate = name
            var number = 2
            while used.contains(([parent, candidate].filter { !$0.isEmpty }.joined(separator: "/")).lowercased()) {
                candidate = "\(stem) (\(number))\(suffix)"
                number += 1
            }
            let path = [parent, candidate].filter { !$0.isEmpty }.joined(separator: "/")
            used.insert(path.lowercased())
            return NativeDownloadTarget(file: file, relativePath: path)
        }
    }

    static func sanitize(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\0")
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if value.isEmpty || value == "." || value == ".." { return "_" }
        if value.count > 120 {
            let ext = value.lastIndex(of: ".").flatMap { index in
                value.distance(from: index, to: value.endIndex) <= 12 ? String(value[index...]) : nil
            } ?? ""
            value = String(value.prefix(120 - ext.count)) + ext
        }
        let stem = value.split(separator: ".", maxSplits: 1).first.map { String($0) }?.lowercased() ?? value.lowercased()
        let reserved = Set(["con", "prn", "aux", "nul"] + (1...9).flatMap { ["com\($0)", "lpt\($0)"] })
        return reserved.contains(stem) ? "_\(value)" : value
    }
}

extension CanvasAPI {
    func courseFiles(_ courseID: Int) async throws -> NativeFileNode {
        async let folderRows = pages("/api/v1/courses/\(courseID)/folders", query: [URLQueryItem(name: "per_page", value: "100")])
        async let fileRows = pages("/api/v1/courses/\(courseID)/files", query: [URLQueryItem(name: "per_page", value: "100")])
        let folders = try await folderRows.compactMap { raw -> NativeFileFolder? in
            guard let id = CanvasJSON.int(raw["id"]) else { return nil }
            return NativeFileFolder(id: id, name: CanvasJSON.string(raw["name"]) ?? "文件夹 \(id)",
                                    parentID: CanvasJSON.int(raw["parent_folder_id"]), position: CanvasJSON.int(raw["position"]))
        }
        let files = try await fileRows.compactMap { raw -> NativeFile? in
            guard let id = CanvasJSON.int(raw["id"]), let text = CanvasJSON.string(raw["url"]),
                  let url = URL(string: text), !CanvasJSON.bool(raw["hidden"]),
                  !CanvasJSON.bool(raw["locked"]), !CanvasJSON.bool(raw["locked_for_user"]),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return NativeFile(id: id, name: CanvasJSON.string(raw["display_name"]) ?? CanvasJSON.string(raw["filename"]) ?? "文件 \(id)",
                              url: url, size: Int64(CanvasJSON.int(raw["size"]) ?? 0),
                              contentType: CanvasJSON.string(raw["content-type"]) ?? CanvasJSON.string(raw["content_type"]),
                              folderID: CanvasJSON.int(raw["folder_id"]), hidden: false)
        }
        return NativeFileTree.build(folders: folders, files: files)
    }

    func assignment(courseID: Int, assignmentID: Int) async throws -> [String: Any] {
        let value = try await get("/api/v1/courses/\(courseID)/assignments/\(assignmentID)", query: [URLQueryItem(name: "include[]", value: "submission")])
        guard let object = value as? [String: Any] else { throw NativeError.protocolFailure("作业详情格式无效。") }
        return object
    }
}

enum NativeReminderPlanner {
    struct Reminder: Identifiable {
        var id: Int
        var at: Date
        var day: String
        var title: String
        var body: String
    }

    static func make(tasks: [NativeTask], now: Date, account: String, muted: Set<String>) -> [Reminder] {
        let horizon = Beijing.addDays(30, to: Beijing.day(now))
        var grouped: [String: [NativeTask]] = [:]
        var triggers: [String: Date] = [:]
        for task in tasks {
            guard task.status == .pending, let due = task.dueAt, due > now, !muted.contains(task.id) else { continue }
            let day = Beijing.day(due)
            guard day < horizon else { continue }
            let parts = Beijing.calendar.dateComponents(in: Beijing.timeZone, from: due)
            let hour = parts.hour ?? 0
            let early = hour < 8 || (hour == 8 && (parts.minute ?? 0) == 0 && (parts.second ?? 0) == 0)
            let dayKey = Beijing.key(day)
            let group = "\(dayKey):\(early ? "early" : "morning")"
            var components = Beijing.calendar.dateComponents([.year, .month, .day], from: early ? Beijing.addDays(-1, to: day) : day)
            components.hour = early ? 20 : 8
            components.minute = 0
            guard let trigger = Beijing.calendar.date(from: components), trigger > now else { continue }
            grouped[group, default: []].append(task)
            triggers[group] = trigger
        }
        return grouped.compactMap { key, items in
            guard let trigger = triggers[key] else { return nil }
            let early = key.hasSuffix(":early")
            let title = early ? "明早有 \(items.count) 项作业截止" : "今天有 \(items.count) 项作业截止"
            let names = items.prefix(3).map(\.title).joined(separator: "、")
            let body = "\(names)\(items.count > 3 ? "等 \(items.count) 项" : "")。点击查看截止时间。"
            return Reminder(id: stableID("\(account):\(key)"), at: trigger, day: String(key.prefix(10)), title: title, body: body)
        }.sorted { $0.at < $1.at }.prefix(60).map { $0 }
    }

    private static func stableID(_ input: String) -> Int {
        var hash: UInt32 = 0x811c9dc5
        for byte in input.utf8 { hash = (hash ^ UInt32(byte)) &* 0x01000193 }
        return Int(hash & 0x7fffffff)
    }
}

final class NativeDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var task: URLSessionDownloadTask?
    private var progress: (@Sendable (Int64, Int64) -> Void)?
    private var allowedCookieDomains: Set<String> = []
    private var cookies: [NativeCookie] = []
    private let lock = NSLock()

    func download(_ file: NativeFile, destination: URL, cookies: [NativeCookie],
                  progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.destination = destination
        self.progress = progress
        self.cookies = cookies
        allowedCookieDomains = Set(cookies.compactMap { cookie in
            Self.domain(cookie.domain, matches: file.url.host ?? "") ? cookie.domain : nil
        })
        var request = URLRequest(url: file.url)
        if let cookieHeader = cookieHeader(for: file.url) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            task = session.downloadTask(with: request)
            task?.resume()
        }
    }

    func cancel() {
        task?.cancel()
        finish(.failure(CancellationError()))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var safeRequest = request
        if let url = request.url, let cookieHeader = cookieHeader(for: url) {
            safeRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        } else {
            safeRequest.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        completionHandler(safeRequest)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                throw NativeError.http(response.statusCode, "文件服务器拒绝了下载请求")
            }
            guard let destination else { throw NativeError.protocolFailure("下载保存位置无效。") }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let value = continuation
        continuation = nil
        lock.unlock()
        value?.resume(with: result)
        session?.finishTasksAndInvalidate()
    }

    private func cookieHeader(for url: URL) -> String? {
        NativeCookieHeader.value(cookies, for: url, permittedDomains: allowedCookieDomains)
    }

    private static func domain(_ cookieDomain: String, matches host: String) -> Bool {
        let lower = cookieDomain.lowercased()
        let domain = lower.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == domain || (lower.hasPrefix(".") && host.hasSuffix(".\(domain)"))
    }

}

enum NativeSummary {
    static func generate(title: String, description: String, config: NativeLLMConfig, apiKey: String) async -> (String, String?) {
        let plain = NativeDomain.summarize(description).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return ("", nil) }
        let fallback = NativeDomain.truncate(plain)
        guard plain.count > 100 else { return ("", nil) }
        guard config.enabled, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            return (fallback, nil)
        }
        let system = "你是课程作业的摘要助手。把用户给出的作业说明压缩成一句话简介，不超过 100 个汉字。只陈述要做什么、要交什么；不要复述截止时间、分值或评分标准，不要加前后缀。"
        let body: [String: Any] = ["model": config.model, "temperature": 0.2, "max_tokens": 200,
                                   "messages": [["role": "system", "content": system],
                                                ["role": "user", "content": "作业标题：\(title)\n\n作业说明：\n\(String(plain.prefix(4000)))"]]]
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return (fallback, "大模型接口暂不可用，已显示文本摘要。")
            }
            let json = CanvasJSON.object(try JSONSerialization.jsonObject(with: data))
            let choice = CanvasJSON.array(json["choices"]).first
            let message = CanvasJSON.object(CanvasJSON.object(choice)["message"])
            let text = CanvasJSON.string(message["content"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return (fallback, "大模型返回了空内容，已显示文本摘要。") }
            return (NativeDomain.truncate(text.trimmingCharacters(in: CharacterSet(charactersIn: "\"「」『』"))), nil)
        } catch { return (fallback, "大模型请求失败，已显示文本摘要。") }
    }
}
