import Foundation

/// Bounded chunk delivery avoids a per-byte async loop and cancels oversized responses immediately.
final class LectureTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var stopped = false
    init(limit: Int) { self.limit = limit }
    func receive(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> Data {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { callback in
                lock.lock()
                if stopped { lock.unlock(); callback.resume(throwing: CancellationError()); return }
                continuation = callback
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.dataTask(with: request)
                lock.unlock(); task.resume()
            }
        }, onCancel: { self.cancel() })
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock(); stopped = true
        let callback = continuation, connection = session
        continuation = nil; session = nil; data = Data(); lock.unlock()
        connection?.invalidateAndCancel(); callback?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let message: String
            switch code {
            case 401: message = "GitHub 令牌无效，请重新配置。"
            case 403, 429: message = "GitHub 请求受限，请稍后重试或配置只读令牌。"
            case 404: message = "找不到笔记分支或文件；私有仓库请检查读取权限。"
            default: message = "GitHub 同步失败（\(code)）。"
            }
            completionHandler(.cancel); finish(.failure(NativeError.protocolFailure(message))); return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(.failure(NativeError.protocolFailure("笔记文件超过支持的大小。"))); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        if stopped { lock.unlock(); return }
        if chunk.count > limit - data.count {
            lock.unlock(); finish(.failure(NativeError.protocolFailure("笔记文件超过支持的大小。"))); return
        }
        data.append(chunk); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { finish(.failure(NativeError.protocolFailure("无法连接 GitHub，请检查网络后重试。"))) }
        else { lock.lock(); let result = data; lock.unlock(); finish(.success(result)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
