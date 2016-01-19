//
//  API.swift
//  PMAPI
//
//  Created by Kevin Ballard on 12/10/15.
//  Copyright © 2015 Postmates. All rights reserved.
//

import Foundation
#if os(OSX)
    import AppKit.NSApplication
#elseif os(iOS) || os(tvOS)
    import UIKit.UIApplication
#elseif os(watchOS)
    import WatchKit.WKExtension
#endif
@exported import PMJSON

/// The default `APIManager` instance.
/// - SeeAlso: `APIManagerConfigurable`.
public let API = APIManager()

/// Manages access to a REST API.
///
/// This class is thread-safe. Requests may be created and used from any thread.
/// `APIManagerRequest`s support concurrent reading from multiple threads, but it is not safe to mutate
/// a request while concurrently accessing it from another thread. `APIManagerTask`s are safe to access
/// from any thread.
public final class APIManager: NSObject {
    public typealias Environment = APIManagerEnvironment
    
    /// The current environment. The default value is `nil`.
    ///
    /// Changes to this property affects any newly-created requests but do not
    /// affect any existing requests or any tasks that are in-progress.
    ///
    /// Changing this property also resets the authentication information if the
    /// new value differs from the old one. Setting this property to the existing
    /// value has no effect.
    ///
    /// - Important: If `environment` is `nil`, requests created with relative paths will fail,
    ///   but requests created with absolute URLs will continue to work. See `APIManagerConfigurable`
    ///   for how to configure the `APIManager` prior to first use.
    ///
    /// - SeeAlso: `resetSession()`, `APIManagerConfigurable`.
    public var environment: Environment? {
        get {
            return inner.sync({ $0.environment })
        }
        set {
            inner.asyncBarrier {
                $0.environment = newValue
                $0.defaultCredential = nil
            }
        }
    }
    
    /// The URL session configuration.
    ///
    /// Changing mutable values within the configuration object has no effect on the
    /// API manager, but you can reassign this property with the modified
    /// configuration object.
    ///
    /// Changing this property affects all newly-created tasks but does not cancel
    /// any tasks that are in-flight. You can use `resetSession()` if you need to
    /// cancel any in-flight tasks.
    ///
    /// - SeeAlso: `resetSession()`
    public var sessionConfiguration: NSURLSessionConfiguration {
        get {
            let config = inner.sync({ $0.sessionConfiguration })
            return config.copy() as! NSURLSessionConfiguration
        }
        set {
            let config = sessionConfiguration.copy() as! NSURLSessionConfiguration
            inner.asyncBarrier { [value=APIManager.defaultUserAgent] in
                $0.sessionConfiguration = config
                $0.setHeader("User-Agent", value: value, overwrite: false)
                if $0.session != nil {
                    self.resetSession($0, invalidate: false)
                }
            }
        }
    }
    
    /// The credential to use for API requests.
    ///
    /// Individual requests may override this credential with their own credential.
    ///
    /// Changes to this property affect any newly-created requests but do not affect
    /// any existing requests or any tasks that are in-progress.
    ///
    /// - Note: Only password-based credentials are supported. It is an error to assign
    /// any other type of credential.
    public var defaultCredential: NSURLCredential? {
        get {
            return inner.sync({ $0.defaultCredential })
        }
        set {
            var newValue = newValue
            if let credential = newValue where credential.user == nil || !credential.hasPassword {
                NSLog("[APIManager] Warning: Attempting to set default credential with a non-password-based credential")
                newValue = nil
            }
            inner.asyncBarrier {
                $0.defaultCredential = newValue
            }
        }
    }
    
    /// The user agent that's passed to every request.
    public var userAgent: String {
        return inner.sync({
            $0.sessionConfiguration.HTTPAdditionalHeaders?["User-Agent"] as? String
        }) ?? APIManager.defaultUserAgent
    }
    
