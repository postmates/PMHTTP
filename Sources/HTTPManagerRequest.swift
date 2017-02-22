//
//  HTTPManagerRequest.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 1/4/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Foundation
@_exported import PMJSON

/// An HTTP request.
///
/// **Thread safety:**
/// This class can be safely read from concurrent threads, but any modifications require exclusive access.
public class HTTPManagerRequest: NSObject, NSCopying {
    /// An HTTP method verb.
    public enum Method: String, LosslessStringConvertible {
        case GET, POST, PUT, PATCH, DELETE
        
        public var description: String {
            return rawValue
        }
        
        public init?(_ description: String) {
            self.init(rawValue: description)
        }
        
        fileprivate var isIdempotent: Bool {
            switch self {
            case .GET, .PUT, .DELETE: return true
            case .POST, .PATCH: return false
            }
        }
    }
    
    /// The URL for the request, including any query items as appropriate.
    public var url: URL {
        if parameters.isEmpty {
            return baseURL
        }
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            fatalError("HTTPManager: base URL cannot be parsed by URLComponents: \(baseURL.relativeString)")
        }
        if var query = comps.percentEncodedQuery, !query.isEmpty {
            query += "&"
            query += FormURLEncoded.string(for: parameters)
            comps.percentEncodedQuery = query
        } else {
            comps.percentEncodedQuery = FormURLEncoded.string(for: parameters)
        }
        return comps.url(relativeTo: baseURL.baseURL)!
    }
    
    /// The request method.
    public let requestMethod: Method
    
    /// `true` if the request is idempotent, otherwise `false`. A request is idempotent if
    /// the side-effects of N > 0 identical requests is the same as for a single request,
    /// or in other words, the request can be repeated without changing anything.
    ///
    /// - Note: A sequence of several idempotent requests may not be idempotent as a whole.
    ///   This could be because a later request in the sequence changes something that
    ///   affects an earlier request.
    ///
    /// This property normally only affects retry behavior for failed requests, although
    /// it could be used for external functionality such as showing a Retry button in an
    /// error dialog. The value of this property is exposed on `HTTPManagerTask` as well.
    ///
    /// - Note: When writing external functionality that uses `isIdempotent` (such as showing
    ///   a Retry button) it's generally a good idea to only repeat requests that failed.
    ///   It should be safe to repeat successful idempotent network requests, but parse requests
    ///   may have parse handlers with side-effects. If you care about idempotence for successful
    ///   or canceled requests, you should ensure that all parse handlers are idempotent or
    ///   mark any relevant parse requests as non-idempotent.
    ///
    /// The default value is `true` for GET, HEAD, PUT, DELETE, OPTIONS, and TRACE requests,
    /// and `false` for POST, PATCH, CONNECT, or unknown request methods.
    @nonobjc public var isIdempotent: Bool
    
    /// The Content-Type for the request.
    /// If no data is being submitted in the request body, the `contentType`
    /// will be empty.
    public var contentType: String {
        return ""
    }
    
    /// The request parameters, or `[]` if there are no parameters.
    /// The parameters are passed by default in the URL query string.
    /// Subclasses may override this behavior.
    public fileprivate(set) var parameters: [URLQueryItem]
    
    /// The `HTTPAuth` value to use for the request. Default is the value of
    /// `HTTPManager.defaultAuth`.
    ///
    /// - SeeAlso: `HTTPBasicAuth`.
    public var auth: HTTPAuth?
    
    /// The timeout interval of the request, in seconds. If `nil`, the session's default
    /// timeout interval is used. Default is `nil`.
    public var timeoutInterval: TimeInterval?
    
    /// The cache policy to use for the request. If `nil`, the default cache policy
    /// is used. Default is `nil` for GET/HEAD requests and `.reloadIgnoringLocalCacheData`
    /// for POST/PUT/PATCH/DELETE requests.
    public fileprivate(set) var cachePolicy: NSURLRequest.CachePolicy?
    
    /// The default cache storage policy to use for the response if the response does not
    /// include appropriate caching headers. If the response does include appropriate headers
    /// such as `Cache-Control` or `Expires`, this property is ignored.
    ///
    /// This property only establishes an upper bound on the cache storage allowed. If the
    /// URL session proposes to store the cached response in-memory only and the default policy
    /// is set to `.allowed`, the response will still be stored in-memory only, and if the URL
    /// session proposes to not cache the response at all, the response will not be cached.
    ///
    /// The default value is `.allowed` for most requests, and `.notAllowed` for parse requests
    /// created from `parseAsJSON()` or `parseAsJSON(with:)`.
    public var defaultResponseCacheStoragePolicy: URLCache.StoragePolicy = .allowed
    
    /// `true` iff redirects should be followed when processing the response.
    /// If `false`, network requests return a successful result containing the redirection
    /// response, and parse requests return an error with `HTTPManagerError.unexpectedRedirect`.
    /// Default is `true`.
    public var shouldFollowRedirects: Bool = true
    
    /// Indicates whether the request is allowed to use the cellular radio. Default is `true`.
    /// If the session configuration's `allowsCellularAccess` is `false`, access to the cellular
    /// radio is always denied regardless of the request's `allowsCellularAccess` property.
    public var allowsCellularAccess: Bool = true
    
    /// Whether the request represents an action the user is waiting on.
    /// Set this to `true` to increase the priority. Default is `false`.
    public var userInitiated: Bool = false
    
    /// The retry behavior to use for the request. Default is the value of
    /// `HTTPManager.defaultRetryBehavior`.
    public var retryBehavior: HTTPManagerRetryBehavior?
    
    /// Whether errors should be assumed to be JSON.
    ///
    /// If `true`, all error bodies are parsed as JSON regardless of their declared
    /// Content-Type. This setting is intended to work around bad servers that
    /// don't declare their Content-Types properly.
    ///
    /// The default value is provided by `HTTPManager.defaultAssumeErrorsAreJSON`.
    public var assumeErrorsAreJSON: Bool = false
    
    /// Whether tasks created from this request should affect the visiblity of the
    /// network activity indicator. Default is `true`.
    ///
    /// Strictly speaking, this controls whether the task is visible to the network activity
    /// handler (if any), and it's the handler's job to show the activity indicator.
    public var affectsNetworkActivityIndicator: Bool = true
    
    /// Additional HTTP header fields to pass in the request. Default is `[:]`.
    ///
    /// - Note: `Content-Type` and `Content-Length` are always ignored. If `self.auth` is non-`nil`,
    ///   it may override other headers, in particular `"Authorization"`.
    public var headerFields: HTTPHeaders = [:]
    
    // possibly expose some URLRequest properties here, if they're useful
    
    // See Mocking.swift for details.
    internal var mock: HTTPMockInstance?
    
    /// Executes a block with `self` as the argument, and then returns `self` again.
    /// - Parameter f: A block to execute, with `self` as the argument.
    /// - Returns: `self`.
    /// This method exists to help with functional-style chaining, e.g.:
    /// ```
    /// HTTP.request(GET: "foo")
    ///     .parseAsJSON(with: { doParse($1) })
    ///     .with({ $0.userInitiated = true })
    ///     .performRequest { task, result in
    ///         // ...
    /// }
    /// ```
    @nonobjc public func with(_ f: (HTTPManagerRequest) throws -> Void) rethrows -> Self {
        try f(self)
        return self
    }
    
    public func copy(with _: NSZone? = nil) -> Any {
        return type(of: self).init(__copyOfRequest: self)
    }
    
    // MARK: Internal
    
    internal init(apiManager: HTTPManager, URL url: URL, method: Method, parameters: [URLQueryItem]) {
        self.apiManager = apiManager
        baseURL = url
        requestMethod = method
        isIdempotent = method.isIdempotent
        self.parameters = parameters
        super.init()
    }
    
    internal let apiManager: HTTPManager
    
    internal let baseURL: URL
    
    /// Implementation detail of `copyWithZone(_:)`.
    /// - Parameter request: Guaranteed to be the same type as `self`.
    public required init(__copyOfRequest request: HTTPManagerRequest) {
        apiManager = request.apiManager
        baseURL = request.baseURL
        requestMethod = request.requestMethod
        isIdempotent = request.isIdempotent
        parameters = request.parameters
        auth = request.auth
        timeoutInterval = request.timeoutInterval
        cachePolicy = request.cachePolicy
        shouldFollowRedirects = request.shouldFollowRedirects
        defaultResponseCacheStoragePolicy = request.defaultResponseCacheStoragePolicy
        allowsCellularAccess = request.allowsCellularAccess
        userInitiated = request.userInitiated
        retryBehavior = request.retryBehavior
        assumeErrorsAreJSON = request.assumeErrorsAreJSON
        mock = request.mock
        affectsNetworkActivityIndicator = request.affectsNetworkActivityIndicator
        headerFields = request.headerFields
        super.init()
    }
    
    /// Returns the URL request, without applying the auth headers.
    internal final var _preparedURLRequest: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = requestMethod.rawValue
        if let policy = cachePolicy {
            request.cachePolicy = policy
        }
        if let timeout = timeoutInterval {
            request.timeoutInterval = timeout
        }
        request.allowsCellularAccess = allowsCellularAccess
        request.allHTTPHeaderFields = headerFields.dictionary
        let contentType = self.contentType
        if contentType.isEmpty {
            request.allHTTPHeaderFields?["Content-Type"] = nil
        } else {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.allHTTPHeaderFields?["Content-Length"] = nil
        prepareURLRequest()?(&request)
        return request
    }
    
    internal func prepareURLRequest() -> ((inout URLRequest) -> Void)? {
        return nil
    }
}

