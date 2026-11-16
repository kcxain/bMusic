import Foundation

/// Enforces the response budget while bytes arrive, including chunked responses.
public enum BoundedHTTPData {
    public static func load(session: URLSession, request: URLRequest, limit: Int,
                            accepts: @escaping @Sendable (HTTPURLResponse) -> Bool) async throws -> Data {
        let transfer = Transfer(limit: limit, accepts: accepts)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.start(session: session, request: request, continuation: continuation)
            }
        } onCancel: { transfer.cancel() }
    }

    private final class Transfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private let accepts: @Sendable (HTTPURLResponse) -> Bool
        private var task: URLSessionDataTask?
        private var continuation: CheckedContinuation<Data, Error>?
        private var cancelled = false
        private var data = Data()
        private var failure: Error?
        init(limit: Int, accepts: @escaping @Sendable (HTTPURLResponse) -> Bool) {
            self.limit = max(0, limit); self.accepts = accepts
        }
        func start(session: URLSession, request: URLRequest, continuation: CheckedContinuation<Data, Error>) {
            lock.lock()
            if cancelled {
                lock.unlock(); continuation.resume(throwing: CancellationError()); return
            }
            self.continuation = continuation
            let task = session.dataTask(with: request)
            task.delegate = self; self.task = task
            lock.unlock()
            task.resume()
        }
        func cancel() {
            lock.lock(); cancelled = true; let task = task; lock.unlock()
            task?.cancel()
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let accepted = (response as? HTTPURLResponse).map(accepts) == true
                && response.expectedContentLength <= Int64(limit)
            if !accepted {
                lock.lock(); failure = BMusicError.invalidResponse; lock.unlock()
            }
            completionHandler(accepted ? .allow : .cancel)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
            lock.lock()
            let exceeds = bytes.count > limit - data.count
            if exceeds { failure = BMusicError.invalidResponse }
            else if failure == nil { data.append(bytes) }
            lock.unlock()
            if exceeds { dataTask.cancel() }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let continuation = continuation
            self.continuation = nil; self.task = nil
            let result: Result<Data, Error>
            if cancelled { result = .failure(CancellationError()) }
            else if let error = failure ?? error { result = .failure(error) }
            else { result = .success(data) }
            data = Data()
            lock.unlock()
            continuation?.resume(with: result)
        }
    }
}