    /// Invalidates all in-flight network operations and resets the URL session.
    ///
    /// - Note: Any tasks that have finished their network portion and are processing
    /// the results are not canceled.
    public func resetSession() {
        inner.asyncBarrier {
            if $0.session != nil {
                self.resetSession($0, invalidate: true)
            }
        }
    }
    
    private class Inner {
        var environment: Environment?
        var sessionConfiguration: NSURLSessionConfiguration = .defaultSessionConfiguration()
        var defaultCredential: NSURLCredential?

        var session: NSURLSession!
        var sessionDelegate: SessionDelegate!
        var oldSessions: [NSURLSession] = []
        
        private func setHeader(header: String, value: String, overwrite: Bool = true) {
            var headers = sessionConfiguration.HTTPAdditionalHeaders ?? [:]
            if overwrite || headers[header] == nil {
                headers[header] = value
                sessionConfiguration.HTTPAdditionalHeaders = headers
            }
        }
    }
    
    private let inner: QueueConfined<Inner> = QueueConfined(label: "APIManager internal queue", value: Inner())
    
    private override init() {
        super.init()
        inner.unsafeDirectAccess { [value=APIManager.defaultUserAgent] in
            $0.setHeader("User-Agent", value: value, overwrite: true)
        }
        let setup: APIManagerConfigurable?
        #if os(OSX)
            setup = NSApplication.sharedApplication().delegate as? APIManagerConfigurable
        #elseif os(iOS) || os(tvOS)
            setup = UIApplication.sharedApplication().delegate as? APIManagerConfigurable
        #elseif os(watchOS)
            setup = WKExtension.sharedExtension().delegate as? APIManagerConfigurable
        #endif
        setup?.configureAPIManager(self)
        inner.asyncBarrier { [value=APIManager.defaultUserAgent] in
            $0.setHeader("User-Agent", value: value, overwrite: false)
            self.resetSession($0, invalidate: false)
        }
    }
    
    deinit {
        inner.asyncBarrier { inner in
            inner.session?.finishTasksAndInvalidate()
        }
    }
    
    private func resetSession(inner: Inner, invalidate: Bool) {
        if let session = inner.session {
            if invalidate {
                session.invalidateAndCancel()
                for session in inner.oldSessions {
                    session.invalidateAndCancel()
                }
                inner.oldSessions.removeAll()
            } else {
                session.finishTasksAndInvalidate()
                inner.oldSessions.append(session)
            }
        }
        let sessionDelegate = SessionDelegate(apiManager: self)
        inner.sessionDelegate = sessionDelegate
        inner.session = NSURLSession(configuration: inner.sessionConfiguration, delegate: sessionDelegate, delegateQueue: nil)
    }
}

/// The environment for an `APIManager`.
///
/// This class does not define any default environments. You can extend this class in your application
/// to add environment definitions for convenient access. For example:
///
/// ```
/// extension APIManagerEnvironment {
///     /// The Production environment.
///     @nonobjc static let Production = APIManagerEnvironment(baseURL: NSURL(string: "https://example.com/api/v1")!)!
///     /// The Staging environment.
///     @nonobjc static let Staging = APIManagerEnvironment(baseURL: NSURL(string: "https://stage.example.com/api/v1")!)!
/// }
/// ```
///
/// You can also use `APIManagerConfigurable` to configure the initial environment on the `APIManager`.
public final class APIManagerEnvironment: NSObject {
    /// The base URL for the environment.
    public let baseURL: NSURL
    
    /// Initializes an environment with a base URL.
    /// - Parameter baseURL: The base URL to use for the environment. Must be valid according to RFC 3986.
    /// - Returns: An `APIManagerEnvironment` if the base URL is a valid absolute URL, `nil` otherwise.
    ///
    /// - Note: If `baseURL` has a non-empty `path` that does not end in a slash, the path is modified to
    ///   include a trailing slash. If `baseURL` has a query or fragment component, these components are
    ///   stripped.
    public convenience init?(baseURL: NSURL) {
        guard let comps = NSURLComponents(URL: baseURL, resolvingAgainstBaseURL: true) else {
            return nil
        }
        self.init(components: comps)
    }
    