extension HTTPManagerRequest {
    /// A collection of HTTP header fields.
    ///
    /// Exposes a `Dictionary`-like interface but guarantees that all header names are normalized.
    public struct HTTPHeaders : Collection, CustomStringConvertible, CustomDebugStringConvertible, ExpressibleByDictionaryLiteral {
        public typealias Index = Dictionary<String,String>.Index
        public typealias Iterator = Dictionary<String,String>.Iterator
        
        /// Returns a `Dictionary` representation of the header set.
        public private(set) var dictionary: [String: String] = [:]
        
        public init() {}
        
        public init(dictionaryLiteral elements: (String, String)...) {
            dictionary = Dictionary(minimumCapacity: elements.count)
            for (key,value) in elements {
                precondition(!key.isEmpty, "HTTPHeaders cannot contain an empty key")
                dictionary[HTTPHeaders.normalizedHTTPHeaderField(key)] = value
            }
        }
        
        public init(_ dictionary: [String: String]) {
            self.dictionary = Dictionary(minimumCapacity: dictionary.count)
            for (key,value) in dictionary where !key.isEmpty {
                self.dictionary[HTTPHeaders.normalizedHTTPHeaderField(key)] = value
            }
        }
        
        public var description: String {
            return String(describing: dictionary)
        }
        
        public var debugDescription: String {
            return "HTTPHeaders(\(String(reflecting: dictionary)))"
        }
        
        /// Adds an HTTP header to the list of header fields.
        ///
        /// - Parameter value: The value for the header field.
        /// - Parameter field: The name of the header field. Header fields are case-insensitive.
        ///
        /// If a value was previously set for the specified *field*, the supplied *value* is appended
        /// to the existing value using the appropriate field delimiter.
        public mutating func addValue(_ value: String, forHeaderField field: String) {
            guard !field.isEmpty else { return }
            let field = HTTPHeaders.normalizedHTTPHeaderField(field)
            if let oldValue = dictionary[field] {
                if field == "Cookie" {
                    dictionary[field] = "\(oldValue); \(value)"
                } else {
                    dictionary[field] = "\(oldValue),\(value)"
                }
            } else {
                dictionary[field] = value
            }
        }
        
        public var count: Int {
            return dictionary.count
        }
        
        public var isEmpty: Bool {
            return dictionary.isEmpty
        }
        
        public var startIndex: Index {
            return dictionary.startIndex
        }
        
        public var endIndex: Index {
            return dictionary.endIndex
        }
        
        public subscript(position: Index) -> (key: String, value: String) {
            return dictionary[position]
        }
        
        public subscript(key: String) -> String? {
            get {
                return dictionary[HTTPHeaders.normalizedHTTPHeaderField(key)]
            }
            set {
                guard !key.isEmpty else { return }
                dictionary[HTTPHeaders.normalizedHTTPHeaderField(key)] = newValue
            }
        }
        
        public func index(forKey key: String) -> Index? {
            return dictionary.index(forKey: key)
        }
        
        public func index(after i: Index) -> Index {
            return dictionary.index(after: i)
        }
        
        public func formIndex(after i: inout Index) {
            dictionary.formIndex(after: &i)
        }
        
        public mutating func append(contentsOf newElements: HTTPHeaders) {
            // the headers are already normalized so we can avoid re-normalizing
            for (key,value) in newElements {
                dictionary[key] = value
            }
        }
        
        public mutating func popFirst() -> (String, String)? {
            return dictionary.popFirst()
        }
        
        public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
            dictionary.removeAll(keepingCapacity: keepCapacity)
        }
        
        public mutating func remove(at index: Index) -> (String, String) {
            return dictionary.remove(at: index)
        }
        
        public mutating func removeValue(forKey key: String) -> String? {
            return dictionary.removeValue(forKey: HTTPHeaders.normalizedHTTPHeaderField(key))
        }
        
        public mutating func updateValue(_ value: String, forKey key: String) -> String? {
            return dictionary.updateValue(value, forKey: HTTPHeaders.normalizedHTTPHeaderField(key))
        }
        
        internal mutating func unsafeUpdateValue(_ value: String, forPreNormalizedKey key: String) -> String? {
            return dictionary.updateValue(value, forKey: key)
        }
        
        public func makeIterator() -> Dictionary<String,String>.Iterator {
            return dictionary.makeIterator()
        }
        
