//
//  HTTPServer.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 1/8/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Foundation
import Security
import CocoaAsyncSocket
@testable import PMHTTP

/// A basic HTTP server that supports expectations.
/// This server automatically listens on localhost with a random port when created.
///
/// **Thread Safety**:
/// `HTTPServer` is thread-safe and all methods can be called on any thread.
final class HTTPServer {
    typealias HTTPHeaders = HTTPManagerRequest.HTTPHeaders
    
    /// Set this to `true` to cause HTTPServer to print debug logs with `NSLog`.
    /// - Warning: This property is not an atomic value. It's a boolean, so writes are
    ///   atomic, but there's no ordering guarantees. Changes to this property should
    ///   preferably occur when the HTTPServer is not running.
    static var enableDebugLogging: Bool = false
    
    /// Returns a new `HTTPServer` instance.
    ///
    /// The returned server handles unencrypted HTTP connections.
    ///
    /// - Throws: Throws an error if the socket can't be configured.
    convenience init() throws {
        try self.init(sslItems: nil)
    }
    
    /// Returns a new `HTTPServer` instance using SSL/TLS.
    ///
    /// The returned server handles encrypted HTTPS connections.
    ///
    /// - Parameter identity: The `SecIdentity` containing the private key and certificate.
    /// - Parameter certificates: Zero or more certificates to use in the certificate chain.
    ///
    /// - Throws: Throws an error if the socket can't be configured.
    convenience init(identity: SecIdentity, certificates: [SecCertificate]) throws {
        try self.init(sslItems: (CollectionOfOne(identity as Any) + certificates.lazy.map({ $0 as Any })) as CFArray)
    }
    
    private init(sslItems: CFArray?) throws {
        shared = QueueConfined(label: "HTTPServer internal queue", value: Shared())
        listener = Listener(shared: shared, sslItems: sslItems)
        try listener.socket.accept(onInterface: "lo0", port: 0)
        listener.log("Listening")
    }
    
    deinit {
        invalidate()
    }
    
    /// Returns the host that the server is listening on.
    var host: String {
        return listener.socket.localHost!
    }
    
    /// Returns the port that the server is listening on.
    var port: UInt16 {
        return listener.socket.localPort
    }
    
    /// Returns the `domain[:port]` address string that the server is listening on.
    /// The port is omitted if it's `80`.
    var address: String {
        let port = self.port
        return port == 80 ? host : "\(host):\(port)"
    }
    
    /// Stops listening for new connections and shuts down all active connections.
    /// Also clears all request callbacks, including the `listenErrorCallback`
    /// and `unhandledRequestCallback`.
    ///
    /// This method is synchronous. When it returns, all sockets have been disconnected.
    func invalidate() {
        shared.asyncBarrier { shared in
            shared.requestCallbacks.removeAll()
            shared.listenErrorCallback = nil
            shared.unhandledRequestCallback = nil
        }
        let workItem = listener.invalidate()
        workItem.wait()
    }
    
    /// Shuts down all active connections and clears all request callbacks, including the
    /// `listenErrorCallback` and `unhandledRequestCallback`.
    /// Does not stop listening for new connections.
    func reset() {
        shared.asyncBarrier { shared in
            shared.requestCallbacks.removeAll()
            shared.listenErrorCallback = nil
            shared.unhandledRequestCallback = nil
        }
        let workItem = listener.reset()
        workItem.wait()
    }
    
    /// Registers a request callback that fires on every request. The callback MUST invoke
    /// the completion handler once and only once. The callback is invoked on an arbitrary
    /// background queue. The completion handler may be invoked on any thread.
    ///
    /// Calling the completion handler with a `Request` fulfills the request and the response
    /// is sent back to the client. Calling the completion handler with `nil` falls through to
    /// the next callback. Callbacks are always consulted in the same order that they were
    /// registered.
    ///
    /// If no callback handles a given request, the server automatically responds with
    /// a 404 Not Found response.
    ///
    /// - Note: Registering a callback (or clearing the callbacks) while a request is being
    ///   processed does not affect the callbacks consulted for the request.
    ///
    /// - Parameter callback: A callback that's invoked on an arbitrary background queue to
    ///   process the request.
    /// - Returns: A `CallbackToken` that can be given to `unregisterRequestCallback(_:)` to
    ///   unregister just this callback.
    ///
    /// - SeeAlso: `unregisterRequestCallback(_:)`, `clearRequestCallbacks()`.
    @discardableResult
    func registerRequestCallback(_ callback: @escaping (_ request: Request, _ completionHandler: @escaping (Response?) -> Void) -> Void) -> CallbackToken {
        let token = CallbackToken()
        shared.asyncBarrier { shared in
            shared.requestCallbacks.append((token, callback))
        }
        return token
    }
    