    /// Initializes an environment with a URL string.
    /// - Parameter string: The URL string to use for the environment. Must be valid according to RFC 3986.
    /// - Returns: An `APIManagerEnvironment` if the URL string is a valid absolute URL, `nil` otherwise.
    ///
    /// - Note: If `string` represents a URL with a non-empty path that does not end in a slash, the path
    ///   is modified to include a trailing slash. If the URL has a query or fragment component, these
    //    components are stripped.
    public convenience init?(string: String) {
        guard let comps = NSURLComponents(string: string) else {
            return nil
        }
        self.init(components: comps)
    }
    
    private convenience init?(components: NSURLComponents) {
        guard components.scheme != nil else {
            // no scheme? Not an absolute URL
            return nil
        }
        // ensure the URL is terminated with a slash
        if let path = components.path where !path.isEmpty && !path.hasSuffix("/") {
            components.path = "\(path)/"
        }
        components.query = nil
        components.fragment = nil
        guard let url = components.URL else {
            return nil
        }
        self.init(sanitizedBaseURL: url)
    }
    
    // hack to workaround `return nil` from designated initializers
    // FIXME: Remove in Swift 2.2
    private init?(sanitizedBaseURL url: NSURL) {
        baseURL = url
        super.init()
    }
    
    public override var description: String {
        return "<APIManagerEnvironment: 0x\(String(unsafeBitCast(unsafeAddressOf(self), UInt.self), radix: 16)) \(baseURL.absoluteString))>"
    }
    
    public override func isEqual(object: AnyObject?) -> Bool {
        guard let other = object as? APIManagerEnvironment else { return false }
        return baseURL == other.baseURL
    }
}

/// A protocol that provides hooks for configuring the `APIManager`.
/// If the application delegate conforms to this protocol, it will be asked to configure the `APIManager`.
/// This will occur on first access to the global `API` property.
@objc public protocol APIManagerConfigurable {
    /// Invoked on first access to the global `API` property.
    ///
    /// - Note: You should not create any requests from within this method. Doing so is not
    ///   supported and will likely result in a misconfigured request.
    ///
    /// - Important: You MUST NOT access the global `API` property from within this method.
    ///   Any attempt to do so will deadlock as the property has not finished initializing.
    func configureAPIManager(api: APIManager)
}

extension APIManager {
    /// Creates a GET request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the query
    ///   string. Default is `[:]`.
    /// - Returns: An `APIManagerDataRequest`, or `nil` if the `path`  cannot be
    ///   parsed by `NSURL`.
    @nonobjc public func request(GET path: String, parameters: [String: String] = [:]) -> APIManagerDataRequest! {
        return request(GET: path, parameters: parameters.map(NSURLQueryItem.init))
    }
    /// Creates a GET request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the query
    ///   string.
    /// - Returns: An `APIManagerDataRequest`, or `nil` if the `path`  cannot be
    ///   parsed by `NSURL`.
    @nonobjc public func request(GET path: String, parameters: [NSURLQueryItem]) -> APIManagerDataRequest! {
        return constructRequest(path, f: { APIManagerDataRequest(apiManager: self, URL: $0, method: .GET, parameters: parameters) })
    }
    