        /// Normalizes an HTTP header field.
        ///
        /// The returned value uses titlecase, including the first letter after `-`.
        /// Known acronyms are preserved in uppercase. Invalid characters are replaced
        /// with `_`.
        public static func normalizedHTTPHeaderField(_ field: String) -> String {
            func normalizeComponent(_ comp: String) -> String {
                if comp.caseInsensitiveCompare("WWW") == .orderedSame {
                    return "WWW"
                } else if comp.caseInsensitiveCompare("ETag") == .orderedSame {
                    return "ETag"
                } else if comp.caseInsensitiveCompare("MD5") == .orderedSame {
                    return "MD5"
                } else if comp.caseInsensitiveCompare("TE") == .orderedSame {
                    return "TE"
                } else if comp.caseInsensitiveCompare("DNI") == .orderedSame {
                    return "DNI"
                } else {
                    var comp = comp
                    // replace invalid characters
                    let cs = CharacterSet.httpHeaderValidCharacters
                    func isValid(_ us: UnicodeScalar) -> Bool {
                        switch us {
                        case "!", "#", "$", "%", "&", "'", "*", "+", "-", ".", "^", "_", "`", "|", "~": return true
                        case "0"..."9": return true
                        case "a"..."z", "A"..."Z": return true
                        default: return false
                        }
                    }
                    if comp.unicodeScalars.contains(where: { !cs.contains($0) }) {
                        var scalars = String.UnicodeScalarView()
                        swap(&comp.unicodeScalars, &scalars)
                        defer { swap(&comp.unicodeScalars, &scalars) }
                        while let idx = scalars.index(where: { !cs.contains($0) }) {
                            scalars.replaceSubrange(idx..<scalars.index(after: idx), with: CollectionOfOne("_"))
                        }
                    }
                    return comp.capitalized
                }
            }
            
            return field.components(separatedBy: "-").lazy.map(normalizeComponent).joined(separator: "-")
        }
    }
}

private extension CharacterSet {
    static let httpHeaderValidCharacters: CharacterSet = {
        var cs = CharacterSet()
        cs.insert(charactersIn: "!#$%&'*+-.^_`|~")
        cs.insert(charactersIn: UnicodeScalar("0")...UnicodeScalar("9"))
        cs.insert(charactersIn: UnicodeScalar("a")...UnicodeScalar("z"))
        cs.insert(charactersIn: UnicodeScalar("A")...UnicodeScalar("Z"))
        return cs
    }()
}

// MARK: - Network Request

/// An HTTP request that does not yet have a parse handler.
public class HTTPManagerNetworkRequest: HTTPManagerRequest, HTTPManagerRequestPerformable {
    /// The request parameters, or `[]` if there are no parameters.
    /// The parameters are passed by default in the URL query string.
    /// Subclasses may override this behavior.
    public override var parameters: [URLQueryItem] {
        get { return super.parameters }
        set { super.parameters = newValue }
    }
    
    /// Creates and returns a `URLRequest` object from the properties of `self`.
    /// For upload requests, the request will include the `HTTPBody` or `HTTPBodyStream`
    /// as appropriate.
    public var preparedURLRequest: URLRequest {
        var request = _preparedURLRequest
        auth?.applyHeaders(to: &request)
        switch uploadBody {
        case .data(let data)?:
            request.httpBody = data
        case .formUrlEncoded(let queryItems)?:
            request.httpBody = FormURLEncoded.data(for: queryItems)
        case .json(let json)?:
            request.httpBody = JSON.encodeAsData(json)
        case let .multipartMixed(boundary, parameters, bodyParts)?:
            // We have at least one Pending value, we need to wait for them to evaluate (otherwise we can't
            // accurately implement the `canRead` stream callback).
            for case .pending(let deferred) in bodyParts {
                deferred.wait()
            }
            request.httpBodyStream = HTTPBody.createMultipartMixedStream(boundary, parameters: parameters, bodyParts: bodyParts)
        case nil:
            break
        }
        return request
    }
    
    /// Returns a new request that parses the data with the specified handler.
    /// - Note: If the server responds with 204 No Content, the parse handler is
    ///   invoked with an empty data. The handler may choose to throw
    ///   `HTTPManagerError.unexpectedNoContent` if it does not handle this case.
    /// - Parameter handler: The handler to call as part of the request
    ///   processing. This handler is not guaranteed to be called on any
    ///   particular thread. The handler returns the new value for the request.
    /// - Returns: An `HTTPManagerParseRequest`.
    /// - Note: If you need to parse on a particular thread, such as on the main
    ///   thread, you should use `performRequest(withCompletionQueue:completion:)` instead.
    /// - Warning: If the request is canceled, the results of the handler may be
    ///   discarded. Any side-effects performed by your handler must be safe in
    ///   the event of a cancelation.
    /// - Warning: The parse request inherits the `isIdempotent` value of `self`.
    ///   If the parse handler has side effects and can throw, you should either
    ///   ensure that it's safe to run the parse handler again or set `isIdempotent`
    ///   to `false`.
    public func parse<T>(using handler: @escaping (_ response: URLResponse, _ data: Data) throws -> T) -> HTTPManagerParseRequest<T> {
        return HTTPManagerParseRequest(request: self, uploadBody: uploadBody, parseHandler: handler)
    }
    
    /// Creates a suspended `HTTPManagerTask` for the request with the given completion handler.
    ///
    /// This method is intended for cases where you need access to the `URLSessionTask` prior to
    /// the task executing, e.g. if you need to record the task identifier somewhere before the
    /// completion block fires.
    /// - Parameter queue: (Optional) The queue to call the handler on. The default value
    ///   of `nil` means the handler will be called on a global concurrent queue.
    /// - Parameter completion: The handler to call when the request is done. This handler
    ///   will be invoked on *queue* if provided, otherwise on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    /// - Important: After you create the task, you must start it by calling the `resume()` method.
    public func createTask(withCompletionQueue queue: OperationQueue? = nil, completion: @escaping (_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<Data>) -> Void) -> HTTPManagerTask {
        let completion = completionThunk(for: completion)
        return apiManager.createNetworkTaskWithRequest(self, uploadBody: uploadBody,
                                                       processor: networkTaskProcessor(queue: queue,
                                                                                       processor: HTTPManagerNetworkRequest.taskProcessor,
                                                                                       taskCompletion: HTTPManagerNetworkRequest.taskCompletion,
                                                                                       completion: completion))
    }
    
    /// Executes a block with `self` as the argument, and then returns `self` again.
    /// - Parameter f: A block to execute, with `self` as the argument.
    /// - Returns: `self`.
    /// This method exists to help with functional-style chaining, e.g.:
    /// ```
    /// HTTP.request(GET: "foo")
    ///     .parseAsJSON(with: { doParse($1) })
    ///     .with({ $0.userInitiated = true })
    ///     .performRequest { task, result in
    ///         // ...
    /// }
    /// ```
    @nonobjc public override func with(_ f: (HTTPManagerNetworkRequest) throws -> Void) rethrows -> Self {
        try f(self)
        return self
    }
    
    private static func taskProcessor(_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<Data>) -> HTTPManagerTaskResult<Data> {
        return result.map(try: { response, data in
            if let response = response as? HTTPURLResponse, case let statusCode = response.statusCode, !(200...399).contains(statusCode) {
                let json: JSON?
                switch response.mimeType.map(MediaType.init) {
                case _ where task.assumeErrorsAreJSON: fallthrough
                case MediaType("application/json")?, MediaType("text/json")?: json = try? JSON.decode(data)
                default: json = nil
                }
                if statusCode == 401 { // Unauthorized
                    throw HTTPManagerError.unauthorized(auth: task.auth, response: response, body: data, bodyJson: json)
                } else {
                    throw HTTPManagerError.failedResponse(statusCode: statusCode, response: response, body: data, bodyJson: json)
                }
            }
            return data
        })
    }
    
    private static func taskCompletion(_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<Data>, _ handler: @escaping (HTTPManagerTask, HTTPManagerTaskResult<Data>) -> Void) {
        let transition = task.transitionState(to: .completed)
        if transition.ok {
            assert(transition.oldState != .completed, "internal HTTPManager error: tried to complete task that's already completed")
            handler(task, result)
        } else {
            assert(transition.oldState == .canceled, "internal HTTPManager error: tried to complete task that's not processing")
            handler(task, .canceled)
        }
    }
    