    /// Registers a request callback that fires for any request whose path matches `path`.
    /// The comparison is done on each path component after decoding any percent escapes.
    /// If `path` contains an invalid percent escape it will never match.
    ///
    /// See `registerRequestCallback(_:)` for details.
    ///
    /// - Note: If `path` does not start with `"/"` it is treated as if it did.
    ///
    /// - Parameter path: The path to compare against.
    /// - Parameter ignoresTrailingSlash: If `true`, a trailing slash on `path` and the
    ///   request path is ignored, otherwise it is significant. Defaults to `false`.
    /// - Parameter callback: A callback that's invoked on an arbitrary background queue to
    ///   process the request.
    /// - Returns: A `CallbackToken` that can be given to `unregisterRequestCallback(_:)` to
    ///   unregister just this callback.
    ///
    /// - SeeAlso: `registerRequestCallback(_:)`.
    @discardableResult
    func registerRequestCallback(for path: String, ignoresTrailingSlash: Bool = false, callback: @escaping (_ request: Request, _ completionHandler: @escaping (Response?) -> Void) -> Void) -> CallbackToken {
        var path = path
        if !path.hasPrefix("/") {
            path = "/\(path)"
        }
        func pathComponents(_ path: String, includesTrailingSlash: Bool) -> [String]? {
            let comps = path.unicodeScalars.split(separator: "/")
            let hasLeadingSlash = path.hasPrefix("/")
            let hasTrailingSlash = includesTrailingSlash && path.hasSuffix("/")
            var result: [String] = []
            result.reserveCapacity(comps.count + (hasLeadingSlash ? 1 : 0) + (hasTrailingSlash ? 1 : 0))
            if hasLeadingSlash {
                result.append("/")
            }
            for comp in comps {
                guard let elt = String(comp).removingPercentEncoding else {
                    return nil
                }
                result.append(elt)
            }
            if hasTrailingSlash {
                result.append("/")
            }
            return result
        }
        let pathComps = pathComponents(path, includesTrailingSlash: !ignoresTrailingSlash)
        return registerRequestCallback { request, completionHandler in
            if let pathComps = pathComps,
                let requestPathComps = pathComponents(request.urlComponents.percentEncodedPath, includesTrailingSlash: !ignoresTrailingSlash),
                pathComps == requestPathComps {
                callback(request, completionHandler)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    /// Unregisters a request callback that was previously registered with `registerRequestCallback(_:)`.
    /// Does nothing if the callback has already been unregistered.
    ///
    /// - SeeAlso: `registerRequestCallback(_:)`, `clearRequestCallbacks()`.
    func unregisterRequestCallback(_ token: CallbackToken) {
        shared.asyncBarrier { shared in
            if let idx = shared.requestCallbacks.index(where: { $0.token === token }) {
                shared.requestCallbacks.remove(at: idx)
            }
        }
    }
    
    /// Clears all registered request callbacks.
    ///
    /// Clearing the callbacks while a request is being processed does not affect the
    /// callbacks consulted for the request.
    ///
    /// Does not clear the `listenErrorCallback` or `unhandledRequestCallback`.
    ///
    /// - SeeAlso: `unregisterRequestCallback(_:)`.
    func clearRequestCallbacks() {
        shared.asyncBarrier { shared in
            shared.requestCallbacks.removeAll()
        }
    }
    
    /// A class that's used to identify registered callbacks for unregistering later.
    final class CallbackToken {}
    
    /// A callback that's triggered if the listen socket shuts down with an error.
    /// The callback is fired on an arbitrary background queue.
    var listenErrorCallback: ((Error) -> Void)? {
        get {
            return shared.sync({ $0.listenErrorCallback })
        }
        set {
            shared.asyncBarrier({ $0.listenErrorCallback = newValue })
        }
    }
    
    /// A callback that's triggered whenever a request comes in that isn't handled by
    /// any handlers. The callback is fired on an arbitrary background queue.
    /// The callback must invoke `completionHandler` (on any thread) once and only once.
    /// the `response` parameter is a suggested response, but the callback may substitute
    /// any other response as desired.
    var unhandledRequestCallback: ((_ request: Request, _ response: Response, _ completionHandler: @escaping (Response) -> Void) -> Void)? {
        get {
            return shared.sync({ $0.unhandledRequestCallback })
        }
        set {
            shared.asyncBarrier({ $0.unhandledRequestCallback = newValue })
        }
    }
    
    enum Method: Equatable {
        case HEAD
        case GET
        case POST
        case PUT
        case PATCH
        case DELETE
        case CONNECT
        case other(String)
        
        init(_ rawValue: String) {
            switch rawValue {
            case comparable("HEAD", options: .caseInsensitive): self = .HEAD
            case comparable("GET", options: .caseInsensitive): self = .GET
            case comparable("POST", options: .caseInsensitive): self = .POST
            case comparable("PUT", options: .caseInsensitive): self = .PUT
            case comparable("PATCH", options: .caseInsensitive): self = .PATCH
            case comparable("DELETE", options: .caseInsensitive): self = .DELETE
            default: self = .other(rawValue.uppercased())
            }
        }
        
        var string: String {
            switch self {
            case .HEAD: return "HEAD"
            case .GET: return "GET"
            case .POST: return "POST"
            case .PUT: return "PUT"
            case .PATCH: return "PATCH"
            case .DELETE: return "DELETE"
            case .CONNECT: return "CONNECT"
            case .other(let s): return s
            }
        }
    }
    
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = TimeZone(abbreviation: "GMT")!
        formatter.dateFormat = "EEE, dd MMM yyyy HH':'mm':'ss 'GMT'"
        return formatter
    }()
    
    // MARK: Status
    
    /// An HTTP status code.
    enum Status : Int {
        // 2xx Success
        case ok = 200
        case created = 201
        case accepted = 202
        case noContent = 204
        // 3xx Redirection
        case multipleChoices = 300
        case movedPermanently = 301
        case found = 302
        case seeOther = 303
        case notModified = 304
        case temporaryRedirect = 307
        // 4xx Client Error
        case badRequest = 400
        case unauthorized = 401
        case forbidden = 403
        case notFound = 404
        case methodNotAllowed = 405
        case notAcceptable = 406
        case gone = 410
        case lengthRequired = 411
        case requestEntityTooLarge = 413
        case requestURITooLong = 414
        case unsupportedMediaType = 415
        // 5xx Server Error
        case internalServerError = 500
        case notImplemented = 501
        case badGateway = 502
        case serviceUnavailable = 503
        case httpVersionNotSupported = 505
        
        /// `true` iff the status is a 1xx status.
        var isInformational: Bool {
            return (100...199).contains(rawValue)
        }
        
        /// `true` iff the status is a 2xx status.
        var isSuccessful: Bool {
            return (200...299).contains(rawValue)
        }
        
        /// `true` iff the status is a 3xx status.
        var isRedirection: Bool {
            return (300...399).contains(rawValue)
        }
        
        /// `true` iff the status is a 4xx status.
        var isClientError: Bool {
            return (400...499).contains(rawValue)
        }
        
        /// `true` iff the status is a 5xx status.
        var isServerError: Bool {
            return (500...599).contains(rawValue)
        }
    }
    
    /// An HTTP request.
    struct Request: CustomStringConvertible, CustomDebugStringConvertible {
        /// The HTTP request method.
        var method: Method
        /// The URL components of the request. Always includes the `path`.
        /// Includes the `host` if the request contains the `Host` header.
        var urlComponents: URLComponents
        /// The HTTP version of the request.
        var httpVersion: HTTPVersion
        /// The HTTP headers.
        var headers: HTTPHeaders
        /// The HTTP headers provided after a chunked body, if any.
        var trailerHeaders: HTTPHeaders = [:]
        /// The request body, if provided.
        var body: Data?
        
        var description: String {
            let path = urlComponents.path
            return  "Request(\(method) \(path.isEmpty ? "(no path)" : path), httpVersion: \(httpVersion), "
                + "headers: \(headers.dictionary), trailerHeaders: \(trailerHeaders.dictionary), "
                + "body: \(body?.count ?? 0) bytes)"
        }
        
        var debugDescription: String {
            return "HTTPServer.Request(method: \(method), path: \(String(reflecting: urlComponents.path)), httpVersion: \(httpVersion), "
                + "headers: \(headers), trailerHeaders: \(trailerHeaders), body: \(body.map(String.init(describing:)) ?? "nil"))"
        }
        
        fileprivate init?(method: Method, requestTarget: String, httpVersion: HTTPVersion, headers: HTTPHeaders = [:], body: Data? = nil) {
            self.method = method
            guard let comps = URLComponents(string: requestTarget) else { return nil }
            urlComponents = comps
            self.httpVersion = httpVersion
            self.headers = headers
            self.body = body
        }
        
        /// Returns the body parsed as a `MultipartBody`.
        /// - Throws: An error describing why the body cannot be parsed.
        func parseMultipartBody() throws -> MultipartBody {
            return try MultipartBody(request: self)
        }
    }
    
    /// A response to an HTTP request.
    struct Response: CustomStringConvertible, CustomDebugStringConvertible {
        /// The HTTP status code.
        var status: Status
        /// The HTTP headers.
        var headers: HTTPHeaders
        /// The body, if any. If set, "Content-Length" will be provided automatically.
        var body: Data?
        
        init(status: Status, headers: HTTPHeaders = [:], body: Data? = nil) {
            self.status = status
            self.headers = headers
            self.body = body
            // If the headers don't include Date, let's set it automatically
            if self.headers.index(forKey: "Date") == nil {
                self.headers["Date"] = HTTPServer.httpDateFormatter.string(from: Date())
            }
        }
        
        init(status: Status, headers: HTTPHeaders = [:], body: String) {
            self.init(status: status, headers: headers, body: body.data(using: String.Encoding.utf8)!)
        }
        
        init(status: Status, headers: HTTPHeaders = [:], text: String) {
            var headers = headers
            headers["Content-Type"] = "text/plain"
            self.init(status: status, headers: headers, body: text)
        }
        
        var description: String {
            return "Response(\(status.rawValue) \(status), headers: \(headers.dictionary), body: \(body?.count ?? 0) bytes)"
        }
        
        var debugDescription: String {
            return "HTTPServer.Response(status: \(status.rawValue) \(status), headers: \(headers), body: \(body.map(String.init(describing:)) ?? "nil"))"
        }
    }
    
    /// An HTTP version.
    struct HTTPVersion : Equatable, Comparable, CustomStringConvertible {
        var major: Int
        var minor: Int
        
        init(_ major: Int, _ minor: Int) {
            self.major = major
            self.minor = minor
        }
        
        var description: String {
            return "\(major).\(minor)"
        }
    }
    
    /// The parsed body of a multipart request.
    struct MultipartBody {
        /// One body part of a multipart request.
        struct Part {
            var headers: HTTPHeaders
            /// The `Content-Disposition` header, or `nil` if no such header exists.
            var contentDisposition: ContentDisposition?
            /// The `Content-Type` header, or `nil` if no such header exists.
            var contentType: MediaType?
            var body: Data
            /// The body data parsed as a UTF-8 string, or `nil` if it couldn't be parsed.
            /// - Note: This ignores any encoding specified in a `"Content-Type"` header on
            ///   the part.
            var bodyText: String? {
                return String(data: body, encoding: String.Encoding.utf8)
            }
            
            /// Parses a `Data` containing everything between the boundaries.
            /// Returns `nil` if the headers are not well-formed.
            init?(content: Data) {
                let anchoredEmptyLineRange = content.range(of: CRLF, options: .anchored, in: 0..<content.count)
                guard let emptyLineRange = anchoredEmptyLineRange ?? content.range(of: CRLFCRLF, in: 0..<content.count)
                    else { return nil }
                body = content.subdata(in: emptyLineRange.upperBound..<content.count)
                let headerData = content.subdata(in: 0..<emptyLineRange.lowerBound)
                guard let headerContent = String(data: headerData, encoding: String.Encoding.ascii)?.chomped()
                    else { return nil }
                headers = HTTPHeaders()
                var lines = unfoldLines(headerContent.components(separatedBy: "\r\n"))
                if lines.last == "" {
                    lines.removeLast()
                }
                for line in lines {
                    guard let idx = line.unicodeScalars.index(of: ":") else { return nil }
                    let field = String(line.unicodeScalars.prefix(upTo: idx))
                    var scalars = line.unicodeScalars.suffix(from: line.unicodeScalars.index(after: idx))
                    // skip leading OWS
                    if let idx = scalars.index(where: { $0 != " " && $0 != "\t" }) {
                        scalars = scalars.suffix(from: idx)
                        // skip trailing OWS
                        let idx = scalars.reversed().index(where: { $0 != " " && $0 != "\t" })!
                        // idx.base is the successor to the element, so prefixUpTo() cuts off at the right spot
                        scalars = scalars.prefix(upTo: idx.base)
                    } else {
                        scalars = scalars.suffix(from: scalars.endIndex)
                    }
                    headers[field] = String(scalars)
                }
                contentDisposition = headers["Content-Disposition"].map({ ContentDisposition($0) })
                contentType = headers["Content-Type"].map({ MediaType($0) })
            }
        }
        
        enum Error: Swift.Error {
            case contentTypeNotMultipart
            case noBody
            case noBoundary
            case invalidBoundary
            case cannotFindFirstBoundary
            case cannotFindBoundaryTerminator
            case invalidBodyPartHeaders
        }
        
        /// The MIME type of the multipart body, such as `"multipart/form-data"`.
        /// The `contentType` is guaranteed to start with `"multipart/"`.
        var contentType: String
        
        /// The body parts.
        var parts: [Part]
        
        /// Parses a multipart request.
        /// - Throws: `MultipartBody.Error` if the `Content-Type` is not
        ///   multipart or the `body` is not formatted properly.
        fileprivate init(request: Request) throws {
            guard let contentType = request.headers["Content-Type"].map(MediaType.init),
                contentType.type == "multipart"
                else { throw Error.contentTypeNotMultipart }
            guard let boundary = contentType.params.first(where: { $0.0 == "boundary" })?.1
                else { throw Error.noBoundary }
            guard let body = request.body
                else { throw Error.noBody }
            self.contentType = contentType.typeSubtype
            guard !boundary.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }),
                let boundaryData = "--\(boundary)".data(using: String.Encoding.utf8)
                else { throw Error.invalidBoundary }
            func findBoundary(_ sourceRange: Range<Int>) -> (range: Range<Int>, isTerminator: Bool)? {
                var sourceRange = sourceRange
                repeat {
                    guard var range = body.range(of: boundaryData, in: sourceRange) else {
                        // Couldn't find a boundary
                        return nil
                    }
                    if range.lowerBound >= 2 && (body[range.lowerBound-2], body[range.lowerBound-1]) == (0x0D, 0x0A) {
                        // The boundary is preceeded by CRLF.
                        // Include the CRLF in the range (as long as it's still within sourceRange)
                        range = Range(uncheckedBounds: (lower: max(sourceRange.lowerBound, range.lowerBound-2), upper: range.upperBound))
                    } else if range.lowerBound != 0 {
                        // The boundary isn't at the start of the data, and isn't preceeded by CRLF.
                        // `range` doesn't contain any CRLF characters, so we can skip the whole thing.
                        sourceRange = Range(uncheckedBounds: (lower: range.upperBound, upper: sourceRange.upperBound))
                        continue
                    }
                    // Is this a terminator?
                    var isTerminator = false
                    if range.upperBound + 1 < body.endIndex && (body[range.upperBound], body[range.upperBound+1]) == (0x2D, 0x2D) { // "--"
                        isTerminator = true
                        range = Range(uncheckedBounds: (lower: range.lowerBound, upper: range.upperBound + 2))
                    }
                    // Skip optional LWS
                    while range.upperBound != body.endIndex && (UnicodeScalar(body[range.upperBound]) == " " || UnicodeScalar(body[range.upperBound]) == "\t") {
                        range = Range(uncheckedBounds: (lower: range.lowerBound, upper: range.upperBound + 1))
                    }
                    if isTerminator && range.upperBound == body.endIndex {
                        // no more data, which is acceptable for the terminator line
                        return (range, isTerminator)
                    } else if range.upperBound + 1 < body.endIndex && (body[range.upperBound], body[range.upperBound+1]) == (0x0D, 0x0A) { // the boundary is preceeded by CRLF
                        // CRLF terminator
                        range = Range(uncheckedBounds: (lower: range.lowerBound, upper: range.upperBound + 2))
                        return (range, isTerminator)
                    }
                    // Otherwise, this supposed boundary line isn't a valid boundary. Search again
                    sourceRange = Range(uncheckedBounds: (lower: range.upperBound, upper: sourceRange.upperBound))
                } while true
            }
            parts = []
            var sourceRange: Range<Int> = 0..<body.count
            guard var boundaryInfo = findBoundary(sourceRange)
                else { throw Error.cannotFindFirstBoundary }
            while !boundaryInfo.isTerminator {
                let startIdx = boundaryInfo.range.upperBound
                sourceRange = Range(uncheckedBounds: (lower: startIdx, upper: sourceRange.upperBound))
                guard let nextBoundary = findBoundary(sourceRange)
                    else { throw Error.cannotFindBoundaryTerminator }
                boundaryInfo = nextBoundary
                let content = body.subdata(in: startIdx..<boundaryInfo.range.lowerBound)
                guard let part = Part(content: content)
                    else { throw Error.invalidBodyPartHeaders }
                parts.append(part)
            }
        }
    }
    