    /// Creates a DELETE request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the query
    ///   string. Default is `[:]`.
    /// - Returns: An `APIManagerDeleteRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @nonobjc public func request(DELETE path: String, parameters: [String: String] = [:]) -> APIManagerDeleteRequest! {
        return request(DELETE: path, parameters: parameters.map(NSURLQueryItem.init))
    }
    /// Creates a DELETE request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the query
    ///   string.
    /// - Returns: An `APIManagerDeleteRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @nonobjc public func request(DELETE path: String, parameters: [NSURLQueryItem]) -> APIManagerDeleteRequest! {
        return constructRequest(path, f: { APIManagerDeleteRequest(apiManager: self, URL: $0, parameters: parameters) })
    }
    
    /// Creates a POST request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`. Default is `[:]`.
    /// - Returns: An `APIManagerUploadRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @nonobjc public func request(POST path: String, parameters: [String: String] = [:]) -> APIManagerUploadRequest! {
        return request(POST: path, parameters: parameters.map(NSURLQueryItem.init))
    }
    /// Creates a POST request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`.
    /// - Returns: An `APIManagerUploadRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @nonobjc public func request(POST path: String, parameters: [NSURLQueryItem]) -> APIManagerUploadRequest! {
        return constructRequest(path, f: { APIManagerUploadRequest(apiManager: self, URL: $0, parameters: parameters) })
    }
    /// Creates a POST request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter json: The JSON data to upload as the body of the request.
    /// - Returns: An `APIManagerUploadJSONRequest`, or `nil` if the `path` cannot
    ///   be parsed by `NSURL`.
    @nonobjc public func request(POST path: String, json: JSON) -> APIManagerUploadJSONRequest! {
        return constructRequest(path, f: { APIManagerUploadJSONRequest(apiManager: self, URL: $0, method: .POST, json: json) })
    }
    
    private func constructRequest<T: APIManagerRequest>(path: String, @noescape f: NSURL -> T) -> T? {
        let (baseURL, credential) = inner.sync({ inner -> (NSURL?, NSURLCredential?) in
            return (inner.environment?.baseURL, inner.defaultCredential)
        })
        guard let url = NSURL(string: path, relativeToURL: baseURL) else { return nil }
        let request = f(url)
        request.credential = credential
        return request
    }
}

// MARK: APIManagerError

/// Errors returned by APIManager
public enum APIManagerError: ErrorType, CustomStringConvertible, CustomDebugStringConvertible {
    /// An HTTP response was returned that indicates failure.
    /// - Parameter statusCode: The HTTP status code. Any code outside of 2xx or 3xx indicates failure.
    /// - Parameter body: The body of the response, if any.
    case FailedResponse(statusCode: Int, body: NSData)
    /// An HTTP response was returned that had an incorrect Content-Type header.
    /// - Note: Missing Content-Type headers are not treated as errors.
    /// - Note: Custom parse requests (using `parseWithHandler()`) do not throw this automatically, but
    ///   the parse handler may choose to throw it.
    /// - Parameter contentType: The Content-Type header of the HTTP response.
    /// - Parameter body: The body of the response, if any.
    case UnexpectedContentType(contentType: String, body: NSData)
    /// An HTTP response returned a 204 No Content where an entity was expected.
    /// This is only thrown from parse requests with methods other than DELETE.
    /// - Note: Custom parse requests (using `parseWithHandler()`) do not throw this automatically, but
    ///   the parse handler may choose to throw it.
    case UnexpectedNoContent
    /// A redirect was encountered while trying to parse a response that has redirects disabled.
    /// This can only be returned if `APIManagerRequest.shouldFollowRedirects` is set to `false`
    /// and the request is configured to parse the response.
    /// - Parameter statusCode: The 3xx HTTP status code.
    /// - Parameter location: The contents of the `"Location"` header, interpreted as a URL, or `nil` if
    ///   the header is missing or cannot be parsed.
    /// - Parameter body: The body of the response, if any.
    case UnexpectedRedirect(statusCode: Int, location: NSURL?, body: NSData)
    
    public var description: String {
        switch self {
        case let .FailedResponse(statusCode, body):
            let statusText = NSHTTPURLResponse.localizedStringForStatusCode(statusCode)
            let bodyText = describeData(body)
            return "FailedResponse(\(statusCode) \(statusText), body: \(bodyText)"
        case let .UnexpectedContentType(contentType, body):
            let bodyText = describeData(body)
            return "UnexpectedContentType(\(String(reflecting: contentType)), body: \(bodyText))"
        case .UnexpectedNoContent:
            return "UnexpectedNoContent"
        case let .UnexpectedRedirect(statusCode, location, _):
            let statusText = NSHTTPURLResponse.localizedStringForStatusCode(statusCode)
            return "UnexpectedRedirect(\(statusCode) \(statusText), location: \(location as ImplicitlyUnwrappedOptional))"
        }
    }
    