    internal var uploadBody: UploadBody? {
        return nil
    }
}

// MARK: HTTPManagerRequestPerformable

/// A protocol for `HTTPManagerRequest`s that can be performed.
public protocol HTTPManagerRequestPerformable {
    associatedtype ResultValue
    
    /// Performs an asynchronous request and calls the specified handler when done.
    /// - Parameter queue: The queue to call the handler on. `nil` means the handler will
    ///   be called on a global concurrent queue.
    /// - Parameter completion: The handler to call when the request is done. This handler
    ///   will be invoked on *queue* if provided, otherwise on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    @discardableResult
    func performRequest(withCompletionQueue queue: OperationQueue?, completion: @escaping (_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<ResultValue>) -> Void) -> HTTPManagerTask
    
    /// Creates a suspended `HTTPManagerTask` for the request with the given completion handler.
    ///
    /// This method is intended for cases where you need access to the `URLSessionTask` prior to
    /// the task executing, e.g. if you need to record the task identifier somewhere before the
    /// completion block fires.
    /// - Parameter queue: The queue to call the handler on. `nil` means the handler will
    ///   be called on a global concurrent queue.
    /// - Parameter completion: The handler to call when the request is done. This handler
    ///   will be invoked on *queue* if provided, otherwise on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    /// - Important: After you create the task, you must start it by calling the `resume()` method.
    func createTask(withCompletionQueue queue: OperationQueue?, completion: @escaping (_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<ResultValue>) -> Void) -> HTTPManagerTask
}

extension HTTPManagerRequestPerformable {
    /// Performs an asynchronous request and calls the specified handler when done.
    /// - Parameter queue: (Optional) The queue to call the handler on. The default value
    ///   of `nil` means the handler will be called on a global concurrent queue.
    /// - Parameter handler: The handler to call when the request is done. The handler
    ///   will be invoked on *queue* if provided, otherwise on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    @discardableResult
    public func performRequest(withCompletionQueue queue: OperationQueue? = nil, completion: @escaping (_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<ResultValue>) -> Void) -> HTTPManagerTask {
        let task = createTask(withCompletionQueue: queue, completion: completion)
        task.resume()
        return task
    }
    
    /// A workaround to ensure the completion block deinits on the queue where it's fired from.
    ///
    /// Ownership of blocks is not passed directly into the queue that runs them, which means they could get
    /// deallocated from the calling thread if the queue runs the block before control returns back to that
    /// calling thread. We guard against that here by forcing the completion block to be released immediately
    /// after it's fired. This ensures that it can only be deallocated on the completion queue or the thread that
    /// creates the task in the first place.
    fileprivate func completionThunk(for block: @escaping (_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<ResultValue>) -> Void) -> (HTTPManagerTask, HTTPManagerTaskResult<ResultValue>) -> Void {
        var unmanagedThunk: Unmanaged<Thunk<(HTTPManagerTask, HTTPManagerTaskResult<ResultValue>), Void>>? = Unmanaged.passRetained(Thunk(block))
        return { (task, result) in
            let thunk = unmanagedThunk.unsafelyUnwrapped.takeRetainedValue()
            unmanagedThunk = nil // effectively a debug assertion that ensures we don't call the completion block twice
            thunk.block(task, result)
        }
    }
}

/// A wrapper class that allows us to stuff the block into an `Unmanaged`.
private class Thunk<Args,ReturnValue> {
    let block: (Args) -> ReturnValue
    init(_ block: @escaping (Args) -> ReturnValue) {
        self.block = block
    }
}

private func networkTaskProcessor<T>(queue: OperationQueue?,
                                  processor: @escaping (HTTPManagerTask, HTTPManagerTaskResult<Data>) -> HTTPManagerTaskResult<T>,
                                  taskCompletion: @escaping (HTTPManagerTask, HTTPManagerTaskResult<T>, @escaping (HTTPManagerTask, HTTPManagerTaskResult<T>) -> Void) -> Void,
                                  completion: @escaping (HTTPManagerTask, HTTPManagerTaskResult<T>) -> Void)
    -> (HTTPManagerTask, HTTPManagerTaskResult<Data>, _ authToken: Any??, _ attempt: Int, _ retry: @escaping (_ isAuthRetry: Bool) -> Bool) -> Void
{
    return { (task, result, authToken, attempt, retry) in
        let result = processor(task, result)
        func runCompletion() {
            if let queue = queue {
                queue.addOperation {
                    taskCompletion(task, result, completion)
                }
            } else {
                taskCompletion(task, result, completion)
            }
        }
        if case .error(_, let HTTPManagerError.unauthorized(auth?, response, body, _)) = result {
            if let token = authToken, let handleUnauthorized = auth.handleUnauthorized {
                var alreadyCalled = false // attempt to detect multiple invocations of the block. Not guaranteed to work.
                handleUnauthorized(response, body, task, token) { shouldRetry in
                    if alreadyCalled {
                        NSLog("[HTTPManager] HTTPAuth completion block invoked multiple times (\(type(of: auth)))")
                        assertionFailure("HTTPAuth completion block invoked multiple times")
                        return
                    }
                    alreadyCalled = true
                    autoreleasepool {
                        if !(shouldRetry && retry(true)) {
                            runCompletion()
                        }
                    }
                }
            } else {
                runCompletion()
            }
        } else if case .error(_, let error) = result, let retryBehavior = task.retryBehavior {
            retryBehavior.handler(task, error, attempt, { shouldRetry in
                if !(shouldRetry && retry(false)) {
                    runCompletion()
                }
            })
        } else {
            runCompletion()
        }
    }
}

// MARK: - Data Request

/// An HTTP GET/HEAD request that does not yet have a parse handler.
public class HTTPManagerDataRequest: HTTPManagerNetworkRequest {
    /// The cache policy to use for the request. If `nil`, the default cache policy
    /// is used. Default is `nil`.
    public override var cachePolicy: NSURLRequest.CachePolicy? {
        get { return super.cachePolicy }
        set { super.cachePolicy = newValue }
    }
    
    /// Returns a new request that parses the data as JSON.
    /// - Note: If the server responds with 204 No Content, the parse is skipped
    ///   and `HTTPManagerError.unexpectedNoContent` is returned as the parse result.
    /// - Parameter options: Options to use for JSON parsing. Defaults to `[]`.
    /// - Returns: An `HTTPManagerParseRequest`.
    public func parseAsJSON(options: JSONOptions = []) -> HTTPManagerParseRequest<JSON> {
        return HTTPManagerParseRequest(request: self, uploadBody: uploadBody, expectedContentTypes: ["application/json"], defaultResponseCacheStoragePolicy: .notAllowed, parseHandler: { response, data in
            if let response = response as? HTTPURLResponse, response.statusCode == 204 {
                throw HTTPManagerError.unexpectedNoContent(response: response)
            }
            return try JSON.decode(data, options: options)
        })
    }
    
