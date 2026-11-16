// What the steps of a micro-app use outside SwiftKey: HTTP with a streamed body, the login keychain
// and notifications.
import Foundation
import Security
import SwiftKeyCore
import UserNotifications

/// A failure with a message for the result panel.
struct MicroAppServiceError: Error, CustomStringConvertible, LocalizedError {
    var description: String
    var errorDescription: String? { description }

    init(_ description: String) {
        self.description = description
    }
}

// MARK: HTTP

/// Sends a request with its own ephemeral session (no cookies, no cache) and gives the body while it comes.
enum MicroAppHTTP {
    static func send(_ request: MicroAppHTTPRequest) async throws -> MicroAppHTTPResponse {
        guard let url = URL(string: request.url) else { throw URLError(.badURL) }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.setValue("SwiftKey/\(AppVersion.marketing ?? "dev") (macOS; micro-app)", forHTTPHeaderField: "User-Agent")
        for header in request.headers { urlRequest.setValue(header.value, forHTTPHeaderField: header.name) }
        urlRequest.httpBody = request.body
        // The step's time limit stops the request; this only ends a connection that hangs.
        urlRequest.timeoutInterval = TimeInterval(MicroAppChecker.maxTimeLimit)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let delegate = StreamingDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: urlRequest)
        delegate.onTermination = { task.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(task, session: session, continuation: continuation)
            }
        } onCancel: {
            task.cancel()
        }
    }

    private final class StreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<MicroAppHTTPResponse, Error>?
        private let stream: AsyncThrowingStream<Data, Error>
        private let body: AsyncThrowingStream<Data, Error>.Continuation
        var onTermination: (@Sendable () -> Void)?

        override init() {
            (stream, body) = AsyncThrowingStream<Data, Error>.makeStream()
            super.init()
            body.onTermination = { [weak self] termination in
                if case .cancelled = termination { self?.onTermination?() }
            }
        }

        func start(_ task: URLSessionDataTask, session: URLSession, continuation: CheckedContinuation<MicroAppHTTPResponse, Error>) {
            lock.lock(); self.continuation = continuation; lock.unlock()
            task.resume()
        }

        private func takeContinuation() -> CheckedContinuation<MicroAppHTTPResponse, Error>? {
            lock.lock(); defer { lock.unlock() }
            let c = continuation
            continuation = nil
            return c
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completionHandler(.allow)
            takeContinuation()?.resume(returning: MicroAppHTTPResponse(status: status, body: stream))
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            body.yield(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                takeContinuation()?.resume(throwing: error)
                body.finish(throwing: error)
            } else {
                takeContinuation()?.resume(throwing: URLError(.badServerResponse))
                body.finish()
            }
            session.finishTasksAndInvalidate()
        }
    }
}

// MARK: Keychain

/// Reads `${keychain.SERVICE}`: the generic password with that service name in the login keychain.
enum MicroAppKeychain {
    static func password(service: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
                throw MicroAppServiceError("the keychain item `\(service)` is not text")
            }
            return text
        case errSecItemNotFound:
            throw MicroAppServiceError("no keychain item with the service `\(service)`; add one with `security add-generic-password -s '\(service)' -a \"$USER\" -w`")
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw MicroAppServiceError("access to the keychain item `\(service)` was refused")
        default:
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            throw MicroAppServiceError("cannot read the keychain item `\(service)`: \(message)")
        }
    }
}

// MARK: Notifications

/// Shows the notification of a `notify` step as SwiftKey.
enum MicroAppNotifier {
    /// Lets notifications show as banners also while SwiftKey is the active app.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list])
        }
    }

    nonisolated(unsafe) private static let presenter = Presenter()

    static func post(title: String, message: String) async throws {
        // The notification center needs an app bundle; a test binary has none.
        guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else {
            throw MicroAppServiceError("notifications need SwiftKey.app")
        }
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        let granted = try await center.requestAuthorization(options: [.alert])
        guard granted else {
            throw MicroAppServiceError("notifications for SwiftKey are off; turn them on in System Settings › Notifications › SwiftKey")
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message.count > 1000 ? String(message.prefix(1000)) + "…" : message
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