    public var debugDescription: String {
        switch self {
        case let .FailedResponse(statusCode, body):
            let statusText = NSHTTPURLResponse.localizedStringForStatusCode(statusCode)
            let bodyText = describeData(body)
            return "APIManagerError.FailedResponse(statusCode: \(statusCode) \(statusText), body: \(bodyText))"
        case let .UnexpectedContentType(contentType, body):
            let bodyText = describeData(body)
            return "APIManagerError.UnexpectedContentType(contentType: \(String(reflecting: contentType)), body: \(bodyText))"
        case .UnexpectedNoContent:
            return "APIManagerError.UnexpectedNoContent"
        case let .UnexpectedRedirect(statusCode, location, body):
            let statusText = NSHTTPURLResponse.localizedStringForStatusCode(statusCode)
            let bodyText = describeData(body)
            return "APIManagerError.UnexpectedRedirect(statusCode: \(statusCode) \(statusText), location: \(location as ImplicitlyUnwrappedOptional), body: \(bodyText))"
        }
    }
}

private func describeData(data: NSData) -> String {
    // we don't have access to the response so we can't see if it included a MIME type.
    // just assume utf-8 instead. If it's not utf-8, it's unlikely to decode so that's fine.
    if data.length > 0, let str = String(data: data, encoding: NSUTF8StringEncoding) {
        return String(reflecting: str)
    } else {
        return String(data)
    }
}

// MARK: - Private

extension APIManager {
    // MARK: Default User-Agent
    private static let defaultUserAgent: String = {
        let bundle = NSBundle.mainBundle()
        
        func appName() -> String {
            if let name = bundle.objectForInfoDictionaryKey("User Agent App Name") as? String {
                return name
            } else if let name = bundle.objectForInfoDictionaryKey("CFBundleDisplayName") as? String {
                return name
            } else if let name = bundle.objectForInfoDictionaryKey(kCFBundleNameKey as String) as? String {
                return name
            } else {
                return "(null)"
            }
        }
        
        func appVersion() -> String {
            let marketingVersionNumber = bundle.objectForInfoDictionaryKey("CFBundleShortVersionString") as? String
            let buildVersionNumber = bundle.objectForInfoDictionaryKey(kCFBundleVersionKey as String) as? String
            if let marketingVersionNumber = marketingVersionNumber, buildVersionNumber = buildVersionNumber where marketingVersionNumber != buildVersionNumber {
                return "\(marketingVersionNumber) rv:\(buildVersionNumber)"
            } else {
                return marketingVersionNumber ?? buildVersionNumber ?? "(null)"
            }
        }
        
        func deviceInfo() -> (model: String, systemName: String) {
            #if os(OSX)
                return ("Macintosh", "Mac OS X")
            #elseif os(iOS) || os(tvOS)
                let device = UIDevice.currentDevice()
                return (device.model, device.systemName)
            #elseif os(watchOS)
                let device = WKInterfaceDevice.currentDevice()
                return (device.model, device.systemName)
            #endif
        }
        
        func systemVersion() -> String {
            let version = NSProcessInfo.processInfo().operatingSystemVersion
            var s = "\(version.majorVersion).\(version.minorVersion)"
            if version.patchVersion != 0 {
                s += ".\(version.patchVersion)"
            }
            return s
        }
        
        let localeIdentifier = NSLocale.currentLocale().localeIdentifier
        
        let (deviceModel, systemName) = deviceInfo()
        // Format is "My Application 1.0 (device_model:iPhone; system_os:iPhone OS system_version:9.2; en_US)"
        return "\(appName()) \(appVersion()) (device_model:\(deviceModel); system_os:\(systemName); system_version:\(systemVersion()); \(localeIdentifier))"
    }()
}