    /// Returns a new request that parses the data as JSON and passes it through
    /// the specified handler.
    /// - Note: If the server responds with 204 No Content, the parse is skipped
    ///   and `HTTPManagerError.unexpectedNoContent` is returned as the parse result.
    /// - Parameter options: Options to use for JSON parsing. Defaults to `[]`.
    /// - Parameter handler: The handler to call as part of the request
    ///   processing. This handler is not guaranteed to be called on any
    ///   particular thread. The handler returns the new value for the request.
    /// - Returns: An `HTTPManagerParseRequest`.
    /// - Note: If you need to parse on a particular thread, such as on the main
    ///   thread, you should use `performRequest(withCompletionQueue:completion:)` instead.
    /// - Warning: If the request is canceled, the results of the handler may be
    ///   discarded. Any side-effects performed by your handler must be safe in
    ///   the event of a cancelation.
    /// - Warning: The parse request inherits the `isIdempotent` value of `self`.
    ///   If the parse handler has side effects and can throw, you should either
    ///   ensure that it's safe to run the parse handler again or set `isIdempotent`
    ///   to `false`.
    public func parseAsJSON<T>(options: JSONOptions = [], using handler: @escaping (_ response: URLResponse, _ json: JSON) throws -> T) -> HTTPManagerParseRequest<T> {
        return HTTPManagerParseRequest(request: self, uploadBody: uploadBody, expectedContentTypes: ["application/json"], defaultResponseCacheStoragePolicy: .notAllowed, parseHandler: { response, data in
            if let response = response as? HTTPURLResponse, response.statusCode == 204 {
                throw HTTPManagerError.unexpectedNoContent(response: response)
            }
            return try handler(response, JSON.decode(data, options: options))
        })
    }
    
    /// Executes a block with `self` as the argument, and then returns `self` again.
    /// - Parameter f: A block to execute, with `self` as the argument.
    /// - Returns: `self`.
    /// This method exists to help with functional-style chaining, e.g.:
    /// ```
    /// HTTP.request(GET: "foo")
    ///     .parseAsJSON(with: { doParse($1) })
    ///     .with({ $0.userInitiated = true })
    ///     .performRequest { task, result in
    ///         // ...
    /// }
    /// ```
    @nonobjc public override func with(_ f: (HTTPManagerDataRequest) throws -> Void) rethrows -> Self {
        try f(self)
        return self
    }
}

// MARK: - Parse Request

/// An HTTP request that has a parse handler.
public final class HTTPManagerParseRequest<T>: HTTPManagerRequest, HTTPManagerRequestPerformable {
    /// The URL for the request, including any query items as appropriate.
    public override var url: URL {
        return baseURL
    }
    
    /// The Content-Type for the request.
    /// If no data is being submitted in the request body, the `contentType`
    /// will be empty.
    public override var contentType: String {
        return _contentType
    }
    
    /// The expected MIME type of the response. Defaults to `["application/json"]`
    /// for JSON parse requests, or `[]` for requests created with `parse(with:)`.
    ///
    /// This property is used to generate the `Accept` header, if not otherwise specified by
    /// the request. If multiple values are provided, they're treated as a priority list
    /// for the purposes of the `Accept` header.
    ///
    /// This property is also used to validate the MIME type of the response. If the
    /// response is a 204 No Content, the MIME type is not checked. For all other 2xx
    /// responses, if at least one expected content type is provided, the MIME type
    /// must match one of them. If it doesn't match any, the parse handler will be
    /// skipped and `HTTPManagerError.unexpectedContentType` will be returned as the result.
    ///
    /// - Note: The MIME type is only tested if the response includes a `Content-Type` header.
    ///   If the `Content-Type` header is missing, the response will always be assumed to be
    ///   valid. The value is tested against both the `Content-Type` header and, if it differs,
    ///   the `URLResponse` property `mimeType`. This is to account for cases where the
    ///   protocol implementation detects a different content type than the server declared.
    ///
    /// Each media type in the list may include parameters. These parameters will be included
    /// in the `Accept` header, but will be ignored for the purposes of comparing against the
    /// resulting MIME type. If the media type includes a parameter named `q`, this parameter
    /// should be last, as it will be interpreted by the `Accept` header as the priority
    /// instead of as a parameter of the media type.
    ///
    /// - Note: Changing the `expectedContentTypes` does not affect the behavior of the parse
    ///   handler. If you create a request using `parseAsJSON()` and then change the
    ///   `expectedContentTypes` to `["text/plain"]`, if the server returns a `"text/plain"`
    ///   response, the parse handler will still assume it's JSON and attempt to decode it.
    ///
    /// - Important: The media types in this list will not be checked for validity. They must
    ///   follow the rules for well-formed media types, otherwise the server may handle the
    ///   request incorrectly.
    public var expectedContentTypes: [String]
    
    /// Creates a suspended `HTTPManagerTask` for the request with the given completion handler.
    ///
    /// This method is intended for cases where you need access to the `URLSessionTask` prior to
    /// the task executing, e.g. if you need to record the task identifier somewhere before the
    /// completion block fires.
    /// - Parameter queue: (Optional) The queue to call the handler on. The default value
    ///   of `nil` means the handler will be called on a global concurrent queue.
    /// - Parameter completion: The handler to call when the request is done. This handler
    ///   will be invoked on *queue* if provided, otherwise on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    /// - Important: After you create the task, you must start it by calling the `resume()` method.
    public func createTask(withCompletionQueue queue: OperationQueue? = nil, completion: @escaping (_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<T>) -> Void) -> HTTPManagerTask {
        let parseHandler: (URLResponse, Data) throws -> T
        let expectedContentTypes: [String]
        if let dataMock = dataMock {
            parseHandler = { _ in dataMock() }
            expectedContentTypes = [] // skip Content-Type handling in the task processor
        } else {
            parseHandler = self.parseHandler
            expectedContentTypes = self.expectedContentTypes
        }
        let completion = completionThunk(for: completion)
        return apiManager.createNetworkTaskWithRequest(self, uploadBody: uploadBody,
                                                       processor: networkTaskProcessor(queue: queue,
                                                                                       processor: { (task, result) in HTTPManagerParseRequest<T>.taskProcessor(task, result, expectedContentTypes, parseHandler) },
                                                                                       taskCompletion: HTTPManagerParseRequest<T>.taskCompletion,
                                                                                       completion: completion))
    }
    
    /// Executes a block with `self` as the argument, and then returns `self` again.
    /// - Parameter f: A block to execute, with `self` as the argument.
    /// - Returns: `self`.
    /// This method exists to help with functional-style chaining, e.g.:
    /// ```
    /// HTTP.request(GET: "foo")
    ///     .parseAsJSON(with: { doParse($1) })
    ///     .with({ $0.userInitiated = true })
    ///     .performRequest { task, result in
    ///         // ...
    /// }
    /// ```
    @nonobjc public override func with(_ f: (HTTPManagerParseRequest) throws -> Void) rethrows -> Self {
        try f(self)
        return self
    }
    