    struct ContentDisposition: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
        /// The dispositon value, not including any parameters, e.g. `"form-data"`.
        var value: String
        /// The parameters, if any.
        var params: DelimitedParameters
        /// The raw value of the `Content-Disposition` header.
        let rawValue: String
        
        var description: String {
            return rawValue
        }
        
        var debugDescription: String {
            return "ContentDisposition(\(String(reflecting: value)), \(String(reflecting: params.rawValue)))"
        }
        
        init(_ rawValue: String) {
            let rawValue = trimLWS(rawValue)
            self.rawValue = rawValue
            if let idx = rawValue.unicodeScalars.index(of: ";") {
                value = trimLWS(String(rawValue.unicodeScalars.prefix(upTo: idx)))
                params = DelimitedParameters(String(rawValue.unicodeScalars.suffix(from: rawValue.unicodeScalars.index(after: idx))), delimiter: ";")
            } else {
                value = rawValue
                params = DelimitedParameters("", delimiter: ";")
            }
        }
    }
    
    private let shared: QueueConfined<Shared>
    private let listener: Listener
    
    private class Shared {
        var listenErrorCallback: ((Error) -> Void)?
        var requestCallbacks: [(token: CallbackToken, callback: (_ request: Request, _ completionHandler: @escaping (Response?) -> Void) -> Void)] = []
        var unhandledRequestCallback: ((_ request: Request, _ response: Response, _ completionHandler: @escaping (Response) -> Void) -> Void)?
    }
    
    private class Listener : NSObject, GCDAsyncSocketDelegate {
        let shared: QueueConfined<Shared>
        let socket = GCDAsyncSocket()
        let queue = DispatchQueue(label: "HTTPServer listen queue")
        var connections: [Connection] = []
        let sslItems: CFArray?
        
        init(shared: QueueConfined<Shared>, sslItems: CFArray?) {
            self.shared = shared
            self.sslItems = sslItems
            super.init()
            socket.setDelegate(self, delegateQueue: queue)
        }
        
        deinit {
            socket.synchronouslySetDelegate(nil)
        }
        
        /// Stops listening for new connections and disconnects all existing connections.
        /// Returns a `DispatchWorkItem` that can be waited on with `.wait` or `.notify`.
        func invalidate() -> DispatchWorkItem {
            log("Invalidated")
            socket.delegate = nil
            socket.disconnect()
            return reset()
        }
        
        /// Disconnects all existing connections but does not stop listening for new ones.
        /// Returns a `DispatchWorkItem` that can be waited on with `.wait` or `.notify`.
        func reset() -> DispatchWorkItem {
            let workItem = DispatchWorkItem {
                autoreleasepool {
                    for connection in self.connections {
                        connection.invalidate()
                    }
                    self.connections.removeAll()
                }
            }
            queue.async(execute: workItem)
            return workItem
        }
        
        func log(_ msg: @autoclosure () -> String) {
            if HTTPServer.enableDebugLogging {
                NSLog("<HTTP Server %@:%hu> %@", socket.localHost ?? "nil", socket.localPort, msg())
            }
        }
        
        @objc func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
            let connection = Connection(shared: shared, listener: self, socket: newSocket)
            log("New connection (id: \(connection.connectionId)) from \(newSocket.connectedHost.map(String.init(describing:)) ?? "nil"):\(newSocket.connectedPort)")
            connections.append(connection)
            if let sslItems = sslItems {
                connection.startTLS([kCFStreamSSLIsServer as String: kCFBooleanTrue, kCFStreamSSLCertificates as String: sslItems])
            }
            connection.readRequestLine()
        }
        
        @objc func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
            // we should only get this if an error occurs, because we nil out the delegate before closing ourselves
            guard let err = err else {
                log("Disconnected")
                return
            }
            log("Disconnected with error: \(err)")
            shared.async { shared in
                if let callback = replace(&shared.listenErrorCallback, with: nil) {
                    DispatchQueue.global(qos: .utility).async {
                        autoreleasepool {
                            callback(err)
                        }
                    }
                }
            }
        }
    }
    
    private class Connection : NSObject, GCDAsyncSocketDelegate {
        let shared: QueueConfined<Shared>
        weak var listener: Listener?
        let socket: GCDAsyncSocket
        let queue = DispatchQueue(label: "HTTPServer connection queue")
        var request: HTTPServer.Request?
        var chunkedBody: NSMutableData?
        var chunkedTrailer: Data?
        
        let connectionId: Int32 // DEBUG
        
        private static var lastConnectionId: Int32 = 0 // DEBUG
        
        init(shared: QueueConfined<Shared>, listener: Listener, socket: GCDAsyncSocket) {
            self.shared = shared
            self.listener = listener
            self.socket = socket
            connectionId = OSAtomicIncrement32(&Connection.lastConnectionId) // DEBUG
            super.init()
            socket.setDelegate(self, delegateQueue: queue)
        }
        
        deinit {
            if socket.isConnected {
                log("Disconnecting (deinit)")
            }
            socket.synchronouslySetDelegate(nil)
            socket.disconnect()
        }
        
        private func log(_ msg: @autoclosure () -> String) {
            if HTTPServer.enableDebugLogging {
                NSLog("<HTTP Connection %d> %@", connectionId, msg())
            }
        }
        
        func invalidate() {
            if socket.isConnected {
                log("Disconnecting (invalidated)")
            }
            socket.delegate = nil
            socket.disconnect()
        }
        
        func startTLS(_ tlsSettings: [String: NSObject]?) {
            log("Starting TLS")
            socket.startTLS(tlsSettings)
        }
        
        func readRequestLine() {
            log("Reading request line...")
            socket.readData(to: CRLF, withTimeout: -1, tag: Tag.requestLine.rawValue)
        }
        
        private func dispatchRequest() {
            log("Dispatching request")
            guard let request = self.request else {
                return writeResponseAndClose(Response(status: .internalServerError, text: "Couldn't find active request"))
            }
            shared.async { shared in
                let callbacks = shared.requestCallbacks
                let unhandledRequestCallback = shared.unhandledRequestCallback
                let queue = DispatchQueue(label: "HTTPServer request callback queue")
                var iter = callbacks.makeIterator()
                func invokeNextCallback() {
                    guard let (_, cb) = iter.next() else {
                        let response = Response(status: .notFound)
                        if let unhandledRequestCallback = unhandledRequestCallback {
                            self.log("Invoking unhandled request callback")
                            unhandledRequestCallback(request, response) { response in
                                self.writeResponse(response)
                            }
                        } else {
                            self.log("Request not handled; sending 404 Not Found")
                            self.writeResponse(Response(status: .notFound))
                        }
                        return
                    }
                    var invoked = false
                    cb(request) { response in
                        // sanity check to make sure we haven't been called already
                        // we'll check again on `queue` because that's the definitive spot, but we're doing an early check here
                        // to provide a better stack trace if the precondition fails.
                        precondition(invoked == false, "HTTPServer request completion handler invoked more than once")
                        queue.async {
                            precondition(invoked == false, "HTTPServer request completion handler invoked more than once")
                            invoked = true
                            autoreleasepool {
                                if let response = response {
                                    self.writeResponse(response)
                                } else {
                                    invokeNextCallback()
                                }
                            }
                        }
                    }
                }
                queue.async {
                    autoreleasepool {
                        invokeNextCallback()
                    }
                }
            }
        }
        
        private func writeResponse(_ response: Response) {
            log("Writing response: \(response.status)")
            let request = replace(&self.request, with: nil)
            chunkedBody = nil
            chunkedTrailer = nil
            var response = response
            if let body = response.body {
                response.headers["Transfer-Encoding"] = nil
                response.headers["Content-Length"] = String(body.count)
            } else if response.headers["Content-Length"] == nil && response.headers["Transfer-Encoding"] == nil {
                response.headers["Content-Length"] = "0"
            }
            var text = "HTTP/1.1 \(response.status)\r\n"
            for (field,value) in response.headers {
                text += "\(field): \(value)\r\n"
            }
            text += "\r\n"
            socket.write(text.data(using: String.Encoding.utf8)!, withTimeout: -1, tag: 0)
            if let body = response.body, !body.isEmpty {
                switch (request?.method, response.status) {
                case (.CONNECT?, _) where response.status.isSuccessful: fallthrough
                case _ where response.status.isInformational: fallthrough
                case (_, .noContent), (_, .notModified):
                    // no body can be present. Print a warning and throw it away
                    NSLog("warning: HTTPServer tried to send response \(response.status) to request method \(request?.method as ImplicitlyUnwrappedOptional) with non-empty body")
                    log("Disconnecting...")
                    socket.disconnectAfterWriting()
                    return
                case (.HEAD?, _):
                    // no body can be present, but sending Content-Length is legitimate, so just silently ignore the body
                    break
                default:
                    log("Writing response body (\(body.count) bytes)")
                    socket.write(body, withTimeout: -1, tag: 0)
                }
            }
            // NB: We don't support comma-separated connection options here
            if response.headers["Connection"]?.caseInsensitiveCompare("close") == .orderedSame
                || (request?.httpVersion == HTTPVersion(1,0) && response.headers["Connection"]?.caseInsensitiveCompare("keep-alive") != .orderedSame)
                || request?.httpVersion < HTTPVersion(1,0)
            {
                log("Disconnecting...")
                socket.disconnectAfterWriting()
            } else {
                // if we're not disconnecting, we might be getting a new request instead
                readRequestLine()
            }
        }
        
        private func writeResponseAndClose(_ response: Response) {
            var response = response
            response.headers["Connection"] = "close"
            writeResponse(response)
        }
        
        /// Parses headers from the given data. If a parse error occurs,
        /// returns `nil` and sends a BadRequest response.
        /// The given closure is invoked for each header, with the old value (if one exists).
        /// The `field` parameter to the closure always contains the normalized name of the header.
        /// If the closure returns a `Response`, that response is sent to the server and the socket closed.
        private func parseHeadersFromData(_ data: Data, _ f: (_ field: String, _ value: String, _ oldValue: String?) -> Response? = { _ in nil }) -> HTTPHeaders? {
            guard let line = String(data: data, encoding: String.Encoding.ascii)?.chomped() else {
                writeResponseAndClose(Response(status: .badRequest, text: "Non-ASCII headers are not supported"))
                return nil
            }
            var headers = HTTPHeaders()
            var comps = unfoldLines(line.components(separatedBy: "\r\n"))
            if comps.last == "" {
                comps.removeLast()
            }
            for comp in comps {
                guard let idx = comp.unicodeScalars.index(of: ":") else {
                    writeResponseAndClose(Response(status: .badRequest, text: "Illegal header line syntax"))
                    return nil
                }
                let field = String(comp.unicodeScalars.prefix(upTo: idx))
                var scalars = comp.unicodeScalars.suffix(from: comp.unicodeScalars.index(after: idx))
                // skip leading OWS
                if let idx = scalars.index(where: { $0 != " " && $0 != "\t" }) {
                    scalars = scalars.suffix(from: idx)
                    // skip trailing OWS
                    let idx = scalars.reversed().index(where: { $0 != " " && $0 != "\t" })!
                    // idx.base is the successor to the element, so prefixUpTo() cuts off at the right spot
                    scalars = scalars.prefix(upTo: idx.base)
                } else {
                    scalars = scalars.suffix(from: scalars.endIndex)
                }
                let value = String(scalars)
                let normalizedField = HTTPHeaders.normalizedHTTPHeaderField(field)
                let oldValue = headers.unsafeUpdateValue(value, forPreNormalizedKey: normalizedField)
                if let response = f(normalizedField, value, oldValue) {
                    writeResponseAndClose(response)
                    return nil
                }
                headers[field] = value
            }
            return headers
        }
        
        private enum Tag: Int {
            case requestLine = 1
            case requestLineStrict
            case headers
            case fixedLengthBody
            case chunkedBodySize
            case chunkedBodyData
            case chunkedBodyTrailer
        }
        
        @objc func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
            switch Tag(rawValue: tag)! {
            case .requestLine:
                // Robust servers should skip at least one CRLF before the request.
                if data == CRLF {
                    log("Skipping CRLF request prefix...")
                    socket.readData(to: CRLF, withTimeout: -1, tag: Tag.requestLineStrict.rawValue)
                } else {
                    fallthrough
                }
            case .requestLineStrict:
                guard let line = String(data: data, encoding: String.Encoding.ascii)?.chomped() else {
                    log("Parsing request line: \(data)")
                    return writeResponseAndClose(Response(status: .badRequest, text: "Non-ASCII request line not supported"))
                }
                log("Parsing request line: \(String(reflecting: line))")
                let comps = line.unicodeScalars.split(whereSeparator: { $0 == " " }).map(String.init)
                guard comps.count == 3 else {
                    return writeResponseAndClose(Response(status: .badRequest, text: "Invalid request line syntax"))
                }
                var version = comps[2]
                guard version.hasPrefix("HTTP/") else {
                    return writeResponseAndClose(Response(status: .badRequest, text: "Couldn't find HTTP version in request line"))
                }
                version.unicodeScalars.removeFirst(5)
                let httpVersion: HTTPVersion
                switch version {
                case "0.9": httpVersion = HTTPVersion(0,9)
                case "1.0": httpVersion = HTTPVersion(1,0)
                case "1.1": httpVersion = HTTPVersion(1,1)
                default: return writeResponseAndClose(Response(status: .httpVersionNotSupported))
                }
                let method = Method(comps[0])
                if case .other(let name) = method {
                    return writeResponseAndClose(Response(status: .methodNotAllowed, text: "Method \(name) not supported"))
                }
                guard let request = Request(method: method, requestTarget: comps[1], httpVersion: httpVersion) else {
                    return writeResponseAndClose(Response(status: .badRequest))
                }
                self.request = request
                log("Reading request headers...")
                socket.readData(to: CRLFCRLF, withTimeout: -1, tag: Tag.headers.rawValue)
            case .headers:
                log("Parsing request headers")
                guard var request = replace(&self.request, with: nil) else {
                    return writeResponseAndClose(Response(status: .internalServerError, text: "Couldn't find active request"))
                }
                var multipleContentLengths = false
                guard let headers = parseHeadersFromData(data, { (field: String, value: String, oldValue: String?) in
                    if field == "Content-Length", let oldValue = oldValue, oldValue != value {
                        multipleContentLengths = true
                    }
                    return nil
                }) else {
                    // response was already written
                    return
                }
                request.headers = headers
                self.request = request
                if let value = request.headers["Transfer-Encoding"] {
                    if value.caseInsensitiveCompare("chunked") != .orderedSame {
                        return writeResponseAndClose(Response(status: .notImplemented, text: "The only supported Transfer-Encoding is chunked"))
                    }
                    chunkedBody = NSMutableData()
                    chunkedTrailer = nil // just in case
                    log("Reading chunked body...")
                    socket.readData(to: CRLF, withTimeout: -1, tag: Tag.chunkedBodySize.rawValue)
                } else if multipleContentLengths {
                    return writeResponseAndClose(Response(status: .badRequest, text: "Multiple Content-Length headers found"))
                } else if let value = request.headers["Content-Length"] {
                    if let length = Int(value), length >= 0 {
                        if length == 0 {
                            dispatchRequest()
                        } else if length > 5 * 1024 * 1024 {
                            log("Content-Length too large (\(length) bytes)")
                            return writeResponseAndClose(Response(status: .requestEntityTooLarge, text: "Requests limited to 5MB"))
                        } else {
                            log("Reading fixed length body (\(length) bytes)...")
                            socket.readData(toLength: UInt(length), withTimeout: -1, tag: Tag.fixedLengthBody.rawValue)
                        }
                    } else {
                        return writeResponseAndClose(Response(status: .badRequest, text: "Invalid Content-Length"))
                    }
                } else {
                    // assume length of 0
                    dispatchRequest()
                }
            case .fixedLengthBody:
                log("Received fixed length body")
                guard var request = replace(&self.request, with: nil) else {
                    return writeResponseAndClose(Response(status: .internalServerError, text: "Couldn't find active request"))
                }
                request.body = data
                self.request = request
                dispatchRequest()
            case .chunkedBodySize:
                log("Parsing chunked body chunk")
                guard let chunkedBody = self.chunkedBody else {
                    return writeResponseAndClose(Response(status: .internalServerError, text: "Couldn't find active chunk body"))
                }
                func isHexDigit(_ c: UInt8) -> Bool {
                    switch UnicodeScalar(c) {
                    case "0"..."9": return true
                    case "a"..."f": return true
                    case "A"..."F": return true
                    default: return false
                    }
                }
                guard let idx = data.index(where: { !isHexDigit($0) }) else {
                    // surely we should have found the CR
                    return writeResponseAndClose(Response(status: .badRequest, text: "Invalid chunk syntax"))
                }
                switch UnicodeScalar(data[idx]) {
                case ";":
                    // the rest of the line is a chunk extension
                    // don't even bother parsing it for validity, we just ignore all extensions
                    break
                case "\r":
                    // line ending
                    break
                default:
                    return writeResponseAndClose(Response(status: .badRequest, text: "Invalid chunk syntax"))
                }
                guard let size = UInt(String(data.prefix(upTo: idx).lazy.map({Character(UnicodeScalar($0))})), radix: 16) else {
                    return writeResponseAndClose(Response(status: .badRequest, text: "Invalid chunk size"))
                }
                if size == 0 {
                    log("Last chunk; reading trailer...")
                    request?.body = chunkedBody as Data
                    chunkedTrailer = nil // just in case
                    socket.readData(toLength: 2, withTimeout: -1, tag: Tag.chunkedBodyTrailer.rawValue)
                } else {
                    guard UInt(chunkedBody.length) + size <= 5 * 1024 * 1024 else {
                        log("Chunk too large (\(size) bytes, \(UInt(chunkedBody.length) + size) total)")
                        return writeResponseAndClose(Response(status: .requestEntityTooLarge, text: "Requests limited to 5MB"))
                    }
                    log("Reading chunk data (\(size) bytes)...")
                    socket.readData(toLength: size + 2, withTimeout: -1, tag: Tag.chunkedBodyData.rawValue)
                }
            case .chunkedBodyData:
                log("Received chunk data")
                guard let chunkedBody = chunkedBody else {
                    return writeResponseAndClose(Response(status: .internalServerError, text: "Couldn't find active chunk body"))
                }
                chunkedBody.append(data)
                // the appended data had a CRLF trailer, chop it off now
                chunkedBody.length -= 2
                log("Reading next chunk...")
                socket.readData(to: CRLF, withTimeout: -1, tag: Tag.chunkedBodySize.rawValue)
            case .chunkedBodyTrailer:
                log("Processing chunked body trailer")
                if let chunkedTrailer = replace(&self.chunkedTrailer, with: nil) {
                    guard var request = replace(&self.request, with: nil) else {
                        return writeResponseAndClose(Response(status: .internalServerError, text: "Couldn't find active request"))
                    }
                    var trailer = chunkedTrailer
                    trailer.append(data)
                    guard let headers = parseHeadersFromData(trailer) else {
                        // response was already written
                        return
                    }
                    request.trailerHeaders = headers
                    self.request = request
                    dispatchRequest()
                } else {
                    // either contains a CRLF or contains the first line of the trailer headers
                    if data == CRLF {
                        dispatchRequest()
                    } else {
                        chunkedTrailer = data
                        log("Reading trailer headers...")
                        socket.readData(to: CRLFCRLF, withTimeout: -1, tag: Tag.chunkedBodyTrailer.rawValue)
                    }
                }
            }
        }
        
        @objc func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
            log("Disconnected")
            if request != nil {
                NSLog("HTTPServer: received disconnection while processing request; error: %@", (err as NSError?) ?? "nil")
            }
            socket.delegate = nil
            if let listener = listener {
                listener.queue.async {
                    if let idx = listener.connections.index(where: { $0 === self }) {
                        listener.connections.remove(at: idx)
                    }
                }
            }
        }
        
        @objc func socketDidSecure(_ sock: GCDAsyncSocket) {
            log("TLS established")
        }
    }
}

