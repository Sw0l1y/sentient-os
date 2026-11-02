// SchoolFeedFetch.swift
// Downloads an assignment feed once: an ephemeral URLSession (no cookies, no cache, no
// credentials), a 30-second request timeout, https only (a redirect to anything else is
// refused), and a size cap. Failures are classified into what the user can do about them:
// the school stopped sharing (401/403/404/410, or a page that is not a calendar), the server
// is having trouble (429/5xx), or the Mac could not reach it (offline, DNS, timeout).
// Privacy: the link is a bearer secret. No error here carries it or its text: the cases hold
// only status and URLError codes, so a Log line or a report can never echo the link.
// Foundation only, so Scripts/test_school_feed.py compiles it alone against a loopback server.
// Doc: Documentation - Sources - Local (Files, WhatsApp, iMessage, Notes).md

import Foundation

nonisolated enum SchoolFeedFetch {
    static let maximumBytes = 8 * 1024 * 1024
    static let timeout: TimeInterval = 30

    nonisolated enum Failure: Error, Equatable, Sendable {
        /// Not an https or webcal link.
        case invalidLink
        /// The school stopped sharing this calendar (or the link was never valid).
        case revoked(status: Int)
        /// The address answered with something that is not a calendar (often a sign-in page).
        case notCalendar
        case tooLarge
        /// The server answered with an error that may pass (429, 5xx, or another status).
        case server(status: Int)
        /// The Mac could not reach the server (URLError code: offline, DNS, timeout).
        case unreachable(code: Int)

        /// A technical code for reports: "school.feed.revoked.404". Never the link.
        var code: String {
            switch self {
            case .invalidLink: "school.feed.invalidLink"
            case .revoked(let status): "school.feed.revoked.\(status)"
            case .notCalendar: "school.feed.notCalendar"
            case .tooLarge: "school.feed.tooLarge"
            case .server(let status): "school.feed.server.\(status)"
            case .unreachable(let code): "school.feed.unreachable.\(code)"
            }
        }

        /// Trying again later will not help: the user needs a new link.
        var needsNewLink: Bool {
            switch self {
            case .invalidLink, .revoked, .notCalendar: true
            case .tooLarge, .server, .unreachable: false
            }
        }
    }

    /// The production read: the link must be https.
    static func fetch(_ link: URL) async throws -> String {
        guard link.scheme?.lowercased() == "https", link.host?.isEmpty == false else { throw Failure.invalidLink }
        return try await fetchBody(from: link, requireHTTPS: true)
    }

    /// The transport and classification behind `fetch`. `requireHTTPS: false` exists only so a
    /// test can read a fixture from a loopback server or a file URL.
    static func fetchBody(from url: URL, requireHTTPS: Bool, maximumBytes: Int = maximumBytes,
                          timeout: TimeInterval = timeout) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue("text/calendar, text/plain;q=0.8, */*;q=0.5", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: RedirectPolicy(requireHTTPS: requireHTTPS))
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw classify(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Never rethrow a transport error as is: its user info can hold the URL.
            throw Failure.unreachable(code: (error as NSError).code)
        }
        if let http = response as? HTTPURLResponse {
            if requireHTTPS, http.url?.scheme?.lowercased() != "https" { throw Failure.notCalendar }
            if let failure = classify(status: http.statusCode) { throw failure }
        }
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        guard looksLikeCalendar(text) else { throw Failure.notCalendar }
        return text
    }

    /// 2xx is fine; 401/403/404/410 mean the calendar is no longer shared; a redirect that was
    /// refused (3xx) is not a calendar; everything else may pass.
    static func classify(status: Int) -> Failure? {
        switch status {
        case 200..<300: nil
        case 300..<400: .notCalendar
        case 401, 403, 404, 410: .revoked(status: status)
        default: .server(status: status)
        }
    }

    static func classify(_ error: URLError) -> Failure {
        switch error.code {
        case .userAuthenticationRequired, .userCancelledAuthentication: .revoked(status: 401)
        case .badURL, .unsupportedURL: .invalidLink
        case .dataLengthExceedsMaximum: .tooLarge
        case .badServerResponse, .cannotParseResponse, .cannotDecodeContentData, .cannotDecodeRawData: .server(status: 0)
        default: .unreachable(code: error.code.rawValue)
        }
    }

    /// An iCalendar body starts with BEGIN:VCALENDAR (after a byte-order mark or blank lines).
    static func looksLikeCalendar(_ text: String) -> Bool {
        let head = text.prefix(2_048).drop { $0.isWhitespace || $0 == "\u{FEFF}" }
        return head.uppercased().hasPrefix("BEGIN:VCALENDAR")
    }

    /// Follows a redirect only to https (any scheme when a test allows http).
    /// The completion-handler form on purpose: the async delegate form crashes the Swift 6.4
    /// compiler's Objective-C thunk under this project's default isolation settings.
    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let requireHTTPS: Bool
        init(requireHTTPS: Bool) { self.requireHTTPS = requireHTTPS }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            let allowed = request.url.map { !requireHTTPS || $0.scheme?.lowercased() == "https" } ?? false
            completionHandler(allowed ? request : nil)
        }
    }
}