    private static func taskProcessor(_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<Data>, _ expectedContentTypes: [String], _ parseHandler: @escaping (URLResponse, Data) throws -> T) -> HTTPManagerTaskResult<T> {
        // check for cancellation before processing
        if task.state == .canceled {
            return .canceled
        }
        
        return result.map(try: { response, data in
            if let response = response as? HTTPURLResponse {
                let statusCode = response.statusCode
                if (300...399).contains(statusCode) {
                    // parsed results can't accept redirects
                    let location = (response.allHeaderFields["Location"] as? String).flatMap({URL(string: $0)})
                    throw HTTPManagerError.unexpectedRedirect(statusCode: statusCode, location: location, response: response, body: data)
                } else if !(200...299).contains(statusCode) {
                    let json: JSON?
                    switch response.mimeType.map(MediaType.init) {
                    case _ where task.assumeErrorsAreJSON: fallthrough
                    case MediaType("application/json")?, MediaType("text/json")?: json = try? JSON.decode(data)
                    default: json = nil
                    }
                    if statusCode == 401 { // Unauthorized
                        throw HTTPManagerError.unauthorized(auth: task.auth, response: response, body: data, bodyJson: json)
                    } else {
                        throw HTTPManagerError.failedResponse(statusCode: statusCode, response: response, body: data, bodyJson: json)
                    }
                } else if statusCode != 204 && !expectedContentTypes.isEmpty, let contentType = (response.allHeaderFields["Content-Type"] as? String).map(MediaType.init), !contentType.typeSubtype.isEmpty {
                    // Not a 204 No Content, check the MIME type against the list
                    // As per the doc comment on expectedContentTypes, we check both the response mimeType and, if it's different, the Content-Type header.
                    var mimeType = response.mimeType.map(MediaType.init)
                    if mimeType?.rawValue == contentType.rawValue {
                        mimeType = nil
                    }
                    let contentTypeAlias = contentTypeAliases[contentType.typeSubtype].map(MediaType.init)
                    let mimeTypeAlias = mimeType.flatMap({ contentTypeAliases[$0.typeSubtype].map(MediaType.init) })
                    let valid = expectedContentTypes.contains(where: {
                        // ignore the parameters from expectedContentTypes
                        let pattern = MediaType(MediaType($0).typeSubtype)
                        if let mimeType = mimeType, pattern ~= mimeType { return true }
                        if pattern ~= contentType { return true }
                        if let contentTypeAliases = contentTypeAlias, pattern ~= contentTypeAliases { return true }
                        if let mimeTypeAlias = mimeTypeAlias, pattern ~= mimeTypeAlias { return true }
                        return false
                    })
                    if !valid {
                        throw HTTPManagerError.unexpectedContentType(contentType: (mimeType ?? contentType).rawValue, response: response, body: data)
                    }
                }
            }
            return try parseHandler(response, data)
        })
    }
    
    private static func taskCompletion(_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<T>, _ handler: @escaping (HTTPManagerTask, HTTPManagerTaskResult<T>) -> Void) {
        let transition = task.transitionState(to: .completed)
        if transition.ok {
            assert(transition.oldState != .completed, "internal HTTPManager error: tried to complete task that's already completed")
            handler(task, result)
        } else {
            assert(transition.oldState == .canceled, "internal HTTPManager error: tried to complete task that's not processing")
            handler(task, .canceled)
        }
    }
    
    private let parseHandler: (URLResponse, Data) throws -> T
    private let prepareRequestHandler: ((inout URLRequest) -> Void)?
    private let _contentType: String
    private let uploadBody: UploadBody?
    
    // See Mocking.swift for details.
    // This is a closure instead of just `T?` to avoid bloating the request object if `T` is large.
    internal var dataMock: (() -> T)?
    
    internal init(request: HTTPManagerRequest, uploadBody: UploadBody?, expectedContentTypes: [String] = [], defaultResponseCacheStoragePolicy: URLCache.StoragePolicy? = nil, parseHandler: @escaping (URLResponse, Data) throws -> T) {
        self.parseHandler = parseHandler
        prepareRequestHandler = request.prepareURLRequest()
        _contentType = request.contentType
        self.uploadBody = uploadBody
        self.expectedContentTypes = expectedContentTypes
        super.init(apiManager: request.apiManager, URL: request.url, method: request.requestMethod, parameters: request.parameters)
        isIdempotent = request.isIdempotent
        auth = request.auth
        timeoutInterval = request.timeoutInterval
        cachePolicy = request.cachePolicy
        shouldFollowRedirects = request.shouldFollowRedirects
        self.defaultResponseCacheStoragePolicy = defaultResponseCacheStoragePolicy ?? request.defaultResponseCacheStoragePolicy
        allowsCellularAccess = request.allowsCellularAccess
        userInitiated = request.userInitiated
        retryBehavior = request.retryBehavior
        assumeErrorsAreJSON = request.assumeErrorsAreJSON
        mock = request.mock
        affectsNetworkActivityIndicator = request.affectsNetworkActivityIndicator
        headerFields = request.headerFields
    }
    
    public required init(__copyOfRequest request: HTTPManagerRequest) {
        let request = unsafeDowncast(request, to: HTTPManagerParseRequest<T>.self)
        parseHandler = request.parseHandler
        prepareRequestHandler = request.prepareRequestHandler
        _contentType = request._contentType
        uploadBody = request.uploadBody
        expectedContentTypes = request.expectedContentTypes
        dataMock = request.dataMock
        super.init(__copyOfRequest: request)
    }
    
    internal override func prepareURLRequest() -> ((inout URLRequest) -> Void)? {
        if !expectedContentTypes.isEmpty {
            return { [expectedContentTypes, prepareRequestHandler] request in
                if request.allHTTPHeaderFields?["Accept"] == nil {
                    request.setValue(acceptHeaderValueForContentTypes(expectedContentTypes), forHTTPHeaderField: "Accept")
                }
                prepareRequestHandler?(&request)
            }
        } else {
            return prepareRequestHandler
        }
    }
}

private let contentTypeAliases: [String: String] = ["text/json": "application/json"]

private func acceptHeaderValueForContentTypes(_ contentTypes: [String]) -> String {
    guard var value = contentTypes.first else { return "" }
    var priority = 9
    for contentType in contentTypes.dropFirst() {
        let mediaType = MediaType(contentType)
        if mediaType.params.contains(where: { $0.0.caseInsensitiveCompare("q") == .orderedSame && $0.1 != nil }) {
            value += ", \(contentType)"
        } else {
            value += ", \(contentType);q=0.\(priority)"
            if priority > 1 { //
                priority -= 1
            }
        }
    }
    return value
}

// MARK: - Action Request

/// An HTTP POST/PUT/PATCH/DELETE request that does not yet have a parse handler.
///
/// Similar to an `HTTPManagerDataRequest` except that it handles 204 No Content
/// instead of throwing `HTTPManagerError.unexpectedNoContent`.
public class HTTPManagerActionRequest: HTTPManagerNetworkRequest {
    /// The results of parsing for use in parse methods that take handlers.
    public typealias ParseResult<T> = HTTPManagerActionParseResult<T>
    @available(*, deprecated, renamed: "ParseResult")
    public typealias JSONResult = ParseResult<JSON>
    
    /// Returns a new request that parses the data as JSON.
    /// - Note: The parse result is `nil` if and only if the server responded with
    ///   204 No Content.
    /// - Parameter options: Options to use for JSON parsing. Defaults to `[]`.
    /// - Returns: An `HTTPManagerParseRequest`.
    public func parseAsJSON(options: JSONOptions = []) -> HTTPManagerParseRequest<JSON?> {
        return HTTPManagerParseRequest(request: self, uploadBody: uploadBody, expectedContentTypes: ["application/json"], defaultResponseCacheStoragePolicy: .notAllowed, parseHandler: { response, data in
            if (response as? HTTPURLResponse)?.statusCode == 204 {
                // No Content
                return nil
            } else {
                return try JSON.decode(data, options: options)
            }
        })
    }
    