private extension String {
    /// Returns the string with a trailing CRLF, CR, or LF chopped off, if present.
    /// Only chops off one line ending.
    func chomped() -> String {
        if hasSuffix("\r\n") {
            return String(unicodeScalars.dropLast(2))
        } else if hasSuffix("\r") || hasSuffix("\n") {
            return String(unicodeScalars.dropLast())
        } else {
            return self
        }
    }
}

private func replace<T>(_ a: inout T, with b: T) -> T {
    var value = b
    swap(&a, &value)
    return value
}

extension HTTPServer.Status : CustomStringConvertible {
    var description: String {
        let name: String
        switch self {
        case .ok: name = "OK"
        case .created: name = "Created"
        case .accepted: name = "Accepted"
        case .noContent: name = "No Content"
        case .multipleChoices: name = "Multiple Choices"
        case .movedPermanently: name = "Moved Permanently"
        case .found: name = "Found"
        case .seeOther: name = "See Other"
        case .notModified: name = "Not Modified"
        case .temporaryRedirect: name = "Temporary Redirect"
        case .badRequest: name = "Bad Request"
        case .unauthorized: name = "Unauthorized"
        case .forbidden: name = "Forbidden"
        case .notFound: name = "Not Found"
        case .methodNotAllowed: name = "Method Not Allowed"
        case .notAcceptable: name = "Not Acceptable"
        case .gone: name = "Gone"
        case .lengthRequired: name = "Length Required"
        case .requestEntityTooLarge: name = "Request Entity Too Large"
        case .requestURITooLong: name = "Request-URI Too Long"
        case .unsupportedMediaType: name = "Unsupported Media Type"
        case .internalServerError: name = "Internal Server Error"
        case .notImplemented: name = "Not Implemented"
        case .badGateway: name = "Bad Gateway"
        case .serviceUnavailable: name = "Service Unavailable"
        case .httpVersionNotSupported: name = "HTTP Version Not Supported"
        }
        return "\(rawValue) \(name)"
    }
}