// MARK: -

private class SessionDelegate: NSObject {
    weak var apiManager: APIManager?
    
    var tasks: [TaskIdentifier: TaskInfo] = [:]
    
    init(apiManager: APIManager) {
        self.apiManager = apiManager
        super.init()
    }
    
    /// A task identifier for an `NSURLSessionTask`.
    typealias TaskIdentifier = Int
    
    struct TaskInfo {
        let task: APIManagerTask
        let uploadBody: UploadBody?
        let processor: (APIManagerTask, APIManagerTaskResult<NSData>) -> Void
        var data: NSMutableData? = nil
        
        init(task: APIManagerTask, uploadBody: UploadBody? = nil, processor: (APIManagerTask, APIManagerTaskResult<NSData>) -> Void) {
            self.task = task
            self.uploadBody = uploadBody
            self.processor = processor
        }
    }
}

extension APIManager {
    /// Creates and returns an `APIManagerTask`.
    /// - Parameter request: The request to create the task from.
    /// - Parameter uploadBody: The data to upload, if any.
    /// - Parameter processor: The processing block. This block must transition the task to the `.Completed` state
    ///   and must handle cancellation correctly.
    /// - Returns: An `APIManagerTask`.
    internal func createNetworkTaskWithRequest(request: APIManagerRequest, uploadBody: UploadBody?, processor: (APIManagerTask, APIManagerTaskResult<NSData>) -> Void) -> APIManagerTask {
        let urlRequest = request._preparedURLRequest
        var uploadBody = uploadBody
        if case .FormUrlEncoded(let queryItems)? = uploadBody {
            uploadBody = .Data(UploadBody.dataRepresentationForQueryItems(queryItems))
        }
        uploadBody?.evaluatePending()
        let apiTask = inner.sync { inner -> APIManagerTask in
            let networkTask: NSURLSessionTask
            if case .Data(let data)? = uploadBody {
                uploadBody = nil
                networkTask = inner.session.uploadTaskWithRequest(urlRequest, fromData: data)
            } else if uploadBody != nil {
                networkTask = inner.session.uploadTaskWithStreamedRequest(urlRequest)
            } else {
                networkTask = inner.session.dataTaskWithRequest(urlRequest)
            }
            let apiTask = APIManagerTask(networkTask: networkTask, request: request)
            let taskInfo = SessionDelegate.TaskInfo(task: apiTask, uploadBody: uploadBody, processor: processor)
            inner.session.delegateQueue.addOperationWithBlock { [sessionDelegate=inner.sessionDelegate] in
                assert(sessionDelegate.tasks[networkTask.taskIdentifier] == nil, "internal APIManager error: tasks contains unknown taskInfo")
                sessionDelegate.tasks[networkTask.taskIdentifier] = taskInfo
            }
            #if os(iOS)
                if apiTask.trackingNetworkActivity {
                    NetworkActivityManager.shared.incrementCounter()
                }
            #endif
            return apiTask
        }
        if apiTask.userInitiated {
            apiTask.networkTask.priority = NSURLSessionTaskPriorityHigh
        }
        apiTask.networkTask.resume()
        return apiTask
    }
}