    /// Returns a new request that parses the data as JSON and passes it through
    /// the specified handler.
    /// - Parameter options: Options to use for JSON parsing. Defaults to `[]`.
    /// - Parameter handler: The handler to call as part of the request
    ///   processing. This handler is not guaranteed to be called on any
    ///   particular thread. The handler returns the new value for the request.
    /// - Returns: An `HTTPManagerParseRequest`.
    /// - Note: If you need to parse on a particular thread, such as on the main
    ///   thread, you should use `performRequest(withCompletionQueue:completion:)` instead.
    /// - Warning: If the request is canceled, the results of the handler may be
    ///   discarded. Any side-effects performed by your handler must be safe in
    ///   the event of a cancelation.
    /// - Warning: The parse request inherits the `isIdempotent` value of `self`.
    ///   If the parse handler has side effects and can throw, you should either
    ///   ensure that it's safe to run the parse handler again or set `isIdempotent`
    ///   to `false`.
    public func parseAsJSON<T>(options: JSONOptions = [], using handler: @escaping (ParseResult<JSON>) throws -> T) -> HTTPManagerParseRequest<T> {
        return HTTPManagerParseRequest(request: self, uploadBody: uploadBody, expectedContentTypes: ["application/json"], defaultResponseCacheStoragePolicy: .notAllowed, parseHandler: { response, data in
            if let response = response as? HTTPURLResponse, response.statusCode == 204 {
                // No Content
                return try handler(.noContent(response))
            } else {
                return try handler(.success(response, JSON.decode(data, options: options)))
            }
        })
    }
    
    /// Executes a block with `self` as the argument, and then returns `self` again.
    /// - Parameter f: A block to execute, with `self` as the argument.
    /// - Returns: `self`.
    /// This method exists to help with functional-style chaining, e.g.:
    /// ```
    /// HTTP.request(POST: "foo")
    ///     .parseAsJSON(with: { doParse($1) })
    ///     .with({ $0.userInitiated = true })
    ///     .performRequest { task, result in
    ///         // ...
    /// }
    /// ```
    @nonobjc public override func with(_ f: (HTTPManagerActionRequest) throws -> Void) rethrows -> Self {
        try f(self)
        return self
    }
    
    internal override init(apiManager: HTTPManager, URL url: URL, method: Method, parameters: [URLQueryItem]) {
        super.init(apiManager: apiManager, URL: url, method: method, parameters: parameters)
        cachePolicy = .reloadIgnoringLocalCacheData
    }
    
    public required init(__copyOfRequest request: HTTPManagerRequest) {
        super.init(__copyOfRequest: request)
    }
}

/// The results of parsing for use in `HTTPManagerActionRequest` parse methods that take handlers.
public enum HTTPManagerActionParseResult<T> {
    /// The server returned 204 No Content.
    case noContent(HTTPURLResponse)
    /// The server returned a valid response.
    case success(URLResponse, T)
    
    /// The server response.
    public var response: URLResponse {
        switch self {
        case .noContent(let response): return response
        case .success(let response, _): return response
        }
    }
    
    /// The parsed response, or `nil` if the server returned 204 No Content.
    public var value: T? {
        switch self {
        case .noContent: return nil
        case .success(_, let json): return json
        }
    }
    
    /// Returns the parsed response, or throws `HTTPManagerError.unexpectedNoContent` if the server
    /// returned 204 No Content.
    public func getValue() throws -> T {
        switch self {
        case .noContent(let response): throw HTTPManagerError.unexpectedNoContent(response: response)
        case .success(_, let value): return value
        }
    }
}

// MARK: - Upload Form Request

/// An HTTP POST/PUT/PATCH request with form data that does not yet have a parse handler.
///
/// By default, any request parameters (see `HTTPManagerRequest.parameters`) are
/// passed as `application/x-www-form-urlencoded`. Adding any multipart bodies
/// passes everything as `multipart/form-data` instead. When mixing *parameters*
/// and multipart bodies, the *parameters* are sent prior to any multipart bodies.
public final class HTTPManagerUploadFormRequest: HTTPManagerActionRequest {
    /// The URL for the request, including any query items as appropriate.
    public override var url: URL {
        return baseURL
    }
    
    /// The Content-Type for the request.
    /// - Returns: Either `"application/x-www-form-urlencoded"` or `"multipart/form-data"`
    ///   depending on the nature of the upload.
    public override var contentType: String {
        if multipartBodies.isEmpty {
            return "application/x-www-form-urlencoded"
        } else {
            return "multipart/form-data"
        }
    }
    
    /// Specifies a named multipart body for this request.
    ///
    /// Calling this method sets the request's overall Content-Type to
    /// `multipart/form-data`.
    ///
    /// - Bug: `name` and `filename` are assumed to be ASCII and not need any escaping.
    ///
    /// - Parameters:
    ///   - data: The data for the multipart body, such as an image or text.
    ///   - name: The name of the multipart body. This is the name the server expects.
    ///   - mimeType: The MIME content type of the multipart body. Optional.
    ///   - filename: The filename of the attachment. Optional.
    @objc(addMultipartData:withName:mimeType:filename:)
    public func addMultipart(data: Data, withName name: String, mimeType: String? = nil, filename: String? = nil) {
        multipartBodies.append(.known(.init(.data(data), name: name, mimeType: mimeType, filename: filename)))
    }
    
    /// Specifies a named multipart body for this request.
    ///
    /// The Content-Type of the multipart body will always be
    /// `text/plain; charset=utf-8`.
    ///
    /// Calling this method sets the request's overall Content-Type to
    /// `multipart/form-data`.
    ///
    /// - Bug: `name` is assumed to be ASCII and not need any escaping.
    ///
    /// - Parameter text: The text of the multipart body.
    /// - Parameter name: The name of the multipart body. This is the name the server expects.
    @objc(addMultipartText:withName:)
    public func addMultipart(text: String, withName name: String) {
        multipartBodies.append(.known(.init(.text(text), name: name)))
    }
    
    /// Adds a block that's invoked asynchronously to provide multipart bodies for this request.
    ///
    /// The block is invoked on an arbitrary thread when task requests a new body stream.
    /// Any multipart bodies added by the block will be inserted into the request body.
    ///
    /// The associated block will only ever be invoked once even if the request is used to create
    /// multiple tasks.
    ///
    /// - Note: Using this method means that the `Content-Length` cannot be calculated for this
    ///   request. When calling APIs that need a defined `Content-Length` you must provide all
    ///   of the upload data up-front.
    ///
    /// - Parameter block: The block that provides the multipart bodies. This block is
    ///   invoked on an arbitrary background thread. The `HTTPManagerUploadMultipart`
    ///   parameter can be used to add multipart bodies to the request. This object is
    ///   only valid for the duration of the block's execution.
    ///
    /// - SeeAlso: `addMultipart(data:withName:mimeType:filename:)`,
    ///   `addMultipart(text:withName:)`.
    @objc(addMultipartBodyWithBlock:)
    public func addMultipartBody(using block: @escaping (HTTPManagerUploadMultipart) -> Void) {
        multipartBodies.append(.pending(.init(block)))
    }
    