private let CRLF: Data = Data(bytes: [13, 10])
private let CRLFCRLF: Data = Data(bytes: [13, 10, 13, 10])

func ==(lhs: HTTPServer.Method, rhs: HTTPServer.Method) -> Bool {
    switch (lhs, rhs) {
    case let (.other(a), .other(b)): return a == b
    case (.other, _), (_, .other): return false
    default: return lhs.string == rhs.string
    }
}

func ==(lhs: HTTPServer.HTTPVersion, rhs: HTTPServer.HTTPVersion) -> Bool {
    return lhs.major == rhs.major && lhs.minor == rhs.minor
}

/// Compares two `ContentDisposition`s for equality, ignoring any LWS.
/// The Parameter names are case-insensitive, but the value and parameter values are case-sensitive.
/// - Note: The order of parameters is considered significant.
func ==(lhs: HTTPServer.ContentDisposition, rhs: HTTPServer.ContentDisposition) -> Bool {
    return lhs.value == rhs.value
        && lhs.params.elementsEqual(rhs.params, by: { $0.0.caseInsensitiveCompare($1.0) == .orderedSame && $0.1 == $1.1 })
}


func <(lhs: HTTPServer.HTTPVersion, rhs: HTTPServer.HTTPVersion) -> Bool {
    return lhs.major < rhs.major || (lhs.major == rhs.major && lhs.minor < rhs.minor)
}

func unfoldLines(_ lines: [String]) -> [String] {
    var result: [String] = []
    result.reserveCapacity(lines.count)
    for var line in lines {
        if line.hasPrefix("\t") {
            line.unicodeScalars.replaceSubrange(line.unicodeScalars.startIndex...line.unicodeScalars.startIndex, with: CollectionOfOne(" "))
        }
        if line.hasPrefix(" ") {
            if var lastLine = result.popLast() {
                lastLine += line
                line = lastLine
            } else {
                line.unicodeScalars.removeFirst()
            }
        }
        result.append(line)
    }
    return result
}

private struct StringComparable {
    let string: String
    let options: NSString.CompareOptions
}

private func comparable(_ string: String, options: NSString.CompareOptions) -> StringComparable {
    return StringComparable(string: string, options: options)
}

private func ~=(comparable: StringComparable, value: String) -> Bool {
    return comparable.string.compare(value, options: comparable.options) == .orderedSame
}

// Swift 3 removed comparisons on Optionals
private extension Optional where Wrapped: Comparable {
    static func <(lhs: Wrapped?, rhs: Wrapped?) -> Bool {
        switch (lhs, rhs) {
        case let (a?, b?): return a < b
        case (nil, _?): return true
        default: return false
        }
    }
}