extension SessionDelegate: NSURLSessionDataDelegate {
    @objc func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
        apiManager?.inner.asyncBarrier { inner in
            if let idx = inner.oldSessions.indexOf({ $0 === self }) {
                inner.oldSessions.removeAtIndex(idx)
            }
        }
        #if os(iOS)
            for taskInfo in tasks.values where taskInfo.task.trackingNetworkActivity {
                NetworkActivityManager.shared.decrementCounter()
            }
            tasks.removeAll()
        #endif
    }
    
    @objc func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
        guard var taskInfo = tasks[dataTask.taskIdentifier] else {
            completionHandler(.Cancel)
            return
        }
        assert(taskInfo.task.networkTask === dataTask, "internal APIManager error: taskInfo out of sync")
        if taskInfo.data != nil {
            taskInfo.data = nil
            tasks[dataTask.taskIdentifier] = taskInfo
        }
        completionHandler(.Allow)
    }
    
    @objc func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
        guard var taskInfo = tasks[dataTask.taskIdentifier] else { return }
        assert(taskInfo.task.networkTask === dataTask, "internal APIManager error: taskInfo out of sync")
        let taskData: NSMutableData
        if let data = taskInfo.data {
            taskData = data
        } else {
            let length = dataTask.countOfBytesExpectedToReceive
            if length <= 0 { // includes NSURLSessionTransferSizeUnknown
                taskData = NSMutableData()
            } else {
                // cap pre-allocation at 10MB
                taskData = NSMutableData(capacity: Int(min(length, 10*1024*1024))) ?? NSMutableData()
            }
            taskInfo.data = taskData
            tasks[dataTask.taskIdentifier] = taskInfo
        }
        taskData.appendData(data)
    }
    
    @objc func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        // NB: If we canceled during the networking portion, we delay reporting the
        // cancellation until the networking portion is done. This should show up here
        // as either an NSURLErrorCancelled error, or simply the inability to transition
        // to processing due to the state being cancelled (which may happen if the task
        // cancellation occurs concurrently with the networking finishing).
        
        guard let taskInfo = tasks.removeValueForKey(task.taskIdentifier) else { return }
        let apiTask = taskInfo.task
        assert(apiTask.networkTask === task, "internal APIManager error: taskInfo out of sync")
        let processor = taskInfo.processor
        
        #if os(iOS)
            if apiTask.trackingNetworkActivity {
                NetworkActivityManager.shared.decrementCounter()
            }
        #endif
        
        let queue = dispatch_get_global_queue(taskInfo.task.userInitiated ? QOS_CLASS_USER_INITIATED : QOS_CLASS_UTILITY, 0)
        if let error = error where error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            // Either we canceled during the networking portion, or someone called
            // cancel() on the NSURLSessionTask directly. In the latter case, treat it
            // as a cancellation anyway.
            let result = taskInfo.task.transitionStateTo(.Canceled)
            assert(result.ok, "internal APIManager error: tried to cancel task that's already completed")
            dispatch_async(queue) {
                processor(apiTask, .Canceled)
            }
        } else {
            let result = apiTask.transitionStateTo(.Processing)
            if result.ok {
                assert(result.oldState == .Running, "internal APIManager error: tried to process task that's already processing")
                dispatch_async(queue) { [data=taskInfo.data] in
                    if let error = error {
                        processor(apiTask, .Error(task.response, error))
                    } else if let response = task.response {
                        processor(apiTask, .Success(response, data ?? NSData()))
                    } else {
                        // this should be unreachable
                        let userInfo = [NSLocalizedDescriptionKey: "internal error: task response was nil with no error"]
                        processor(apiTask, .Error(nil, NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: userInfo)))
                    }
                }
            } else {
                assert(result.oldState == .Canceled, "internal APIManager error: tried to process task that's already completed")
                // We must have canceled concurrently with the networking portion finishing
                dispatch_async(queue) {
                    processor(apiTask, .Canceled)
                }
            }
        }
    }
    
    @objc func URLSession(session: NSURLSession, task: NSURLSessionTask, willPerformHTTPRedirection response: NSHTTPURLResponse, newRequest request: NSURLRequest, completionHandler: (NSURLRequest?) -> Void) {
        guard let taskInfo = tasks[task.taskIdentifier] else {
            completionHandler(request)
            return
        }
        assert(taskInfo.task.networkTask === task, "internal APIManager error: taskInfo out of sync")
        if taskInfo.task.followRedirects {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
    
    @objc func URLSession(session: NSURLSession, task: NSURLSessionTask, needNewBodyStream completionHandler: (NSInputStream?) -> Void) {
        // TODO: implement me
        completionHandler(nil)
    }
}