    /// Adds a block that's invoked asynchronously to provide multipart bodies for this request.
    ///
    /// The block is invoked on an arbitrary thread when task requests a new body stream.
    /// Any multipart bodies added by the block will be inserted into the request body.
    ///
    /// The associated block will only ever be invoked once even if the request is used to create
    /// multiple tasks.
    ///
    /// - Note: Using this method means that the `Content-Length` cannot be calculated for this
    ///   request. When calling APIs that need a defined `Content-Length` you must provide all
    ///   of the upload data up-front.
    ///
    /// - Parameter block: The block that provides the multipart bodies. This block is
    ///   invoked on an arbitrary background thread. The `HTTPManagerUploadMultipart`
    ///   parameter can be used to add multipart bodies to the request. This object is
    ///   only valid for the duration of the block's execution.
    /// - Returns: `self`.
    ///
    /// - SeeAlso: `addMultipart(data:withName:mimeType:filename:)`,
    ///   `addMultipart(text:withName:)`.
    @nonobjc public func withMultipartBody(using block: @escaping (HTTPManagerUploadMultipart) -> Void) -> HTTPManagerUploadFormRequest {
        addMultipartBody(using: block)
        return self
    }
    
    /// Executes a block with `self` as the argument, and then returns `self` again.
    /// - Parameter f: A block to execute, with `self` as the argument.
    /// - Returns: `self`.
    /// This method exists to help with functional-style chaining, e.g.:
    /// ```
    /// HTTP.request(POST: "foo")
    ///     .parseAsJSON(with: { doParse($1) })
    ///     .with({ $0.userInitiated = true })
    ///     .performRequest { task, result in
    ///         // ...
    /// }
    /// ```
    @nonobjc public override func with(_ f: (HTTPManagerUploadFormRequest) throws -> Void) rethrows -> Self {
        try f(self)
        return self
    }
    
    private var multipartBodies: [MultipartBodyPart] = []
    internal override var uploadBody: UploadBody? {
        if !multipartBodies.isEmpty {
            return .multipartMixed(boundary: _boundary, parameters: parameters, bodyParts: multipartBodies)
        } else if !parameters.isEmpty {
            return .formUrlEncoded(parameters)
        } else {
            return nil
        }
    }
    
    internal override func prepareURLRequest() -> ((inout URLRequest) -> Void)? {
        if !multipartBodies.isEmpty {
            // We need to attach the boundary to the Content-Type.
            return { [boundary=_boundary] request in
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            }
        } else {
            return nil
        }
    }
    
    private lazy var _boundary: String = {
        // WebKit uses a boundary that looks like "----WebKitFormBoundary<suffix>"
        // where <suffix> is 16 random alphanumeric characters.
        // We'll just use a UUID for our randomness but we'll go with a similar prefix.
        let uuid = UUID()
        return "----PMHTTPFormBoundary\(uuid.uuidString)"
    }()
}

/// Helper class for `HTTPManagerUploadFormRequest.addMultipartBody(with:)`.
public final class HTTPManagerUploadMultipart: NSObject {
    /// Specifies a named multipart body for this request.
    ///
    /// Calling this method sets the request's overall Content-Type to
    /// `multipart/form-data`.
    ///
    /// - Bug: `name` and `filename` are assumed to be ASCII and not need any escaping.
    ///
    /// - Parameters:
    ///   - data: The data for the multipart body, such as an image or text.
    ///   - name: The name of the multipart body. This is the name the server expects.
    ///   - mimeType: The MIME content type of the multipart body. Optional.
    ///   - filename: The filename of the attachment. Optional.
    @objc(addMultipartData:withName:mimeType:filename:)
    public func addMultipart(data: Data, withName name: String, mimeType: String? = nil, filename: String? = nil) {
        multipartData.append(.init(.data(data), name: name, mimeType: mimeType, filename: filename))
    }
    
    /// Specifies a named multipart body for this request.
    ///
    /// The Content-Type of the multipart body will always be
    /// `text/plain; charset=utf-8`.
    ///
    /// Calling this method sets the request's overall Content-Type to
    /// `multipart/form-data`.
    ///
    /// - Bug: `name` is assumed to be ASCII and not need any escaping.
    ///
    /// - Parameter text: The text of the multipart body.
    /// - Parameter name: The name of the multipart body. This is the name the server expects.
    @objc(addMultipartText:withName:)
    public func addMultipart(text: String, withName name: String) {
        multipartData.append(.init(.text(text), name: name))
    }
    
    internal var multipartData: [MultipartBodyPart.Data] = []
}

// MARK: - Upload Data Request

/// An HTTP POST/PUT/PATCH request with binary data that does not yet have a parse handler.
///
/// The body of this request is a given `NSData` object. Any `parameters` are passed in the
/// query string.
public final class HTTPManagerUploadDataRequest: HTTPManagerActionRequest {
    /// The data to upload.
    public var uploadData: Data
    
    public override var contentType: String {
        get { return _contentType }
        set { _contentType = newValue }
    }
    
    /// Executes a block with `self` as the argument, and then returns `self` again.
    /// - Parameter f: A block to execute, with `self` as the argument.
    /// - Returns: `self`.
    /// This method exists to help with functional-style chaining, e.g.:
    /// ```
    /// HTTP.request(POST: "foo", data: someData)
    ///     .parseAsJSON(with: { doParse($1) })
    ///     .with({ $0.userInitiated = true })
    ///     .performRequest { task, result in
    ///         // ...
    /// }
    /// ```
    @nonobjc public override func with(_ f: (HTTPManagerUploadDataRequest) throws -> Void) rethrows -> Self {
        try f(self)
        return self
    }
    
    private var _contentType: String = ""
    
    internal override var uploadBody: UploadBody? {
        return .data(uploadData)
    }
    
    internal init(apiManager: HTTPManager, URL url: URL, method: Method, contentType: String, data: Data) {
        _contentType = contentType
        uploadData = data
        super.init(apiManager: apiManager, URL: url, method: method, parameters: [])
    }
    
    public required init(__copyOfRequest request: HTTPManagerRequest) {
        let request = unsafeDowncast(request, to: HTTPManagerUploadDataRequest.self)
        _contentType = request._contentType
        uploadData = request.uploadData
        super.init(__copyOfRequest: request)
    }
}

// MARK: - Upload JSON Request

/// An HTTP POST/PUT/PATCH for JSON data that does not yet have a parse handler.
///
/// The body of this request is a JSON blob. Any `parameters` are passed in the
/// query string.
public final class HTTPManagerUploadJSONRequest: HTTPManagerActionRequest {
    /// The JSON data to upload.
    public var uploadJSON: JSON
    
    /// The Content-Type for the request.
    /// - Returns: `"application/json"`.
    public override var contentType: String {
        return "application/json"
    }
    
    /// Executes a block with `self` as the argument, and then returns `self` again.
    /// - Parameter f: A block to execute, with `self` as the argument.
    /// - Returns: `self`.
    /// This method exists to help with functional-style chaining, e.g.:
    /// ```
    /// HTTP.request(POST: "foo", json: jsonObject)
    ///     .parseAsJSON(with: { doParse($1) })
    ///     .with({ $0.userInitiated = true })
    ///     .performRequest { task, result in
    ///         // ...
    /// }
    /// ```
    @nonobjc public override func with(_ f: (HTTPManagerUploadJSONRequest) throws -> Void) rethrows -> Self {
        try f(self)
        return self
    }
    
    internal override var uploadBody: UploadBody? {
        return .json(uploadJSON)
    }
    
    internal init(apiManager: HTTPManager, URL url: URL, method: Method, json: JSON) {
        uploadJSON = json
        super.init(apiManager: apiManager, URL: url, method: method, parameters: [])
    }
    
    public required init(__copyOfRequest request: HTTPManagerRequest) {
        let request = unsafeDowncast(request, to: HTTPManagerUploadJSONRequest.self)
        uploadJSON = request.uploadJSON
        super.init(__copyOfRequest: request)
    }
}
