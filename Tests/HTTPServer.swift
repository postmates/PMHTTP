//
//  HTTPServer.swift
//  PostmatesNetworking
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
    
    /// Returns the new `HTTPServer` instance.
    /// - Throws: Throws an error if the socket can't be configured.
    init() throws {
        shared = QueueConfined(label: "HTTPServer internal queue", value: Shared())
        listener = Listener(shared: shared)
        try listener.socket.acceptOnInterface("lo0", port: 0)
        listener.log("Listening")
    }
    
    deinit {
        invalidate()
    }
    
    /// Returns the host that the server is listening on.
    var host: String {
        return listener.socket.localHost
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
        let block = listener.invalidate()
        dispatch_block_wait(block, DISPATCH_TIME_FOREVER)
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
        let block = listener.reset()
        dispatch_block_wait(block, DISPATCH_TIME_FOREVER)
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
    func registerRequestCallback(callback: (request: Request, completionHandler: Response? -> Void) -> Void) -> CallbackToken {
        let token = CallbackToken()
        shared.asyncBarrier { shared in
            shared.requestCallbacks.append((token, callback))
        }
        return token
    }
    
    /// Registers a request callback that fires for any request whose path exactly matches `path`.
    /// The path is compared in a case-sensitive manner after decoding any percent escapes.
    /// See `registerRequestCallback(_:)` for details.
    ///
    /// - SeeAlso: `registerRequestCallback(_:)`.
    func registerRequestCallbackForPath(path: String, callback: (request: Request, completionHandler: Response? -> Void) -> Void) -> CallbackToken {
        return registerRequestCallback { request, completionHandler in
            if request.urlComponents.path == path {
                callback(request: request, completionHandler: completionHandler)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    /// Unregisters a request callback that was previously registered with `registerRequestCallback(_:)`.
    /// Does nothing if the callback has already been unregistered.
    ///
    /// - SeeAlso: `registerRequestCallback(_:)`, `clearRequestCallbacks()`.
    func unregisterRequestCallback(token: CallbackToken) {
        shared.asyncBarrier { shared in
            if let idx = shared.requestCallbacks.indexOf({ $0.token === token }) {
                shared.requestCallbacks.removeAtIndex(idx)
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
    var listenErrorCallback: (NSError -> Void)? {
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
    var unhandledRequestCallback: ((request: Request, response: Response, completionHandler: Response -> Void) -> Void)? {
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
        case Other(String)
        
        init(_ rawValue: String) {
            switch rawValue {
            case comparable("HEAD", options: .CaseInsensitiveSearch): self = .HEAD
            case comparable("GET", options: .CaseInsensitiveSearch): self = .GET
            case comparable("POST", options: .CaseInsensitiveSearch): self = .POST
            case comparable("PUT", options: .CaseInsensitiveSearch): self = .PUT
            case comparable("PATCH", options: .CaseInsensitiveSearch): self = .PATCH
            case comparable("DELETE", options: .CaseInsensitiveSearch): self = .DELETE
            default: self = .Other(rawValue.uppercaseString)
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
            case .Other(let s): return s
            }
        }
    }
    
    private static let httpDateFormatter: NSDateFormatter = {
        let formatter = NSDateFormatter()
        let locale = NSLocale(localeIdentifier: "en_US_POSIX")
        let calendar = NSCalendar(identifier: NSCalendarIdentifierGregorian)!
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = NSTimeZone(abbreviation: "GMT")!
        formatter.dateFormat = "EEE, dd MMM yyyy HH':'mm':'ss 'GMT'"
        return formatter
    }()
    
    // MARK: Status
    
    /// An HTTP status code.
    enum Status : Int {
        // 2xx Success
        case OK = 200
        case Created = 201
        case Accepted = 202
        case NoContent = 204
        // 3xx Redirection
        case MultipleChoices = 300
        case MovedPermanently = 301
        case Found = 302
        case SeeOther = 303
        case NotModified = 304
        case TemporaryRedirect = 307
        // 4xx Client Error
        case BadRequest = 400
        case Unauthorized = 401
        case Forbidden = 403
        case NotFound = 404
        case MethodNotAllowed = 405
        case NotAcceptable = 406
        case Gone = 410
        case LengthRequired = 411
        case RequestEntityTooLarge = 413
        case RequestURITooLong = 414
        case UnsupportedMediaType = 415
        // 5xx Server Error
        case InternalServerError = 500
        case NotImplemented = 501
        case BadGateway = 502
        case ServiceUnavailable = 503
        case HTTPVersionNotSupported = 505
        
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
        var urlComponents: NSURLComponents
        /// The HTTP version of the request.
        var httpVersion: HTTPVersion
        /// The HTTP headers.
        var headers: HTTPHeaders
        /// The HTTP headers provided after a chunked body, if any.
        var trailerHeaders: HTTPHeaders = [:]
        /// The request body, if provided.
        var body: NSData?
        
        var description: String {
            return  "Request(\(method) \(urlComponents.path ?? "nil"), httpVersion: \(httpVersion), "
                + "headers: \(headers.dictionary), trailerHeaders: \(trailerHeaders.dictionary), "
                + "body: \(body?.length ?? 0) bytes)"
        }
        
        var debugDescription: String {
            return "HTTPServer.Request(method: \(method), path: \(String(reflecting: urlComponents.path)), httpVersion: \(httpVersion), "
                + "headers: \(headers), trailerHeaders: \(trailerHeaders), body: \(body))"
        }
        
        private init?(method: Method, requestTarget: String, httpVersion: HTTPVersion, headers: HTTPHeaders = [:], body: NSData? = nil) {
            self.method = method
            guard let comps = NSURLComponents(string: requestTarget) else { return nil }
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
        var body: NSData?
        
        init(status: Status, headers: HTTPHeaders = [:], body: NSData? = nil) {
            self.status = status
            self.headers = headers
            self.body = body
            // If the headers don't include Date, let's set it automatically
            if self.headers.indexForKey("Date") == nil {
                self.headers["Date"] = HTTPServer.httpDateFormatter.stringFromDate(NSDate())
            }
        }
        
        init(status: Status, headers: HTTPHeaders = [:], body: String) {
            self.init(status: status, headers: headers, body: body.dataUsingEncoding(NSUTF8StringEncoding)!)
        }
        
        init(status: Status, headers: HTTPHeaders = [:], text: String) {
            var headers = headers
            headers["Content-Type"] = "text/plain"
            self.init(status: status, headers: headers, body: text)
        }
        
        var description: String {
            return "Response(\(status.rawValue) \(status), headers: \(headers.dictionary), body: \(body?.length ?? 0) bytes)"
        }
        
        var debugDescription: String {
            return "HTTPServer.Response(status: \(status.rawValue) \(status), headers: \(headers), body: \(body))"
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
            var body: NSData
            /// The body data parsed as a UTF-8 string, or `nil` if it couldn't be parsed.
            /// - Note: This ignores any encoding specified in a `"Content-Type"` header on
            ///   the part.
            var bodyText: String? {
                return String(data: body, encoding: NSUTF8StringEncoding)
            }
            
            /// Parses an NSData containing everything between the boundaries.
            /// Returns `nil` if the headers are not well-formed.
            init?(content: NSData) {
                let anchoredEmptyLineRange = content.rangeOfData(CRLF, options: .Anchored, range: NSRange(0..<content.length)).toRange()
                guard let emptyLineRange = anchoredEmptyLineRange ?? content.rangeOfData(CRLFCRLF, options: [], range: NSRange(0..<content.length)).toRange()
                    else { return nil }
                body = content.subdataWithRange(NSRange(emptyLineRange.endIndex..<content.length))
                let headerData = content.subdataWithRange(NSRange(0..<emptyLineRange.startIndex))
                guard let headerContent = String(bytes: headerData.bufferPointer, encoding: NSASCIIStringEncoding)?.chomped()
                    else { return nil }
                headers = HTTPHeaders()
                var lines = unfoldLines(headerContent.componentsSeparatedByString("\r\n"))
                if lines.last == "" {
                    lines.removeLast()
                }
                for line in lines {
                    guard let idx = line.unicodeScalars.indexOf(":") else { return nil }
                    let field = String(line.unicodeScalars.prefixUpTo(idx))
                    var scalars = line.unicodeScalars.suffixFrom(idx.successor())
                    // skip leading OWS
                    if let idx = scalars.indexOf({ $0 != " " && $0 != "\t" }) {
                        scalars = scalars.suffixFrom(idx)
                        // skip trailing OWS
                        let idx = scalars.reverse().indexOf({ $0 != " " && $0 != "\t" })!
                        // idx.base is the successor to the element, so prefixUpTo() cuts off at the right spot
                        scalars = scalars.prefixUpTo(idx.base)
                    } else {
                        scalars = scalars.suffixFrom(scalars.endIndex)
                    }
                    headers[field] = String(scalars)
                }
                contentDisposition = headers["Content-Disposition"].map({ ContentDisposition($0) })
                contentType = headers["Content-Type"].map({ MediaType($0) })
            }
        }
        
        enum Error: ErrorType {
            case ContentTypeNotMultipart
            case NoBody
            case NoBoundary
            case InvalidBoundary
            case CannotFindFirstBoundary
            case CannotFindBoundaryTerminator
            case InvalidBodyPartHeaders
        }
        
        /// The MIME type of the multipart body, such as `"multipart/form-data"`.
        /// The `contentType` is guaranteed to start with `"multipart/"`.
        var contentType: String
        
        /// The body parts.
        var parts: [Part]
        
        /// Parses a multipart request.
        /// - Throws: `MultipartBody.Error` if the `Content-Type` is not
        ///   multipart or the `body` is not formatted properly.
        private init(request: Request) throws {
            guard let contentType = request.headers["Content-Type"].map(MediaType.init)
                where contentType.type == "multipart"
                else { throw Error.ContentTypeNotMultipart }
            guard let boundary = contentType.params.find({ $0.0 == "boundary" })?.1
                else { throw Error.NoBoundary }
            guard let body = request.body
                else { throw Error.NoBody }
            self.contentType = contentType.typeSubtype
            guard !boundary.unicodeScalars.contains({ $0 == "\r" || $0 == "\n" }),
                let boundaryData = "--\(boundary)".dataUsingEncoding(NSUTF8StringEncoding)
                else { throw Error.InvalidBoundary }
            let bytes = body.bufferPointer
            func findBoundary(sourceRange: Range<Int>) -> (range: Range<Int>, isTerminator: Bool)? {
                var sourceRange = sourceRange
                repeat {
                    guard var range = body.rangeOfData(boundaryData, options: [], range: NSRange(sourceRange)).toRange() else {
                        // Couldn't find a boundary
                        return nil
                    }
                    if range.startIndex >= 2 && (bytes[range.startIndex-2], bytes[range.startIndex-1]) == (0x0D, 0x0A) {
                        // The boundary is preceeded by CRLF.
                        // Include the CRLF in the range (as long as it's still within sourceRange)
                        range.startIndex = max(sourceRange.startIndex, range.startIndex-2)
                    } else if range.startIndex != 0 {
                        // The boundary isn't at the start of the data, and isn't preceeded by CRLF.
                        // `range` doesn't contain any CRLF characters, so we can skip the whole thing.
                        sourceRange.startIndex = range.endIndex
                        continue
                    }
                    // Is this a terminator?
                    var isTerminator = false
                    if range.endIndex + 1 < bytes.endIndex && (bytes[range.endIndex], bytes[range.endIndex+1]) == (0x2D, 0x2D) { // "--"
                        isTerminator = true
                        range.endIndex += 2
                    }
                    // Skip optional LWS
                    while range.endIndex != bytes.endIndex && (UnicodeScalar(bytes[range.endIndex]) == " " || UnicodeScalar(bytes[range.endIndex]) == "\t") {
                        range.endIndex += 1
                    }
                    if isTerminator && range.endIndex == bytes.endIndex {
                        // no more data, which is acceptable for the terminator line
                        return (range, isTerminator)
                    } else if range.endIndex + 1 < bytes.endIndex && (bytes[range.endIndex], bytes[range.endIndex+1]) == (0x0D, 0x0A) { // the boundary is preceeded by CRLF
                        // CRLF terminator
                        range.endIndex += 2
                        return (range, isTerminator)
                    }
                    // Otherwise, this supposed boundary line isn't a valid boundary. Search again
                    sourceRange.startIndex = range.endIndex
                } while true
            }
            parts = []
            var sourceRange = 0..<body.length
            guard var boundaryInfo = findBoundary(sourceRange)
                else { throw Error.CannotFindFirstBoundary }
            while !boundaryInfo.isTerminator {
                let startIdx = boundaryInfo.range.endIndex
                sourceRange.startIndex = startIdx
                guard let nextBoundary = findBoundary(sourceRange)
                    else { throw Error.CannotFindBoundaryTerminator }
                boundaryInfo = nextBoundary
                let content = body.subdataWithRange(NSRange(startIdx..<boundaryInfo.range.startIndex))
                guard let part = Part(content: content)
                    else { throw Error.InvalidBodyPartHeaders }
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
            if let idx = rawValue.unicodeScalars.indexOf(";") {
                value = trimLWS(String(rawValue.unicodeScalars.prefixUpTo(idx)))
                params = DelimitedParameters(String(rawValue.unicodeScalars.suffixFrom(idx.successor())), delimiter: ";")
            } else {
                value = rawValue
                params = DelimitedParameters("", delimiter: ";")
            }
        }
    }
    
    private let shared: QueueConfined<Shared>
    private let listener: Listener
    
    private class Shared {
        var listenErrorCallback: (NSError -> Void)?
        var requestCallbacks: [(token: CallbackToken, callback: (request: Request, completionHandler: Response? -> Void) -> Void)] = []
        var unhandledRequestCallback: ((request: Request, response: Response, completionHandler: Response -> Void) -> Void)?
    }
    
    private class Listener : NSObject, GCDAsyncSocketDelegate {
        let shared: QueueConfined<Shared>
        let socket = GCDAsyncSocket()!
        let queue = dispatch_queue_create("HTTPServer listen queue", DISPATCH_QUEUE_SERIAL)!
        var connections: [Connection] = []
        
        init(shared: QueueConfined<Shared>) {
            self.shared = shared
            super.init()
            socket.setDelegate(self, delegateQueue: queue)
        }
        
        deinit {
            socket.synchronouslySetDelegate(nil)
        }
        
        /// Stops listening for new connections and disconnects all existing connections.
        /// Returns a `dispatch_block_t` created with `dispatch_block_create()` that can
        // be waited on with `dispatch_block_wait(_:_:)` or `dispatch_block_notify(_:_:_:)`.
        func invalidate() -> dispatch_block_t {
            log("Invalidated")
            socket.delegate = nil
            socket.disconnect()
            return reset()
        }
        
        /// Disconnects all existing connections but does not stop listening for new ones.
        /// Returns a `dispatch_block_t` created with `dispatch_block_create()` that can
        // be waited on with `dispatch_block_wait(_:_:)` or `dispatch_block_notify(_:_:_:)`.
        func reset() -> dispatch_block_t {
            let block = dispatch_block_create(dispatch_block_flags_t(0)) {
                for connection in self.connections {
                    connection.invalidate()
                }
                self.connections.removeAll()
            }
            dispatch_async(queue, block)
            return block
        }
        
        private func log(@autoclosure msg: () -> String) {
            if HTTPServer.enableDebugLogging {
                NSLog("<HTTP Server %@:%hu> %@", socket.localHost ?? "nil", socket.localPort ?? 0, msg())
            }
        }
        
        @objc func socket(sock: GCDAsyncSocket!, didAcceptNewSocket newSocket: GCDAsyncSocket!) {
            let connection = Connection(shared: shared, listener: self, socket: newSocket)
            log("New connection (id: \(connection.connectionId)) from \(newSocket.connectedHost):\(newSocket.connectedPort)")
            connections.append(connection)
            connection.readRequestLine()
        }
        
        @objc func socketDidDisconnect(sock: GCDAsyncSocket!, withError err: NSError!) {
            // we should only get this if an error occurs, because we nil out the delegate before closing ourselves
            guard let err = err else {
                log("Disconnected")
                return
            }
            log("Disconnected with error: \(err)")
            shared.async { shared in
                if let callback = replace(&shared.listenErrorCallback, with: nil) {
                    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
                        callback(err)
                    }
                }
            }
        }
    }
    
    private class Connection : NSObject, GCDAsyncSocketDelegate {
        let shared: QueueConfined<Shared>
        weak var listener: Listener?
        let socket: GCDAsyncSocket
        let queue = dispatch_queue_create("HTTPServer connection queue", DISPATCH_QUEUE_SERIAL)!
        var request: HTTPServer.Request?
        var chunkedBody: NSMutableData?
        var chunkedTrailer: NSData?
        
        let connectionId: Int32 // DEBUG
        
        static var lastConnectionId: Int32 = 0 // DEBUG
        
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
        
        private func log(@autoclosure msg: () -> String) {
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
        
        func readRequestLine() {
            log("Reading request line...")
            socket.readDataToData(CRLF, withTimeout: -1, tag: Tag.RequestLine.rawValue)
        }
        
        private func dispatchRequest() {
            log("Dispatching request")
            guard let request = self.request else {
                return writeResponseAndClose(Response(status: .InternalServerError, text: "Couldn't find active request"))
            }
            shared.async { shared in
                let callbacks = shared.requestCallbacks
                let unhandledRequestCallback = shared.unhandledRequestCallback
                let queue = dispatch_queue_create("HTTPServer request callback queue", DISPATCH_QUEUE_SERIAL)
                var gen = callbacks.generate()
                func invokeNextCallback() {
                    guard let (_, cb) = gen.next() else {
                        let response = Response(status: .NotFound)
                        if let unhandledRequestCallback = unhandledRequestCallback {
                            self.log("Invoking unhandled request callback")
                            unhandledRequestCallback(request: request, response: response) { response in
                                self.writeResponse(response)
                            }
                        } else {
                            self.log("Request not handled; sending 404 Not Found")
                            self.writeResponse(Response(status: .NotFound))
                        }
                        return
                    }
                    var invoked = false
                    cb(request: request) { response in
                        // sanity check to make sure we haven't been called already
                        // we'll check again on `queue` because that's the definitive spot, but we're doing an early check here
                        // to provide a better stack trace if the precondition fails.
                        precondition(invoked == false, "HTTPServer request completion handler invoked more than once")
                        dispatch_async(queue) {
                            precondition(invoked == false, "HTTPServer request completion handler invoked more than once")
                            invoked = true
                            if let response = response {
                                self.writeResponse(response)
                            } else {
                                invokeNextCallback()
                            }
                        }
                    }
                }
                dispatch_async(queue) {
                    invokeNextCallback()
                }
            }
        }
        
        private func writeResponse(response: Response) {
            log("Writing response: \(response.status)")
            let request = replace(&self.request, with: nil)
            chunkedBody = nil
            chunkedTrailer = nil
            var response = response
            if let body = response.body {
                response.headers.removeValueForKey("Transfer-Encoding")
                response.headers["Content-Length"] = String(body.length)
            } else if response.headers["Content-Length"] == nil && response.headers["Transfer-Encoding"] == nil {
                response.headers["Content-Length"] = "0"
            }
            var text = "HTTP/1.1 \(response.status)\r\n"
            for (field,value) in response.headers {
                text += "\(field): \(value)\r\n"
            }
            text += "\r\n"
            socket.writeData(text.dataUsingEncoding(NSUTF8StringEncoding), withTimeout: -1, tag: 0)
            if let body = response.body where body.length > 0 {
                switch (request?.method, response.status) {
                case (.CONNECT?, _) where response.status.isSuccessful: fallthrough
                case _ where response.status.isInformational: fallthrough
                case (_, .NoContent), (_, .NotModified):
                    // no body can be present. Print a warning and throw it away
                    NSLog("warning: HTTPServer tried to send response \(response.status) to request method \(request?.method as ImplicitlyUnwrappedOptional) with non-empty body")
                    log("Disconnecting...")
                    socket.disconnectAfterWriting()
                    return
                case (.HEAD?, _):
                    // no body can be present, but sending Content-Length is legitimate, so just silently ignore the body
                    break
                default:
                    log("Writing response body (\(body.length) bytes)")
                    socket.writeData(body, withTimeout: -1, tag: 0)
                }
            }
            // NB: We don't support comma-separated connection options here
            if response.headers["Connection"]?.caseInsensitiveCompare("close") == .OrderedSame
                || (request?.httpVersion == HTTPVersion(1,0) && response.headers["Connection"]?.caseInsensitiveCompare("keep-alive") != .OrderedSame)
                || request?.httpVersion < HTTPVersion(1,0)
            {
                log("Disconnecting...")
                socket.disconnectAfterWriting()
            } else {
                // if we're not disconnecting, we might be getting a new request instead
                readRequestLine()
            }
        }
        
        private func writeResponseAndClose(response: Response) {
            var response = response
            response.headers["Connection"] = "close"
            writeResponse(response)
        }
        
        /// Parses headers from the given data. If a parse error occurs,
        /// returns `nil` and sends a BadRequest response.
        /// The given closure is invoked for each header, with the old value (if one exists).
        /// The `field` parameter to the closure always contains the normalized name of the header.
        /// If the closure returns a `Response`, that response is sent to the server and the socket closed.
        private func parseHeadersFromData(data: NSData, @noescape _ f: (field: String, value: String, oldValue: String?) -> Response? = { _ in nil }) -> HTTPHeaders? {
            guard let line = String(bytes: data.bufferPointer, encoding: NSASCIIStringEncoding)?.chomped() else {
                writeResponseAndClose(Response(status: .BadRequest, text: "Non-ASCII headers are not supported"))
                return nil
            }
            var headers = HTTPHeaders()
            var comps = unfoldLines(line.componentsSeparatedByString("\r\n"))
            if comps.last == "" {
                comps.removeLast()
            }
            for comp in comps {
                guard let idx = comp.unicodeScalars.indexOf(":") else {
                    writeResponseAndClose(Response(status: .BadRequest, text: "Illegal header line syntax"))
                    return nil
                }
                let field = String(comp.unicodeScalars.prefixUpTo(idx))
                var scalars = comp.unicodeScalars.suffixFrom(idx.successor())
                // skip leading OWS
                if let idx = scalars.indexOf({ $0 != " " && $0 != "\t" }) {
                    scalars = scalars.suffixFrom(idx)
                    // skip trailing OWS
                    let idx = scalars.reverse().indexOf({ $0 != " " && $0 != "\t" })!
                    // idx.base is the successor to the element, so prefixUpTo() cuts off at the right spot
                    scalars = scalars.prefixUpTo(idx.base)
                } else {
                    scalars = scalars.suffixFrom(scalars.endIndex)
                }
                let value = String(scalars)
                let normalizedField = HTTPHeaders.normalizedHTTPHeaderField(field)
                let oldValue = headers.unsafeUpdateValue(value, forPreNormalizedKey: normalizedField)
                if let response = f(field: normalizedField, value: value, oldValue: oldValue) {
                    writeResponseAndClose(response)
                    return nil
                }
                headers[field] = value
            }
            return headers
        }
        
        private enum Tag: Int {
            case RequestLine = 1
            case RequestLineStrict
            case Headers
            case FixedLengthBody
            case ChunkedBodySize
            case ChunkedBodyData
            case ChunkedBodyTrailer
        }
        
        @objc func socket(sock: GCDAsyncSocket!, didReadData data: NSData!, withTag tag: Int) {
            switch Tag(rawValue: tag)! {
            case .RequestLine:
                // Robust servers should skip at least one CRLF before the request.
                if data.isEqualToData(CRLF) {
                    log("Skipping CRLF request prefix...")
                    socket.readDataToData(CRLF, withTimeout: -1, tag: Tag.RequestLineStrict.rawValue)
                } else {
                    fallthrough
                }
            case .RequestLineStrict:
                guard let line = String(bytes: data.bufferPointer, encoding: NSASCIIStringEncoding)?.chomped() else {
                    log("Parsing request line: \(data)")
                    return writeResponseAndClose(Response(status: .BadRequest, text: "Non-ASCII request line not supported"))
                }
                log("Parsing request line: \(String(reflecting: line))")
                let comps = line.unicodeScalars.split(isSeparator: { $0 == " " }).map(String.init)
                guard comps.count == 3 else {
                    return writeResponseAndClose(Response(status: .BadRequest, text: "Invalid request line syntax"))
                }
                var version = comps[2]
                guard version.hasPrefix("HTTP/") else {
                    return writeResponseAndClose(Response(status: .BadRequest, text: "Couldn't find HTTP version in request line"))
                }
                version.unicodeScalars.removeFirst(5)
                let httpVersion: HTTPVersion
                switch version {
                case "0.9": httpVersion = HTTPVersion(0,9)
                case "1.0": httpVersion = HTTPVersion(1,0)
                case "1.1": httpVersion = HTTPVersion(1,1)
                default: return writeResponseAndClose(Response(status: .HTTPVersionNotSupported))
                }
                let method = Method(comps[0])
                if case .Other(let name) = method {
                    return writeResponseAndClose(Response(status: .MethodNotAllowed, text: "Method \(name) not supported"))
                }
                guard let request = Request(method: method, requestTarget: comps[1], httpVersion: httpVersion) else {
                    return writeResponseAndClose(Response(status: .BadRequest))
                }
                self.request = request
                log("Reading request headers...")
                socket.readDataToData(CRLFCRLF, withTimeout: -1, tag: Tag.Headers.rawValue)
            case .Headers:
                log("Parsing request headers")
                guard var request = replace(&self.request, with: nil) else {
                    return writeResponseAndClose(Response(status: .InternalServerError, text: "Couldn't find active request"))
                }
                var multipleContentLengths = false
                guard let headers = parseHeadersFromData(data, { (field: String, value: String, oldValue: String?) in
                    if field == "Content-Length", let oldValue = oldValue where oldValue != value {
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
                    if value.caseInsensitiveCompare("chunked") != .OrderedSame {
                        return writeResponseAndClose(Response(status: .NotImplemented, text: "The only supported Transfer-Encoding is chunked"))
                    }
                    chunkedBody = NSMutableData()
                    chunkedTrailer = nil // just in case
                    log("Reading chunked body...")
                    socket.readDataToData(CRLF, withTimeout: -1, tag: Tag.ChunkedBodySize.rawValue)
                } else if multipleContentLengths {
                    return writeResponseAndClose(Response(status: .BadRequest, text: "Multiple Content-Length headers found"))
                } else if let value = request.headers["Content-Length"] {
                    if let length = Int(value) where length >= 0 {
                        if length == 0 {
                            dispatchRequest()
                        } else if length > 5 * 1024 * 1024 {
                            log("Content-Length too large (\(length) bytes)")
                            return writeResponseAndClose(Response(status: .RequestEntityTooLarge, text: "Requests limited to 5MB"))
                        } else {
                            log("Reading fixed length body (\(length) bytes)...")
                            socket.readDataToLength(UInt(length), withTimeout: -1, tag: Tag.FixedLengthBody.rawValue)
                        }
                    } else {
                        return writeResponseAndClose(Response(status: .BadRequest, text: "Invalid Content-Length"))
                    }
                } else {
                    // assume length of 0
                    dispatchRequest()
                }
            case .FixedLengthBody:
                log("Received fixed length body")
                guard var request = replace(&self.request, with: nil) else {
                    return writeResponseAndClose(Response(status: .InternalServerError, text: "Couldn't find active request"))
                }
                request.body = data
                self.request = request
                dispatchRequest()
            case .ChunkedBodySize:
                log("Parsing chunked body chunk")
                guard let chunkedBody = self.chunkedBody else {
                    return writeResponseAndClose(Response(status: .InternalServerError, text: "Couldn't find active chunk body"))
                }
                let buffer = data.bufferPointer
                func isHexDigit(c: UInt8) -> Bool {
                    switch UnicodeScalar(c) {
                    case "0"..."9": return true
                    case "a"..."f": return true
                    case "A"..."F": return true
                    default: return false
                    }
                }
                guard let idx = buffer.indexOf({ !isHexDigit($0) }) else {
                    // surely we should have found the CR
                    return writeResponseAndClose(Response(status: .BadRequest, text: "Invalid chunk syntax"))
                }
                switch UnicodeScalar(buffer[idx]) {
                case ";":
                    // the rest of the line is a chunk extension
                    // don't even bother parsing it for validity, we just ignore all extensions
                    break
                case "\r":
                    // line ending
                    break
                default:
                    return writeResponseAndClose(Response(status: .BadRequest, text: "Invalid chunk syntax"))
                }
                guard let size = UInt(String(buffer.prefixUpTo(idx).lazy.map({Character(UnicodeScalar($0))})), radix: 16) else {
                    return writeResponseAndClose(Response(status: .BadRequest, text: "Invalid chunk size"))
                }
                if size == 0 {
                    log("Last chunk; reading trailer...")
                    request?.body = chunkedBody
                    chunkedTrailer = nil // just in case
                    socket.readDataToLength(2, withTimeout: -1, tag: Tag.ChunkedBodyTrailer.rawValue)
                } else {
                    guard UInt(chunkedBody.length) + size <= 5 * 1024 * 1024 else {
                        log("Chunk too large (\(size) bytes, \(UInt(chunkedBody.length) + size) total)")
                        return writeResponseAndClose(Response(status: .RequestEntityTooLarge, text: "Requests limited to 5MB"))
                    }
                    log("Reading chunk data (\(size) bytes)...")
                    socket.readDataToLength(size + 2, withTimeout: -1, tag: Tag.ChunkedBodyData.rawValue)
                }
            case .ChunkedBodyData:
                log("Received chunk data")
                guard let chunkedBody = chunkedBody else {
                    return writeResponseAndClose(Response(status: .InternalServerError, text: "Couldn't find active chunk body"))
                }
                chunkedBody.appendData(data)
                // the appended data had a CRLF trailer, chop it off now
                chunkedBody.length -= 2
                log("Reading next chunk...")
                socket.readDataToData(CRLF, withTimeout: -1, tag: Tag.ChunkedBodySize.rawValue)
            case .ChunkedBodyTrailer:
                log("Processing chunked body trailer")
                if let chunkedTrailer = replace(&self.chunkedTrailer, with: nil) {
                    guard var request = replace(&self.request, with: nil) else {
                        return writeResponseAndClose(Response(status: .InternalServerError, text: "Couldn't find active request"))
                    }
                    let trailer = NSMutableData(data: chunkedTrailer)
                    trailer.appendData(data)
                    guard let headers = parseHeadersFromData(trailer) else {
                        // response was already written
                        return
                    }
                    request.trailerHeaders = headers
                    self.request = request
                    dispatchRequest()
                } else {
                    // either contains a CRLF or contains the first line of the trailer headers
                    if data.isEqualToData(CRLF) {
                        dispatchRequest()
                    } else {
                        chunkedTrailer = data
                        log("Reading trailer headers...")
                        socket.readDataToData(CRLFCRLF, withTimeout: -1, tag: Tag.ChunkedBodyTrailer.rawValue)
                    }
                }
            }
        }
        
        @objc func socketDidDisconnect(sock: GCDAsyncSocket!, withError err: NSError!) {
            log("Disconnected")
            if request != nil {
                NSLog("HTTPServer: received disconnection while processing request; error: %@", err ?? "nil")
            }
            socket.delegate = nil
            if let listener = listener {
                dispatch_async(listener.queue) {
                    if let idx = listener.connections.indexOf({ $0 === self }) {
                        listener.connections.removeAtIndex(idx)
                    }
                }
            }
        }
    }
}

extension String {
    /// Returns the string with a trailing CRLF, CR, or LF chopped off, if present.
    /// Only chops off one line ending.
    @warn_unused_result private func chomped() -> String {
        if hasSuffix("\r\n") {
            return String(unicodeScalars.dropLast(2))
        } else if hasSuffix("\r") || hasSuffix("\n") {
            return String(unicodeScalars.dropLast())
        } else {
            return self
        }
    }
}

private func replace<T>(inout a: T, with b: T) -> T {
    var value = b
    swap(&a, &value)
    return value
}

extension HTTPServer.Status : CustomStringConvertible {
    var description: String {
        let name: String
        switch self {
        case .OK: name = "OK"
        case .Created: name = "Created"
        case .Accepted: name = "Accepted"
        case .NoContent: name = "No Content"
        case .MultipleChoices: name = "Multiple Choices"
        case .MovedPermanently: name = "Moved Permanently"
        case .Found: name = "Found"
        case .SeeOther: name = "See Other"
        case .NotModified: name = "Not Modified"
        case .TemporaryRedirect: name = "Temporary Redirect"
        case .BadRequest: name = "Bad Request"
        case .Unauthorized: name = "Unauthorized"
        case .Forbidden: name = "Forbidden"
        case .NotFound: name = "Not Found"
        case .MethodNotAllowed: name = "Method Not Allowed"
        case .NotAcceptable: name = "Not Acceptable"
        case .Gone: name = "Gone"
        case .LengthRequired: name = "Length Required"
        case .RequestEntityTooLarge: name = "Request Entity Too Large"
        case .RequestURITooLong: name = "Request-URI Too Long"
        case .UnsupportedMediaType: name = "Unsupported Media Type"
        case .InternalServerError: name = "Internal Server Error"
        case .NotImplemented: name = "Not Implemented"
        case .BadGateway: name = "Bad Gateway"
        case .ServiceUnavailable: name = "Service Unavailable"
        case .HTTPVersionNotSupported: name = "HTTP Version Not Supported"
        }
        return "\(rawValue) \(name)"
    }
}

private let CRLF: NSData = NSData(bytes: "\r\n", length: 2)
private let CRLFCRLF: NSData = NSData(bytes: "\r\n\r\n", length: 4)

extension NSData {
    private var bufferPointer: UnsafeBufferPointer<UInt8> {
        return UnsafeBufferPointer(start: UnsafePointer(bytes), count: length)
    }
}

func ==(lhs: HTTPServer.Method, rhs: HTTPServer.Method) -> Bool {
    switch (lhs, rhs) {
    case let (.Other(a), .Other(b)): return a == b
    case (.Other, _), (_, .Other): return false
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
        && lhs.params.elementsEqual(rhs.params, isEquivalent: { $0.0.caseInsensitiveCompare($1.0) == .OrderedSame && $0.1 == $1.1 })
}


func <(lhs: HTTPServer.HTTPVersion, rhs: HTTPServer.HTTPVersion) -> Bool {
    return lhs.major < rhs.major || (lhs.major == rhs.major && lhs.minor < rhs.minor)
}

func unfoldLines(lines: [String]) -> [String] {
    var result: [String] = []
    result.reserveCapacity(lines.count)
    for var line in lines {
        if line.hasPrefix("\t") {
            line.unicodeScalars.replaceRange(line.unicodeScalars.startIndex...line.unicodeScalars.startIndex, with: CollectionOfOne(" "))
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
    let options: NSStringCompareOptions
}

private func comparable(string: String, options: NSStringCompareOptions) -> StringComparable {
    return StringComparable(string: string, options: options)
}

private func ~=(comparable: StringComparable, value: String) -> Bool {
    return comparable.string.compare(value, options: comparable.options) == .OrderedSame
}
