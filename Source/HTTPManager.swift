//
//  HTTPManager.swift
//  PostmatesNetworking
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
@_exported import PMJSON

/// The default `HTTPManager` instance.
/// - SeeAlso: `HTTPManagerConfigurable`.
public let HTTP = HTTPManager(shared: true)

/// Manages access to a REST API.
///
/// This class is thread-safe. Requests may be created and used from any thread.
/// `HTTPManagerRequest`s support concurrent reading from multiple threads, but it is not safe to mutate
/// a request while concurrently accessing it from another thread. `HTTPManagerTask`s are safe to access
/// from any thread.
public final class HTTPManager: NSObject {
    public typealias Environment = HTTPManagerEnvironment
    
    /// The current environment. The default value is `nil`.
    ///
    /// Changes to this property affects any newly-created requests but do not
    /// affect any existing requests or any tasks that are in-progress.
    ///
    /// Changing this property also resets the default credential if the
    /// new value differs from the old one. Setting this property to the existing
    /// value has no effect.
    ///
    /// - Important: If `environment` is `nil`, requests created with relative paths will fail,
    ///   but requests created with absolute URLs will continue to work. See `HTTPManagerConfigurable`
    ///   for how to configure the shared `HTTPManager` prior to first use.
    ///
    /// - SeeAlso: `resetSession()`, `HTTPManagerConfigurable`, `defaultCredential`.
    public var environment: Environment? {
        get {
            return inner.sync({ $0.environment })
        }
        set {
            inner.asyncBarrier {
                if $0.environment != newValue {
                    $0.environment = newValue
                    $0.defaultCredential = nil
                }
            }
        }
    }
    
    /// The URL session configuration.
    ///
    /// Changing mutable values within the configuration object has no effect on the
    /// HTTP manager, but you can reassign this property with the modified
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
            return unsafeDowncast(config.copy())
        }
        set {
            let config: NSURLSessionConfiguration = unsafeDowncast(newValue.copy())
            inner.asyncBarrier { [value=HTTPManager.defaultUserAgent] in
                $0.sessionConfiguration = config
                $0.setHeader("User-Agent", value: value, overwrite: false)
                if $0.session != nil {
                    self.resetSession($0, invalidate: false)
                }
            }
        }
    }
    
    /// The credential to use for HTTP requests. The default value is `nil`.
    ///
    /// Individual requests may override this credential with their own credential.
    ///
    /// Changes to this property affect any newly-created requests but do not affect any existing
    /// requests or any tasks that are in-progress.
    ///
    /// - Note: This credential is only used for HTTP requests that are located within the current
    ///   environment's base URL. If a request is created with an absolute path or absolute URL, and
    ///   the resulting URL does not represent a resource found within the environment's base URL,
    ///   the request will not be assigned the default credential.
    ///
    /// - Important: Only password-based credentials are supported. It is an error to assign any
    ///   other type of credential.
    ///
    /// - SeeAlso: `environment`.
    public var defaultCredential: NSURLCredential? {
        get {
            return inner.sync({ $0.defaultCredential })
        }
        set {
            var newValue = newValue
            if let credential = newValue where credential.user == nil || !credential.hasPassword {
                NSLog("[HTTPManager] Warning: Attempting to set default credential with a non-password-based credential")
                newValue = nil
            }
            inner.asyncBarrier {
                $0.defaultCredential = newValue
            }
        }
    }
    
    /// The default retry behavior to use for requests. The default value is `nil`.
    ///
    /// Individual requests may override this behavior with their own behavior.
    ///
    /// Changes to this property affect any newly-created requests but do not affect
    /// any existing requests or any tasks that are in-progress.
    public var defaultRetryBehavior: HTTPManagerRetryBehavior? {
        get {
            return inner.sync({ $0.defaultRetryBehavior })
        }
        set {
            inner.asyncBarrier {
                $0.defaultRetryBehavior = newValue
            }
        }
    }
    
    /// The user agent that's passed to every request.
    public var userAgent: String {
        return inner.sync({
            $0.sessionConfiguration.HTTPAdditionalHeaders?["User-Agent"] as? String
        }) ?? HTTPManager.defaultUserAgent
    }
    
    /// An `HTTPMockManager` that can be used to define mocks for this `HTTPManager`.
    public let mockManager = HTTPMockManager()
    
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
    
    #if os(iOS)
    /// Tracks a given `NSURLSessionTask` for the network activity indicator.
    /// Only use this if you create a task yourself, any tasks created by
    /// `HTTPManager` are automatically tracked (unless disabled by the request).
    public static func trackNetworkActivityForTask(task: NSURLSessionTask) {
        NetworkActivityManager.shared.trackTask(task)
    }
    #endif
    
    /// Creates and returns a new `HTTPManager`.
    ///
    /// The returned `HTTPManager` needs its `environment` set, but is otherwise ready
    /// for use.
    ///
    /// - Important: Unlike the global `HTTP` property, calling this initializer does
    ///   not go through `HTTPManagerConfigurable`. The calling code must configure
    ///   the returned `HTTPManager` instance as appropriate.
    ///
    /// - SeeAlso: `HTTP`.
    public override convenience init() {
        self.init(shared: false)
    }
    
    private class Inner {
        var environment: Environment?
        var sessionConfiguration: NSURLSessionConfiguration = .defaultSessionConfiguration()
        var defaultCredential: NSURLCredential?
        var defaultRetryBehavior: HTTPManagerRetryBehavior?

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
    
    private let inner: QueueConfined<Inner> = QueueConfined(label: "HTTPManager internal queue", value: Inner())
    
    private init(shared: Bool) {
        super.init()
        inner.unsafeDirectAccess { [value=HTTPManager.defaultUserAgent] in
            $0.setHeader("User-Agent", value: value, overwrite: true)
        }
        if shared {
            let setup: HTTPManagerConfigurable?
            #if os(OSX)
                setup = NSApplication.sharedApplication().delegate as? HTTPManagerConfigurable
            #elseif os(iOS) || os(tvOS)
                setup = UIApplication.sharedApplication().delegate as? HTTPManagerConfigurable
            #elseif os(watchOS)
                setup = WKExtension.sharedExtension().delegate as? HTTPManagerConfigurable
            #endif
            setup?.configureHTTPManager(self)
        }
        inner.asyncBarrier { [value=HTTPManager.defaultUserAgent] in
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
        // Insert HTTPMockURLProtocol into the protocol classes list.
        let config: NSURLSessionConfiguration = unsafeDowncast(inner.sessionConfiguration.copy())
        var classes = config.protocolClasses ?? []
        classes.insert(HTTPMockURLProtocol.self, atIndex: 0)
        config.protocolClasses = classes
        inner.session = NSURLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }
}

/// The environment for an `HTTPManager`.
///
/// This class does not define any default environments. You can extend this class in your application
/// to add environment definitions for convenient access. For example:
///
/// ```
/// extension HTTPManagerEnvironment {
///     /// The Production environment.
///     @nonobjc static let Production = HTTPManagerEnvironment(baseURL: NSURL(string: "https://example.com/api/v1")!)!
///     /// The Staging environment.
///     @nonobjc static let Staging = HTTPManagerEnvironment(baseURL: NSURL(string: "https://stage.example.com/api/v1")!)!
/// }
/// ```
///
/// You can also use `HTTPManagerConfigurable` to configure the initial environment on the shared `HTTPManager`.
public final class HTTPManagerEnvironment: NSObject {
    /// The base URL for the environment.
    /// - Invariant: The URL is an absolute URL that is valid according to RFC 3986, the URL's path
    ///   is either empty or has a trailing slash, and the URL has no query or fragment component.
    public let baseURL: NSURL
    
    /// Initializes an environment with a base URL.
    /// - Parameter baseURL: The base URL to use for the environment. Must be a valid absolute URL
    ///   according to RFC 3986.
    /// - Returns: An `HTTPManagerEnvironment` if the base URL is a valid absolute URL, `nil` otherwise.
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
    /// - Parameter string: The URL string to use for the environment. Must be a valid absolute URL
    ///   according to RFC 3986.
    /// - Returns: An `HTTPManagerEnvironment` if the URL string is a valid absolute URL, `nil` otherwise.
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
    
    /// Returns `true` if `url` is prefixed by `self.baseURL`, `false` otherwise.
    ///
    /// - Parameter url: The URL to compare against. Must be a valid absolute URL according to RFC 3986,
    ///   otherwise this method always returns `false`.
    ///
    /// For one URL to prefix another, both URLs must have the same scheme, authority info,
    /// host, and port, and the first URL's path must be a prefix of the second URL's path.
    /// Scheme and host are compared case-insensitively, and if the port is nil, an appropriate
    /// default value is assumed for the HTTP and HTTPS schemes.
    public func isPrefixOf(url: NSURL) -> Bool {
        guard let urlComponents = NSURLComponents(URL: url, resolvingAgainstBaseURL: true) else { return false }
        func getPort(components: NSURLComponents) -> Int? {
            if let port = components.port { return port as Int }
            switch components.scheme {
            case CaseInsensitiveASCIIString("http")?: return 80
            case CaseInsensitiveASCIIString("https")?: return 443
            default: return nil
            }
        }
        func caseInsensitiveCompare(a: String?, _ b: String?) -> Bool {
            return a.map({CaseInsensitiveASCIIString($0)}) == b.map({CaseInsensitiveASCIIString($0)})
        }
        guard caseInsensitiveCompare(baseURLComponents.scheme, urlComponents.scheme)
            && baseURLComponents.percentEncodedUser == urlComponents.percentEncodedUser
            && baseURLComponents.percentEncodedPassword == urlComponents.percentEncodedPassword
            && caseInsensitiveCompare(baseURLComponents.percentEncodedHost, urlComponents.percentEncodedHost)
            && getPort(baseURLComponents) == getPort(urlComponents)
            else { return false }
        switch (baseURLComponents.percentEncodedPath, urlComponents.percentEncodedPath) {
        case (""?, _), (nil, _): return true
        case (_?, nil): return false
        case let (a?, b?): return b.hasPrefix(a)
        }
    }
    
    private init?(components: NSURLComponents) {
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
        baseURL = url
        baseURLComponents = components
        super.init()
    }
    
    /// `NSURLComponents` object equivalent to `baseURL`.
    /// This property is `private` because the returned object is mutable but should not be mutated.
    /// It only exists to avoid re-parsing the URL every time its components is accessed.
    private let baseURLComponents: NSURLComponents
    
    public override var description: String {
        return "<HTTPManagerEnvironment: 0x\(String(unsafeBitCast(unsafeAddressOf(self), UInt.self), radix: 16)) \(baseURL.absoluteString))>"
    }
    
    public override func isEqual(object: AnyObject?) -> Bool {
        guard let other = object as? HTTPManagerEnvironment else { return false }
        return baseURL == other.baseURL
    }
    
    public override var hash: Int {
        return baseURL.hash &+ 1
    }
}

/// A protocol that provides hooks for configuring the shared `HTTPManager`.
/// If the application delegate conforms to this protocol, it will be asked to configure the shared `HTTPManager`.
/// This will occur on first access to the global `HTTP` property.
@objc public protocol HTTPManagerConfigurable {
    /// Invoked on first access to the global `HTTP` property.
    ///
    /// - Note: You should not create any requests from within this method. Doing so is not
    ///   supported and will likely result in a misconfigured request.
    ///
    /// - Important: You MUST NOT access the global `HTTP` property from within this method.
    ///   Any attempt to do so will deadlock as the property has not finished initializing.
    func configureHTTPManager(httpManager: HTTPManager)
}

extension HTTPManager {
    /// Creates a GET request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the query
    ///   string. Default is `[:]`.
    /// - Returns: An `HTTPManagerDataRequest`, or `nil` if the `path`  cannot be
    ///   parsed by `NSURL`.
    @objc(requestForGET:parameters:)
    public func request(GET path: String, parameters: [String: AnyObject] = [:]) -> HTTPManagerDataRequest! {
        return request(GET: path, parameters: parameters.map({ NSURLQueryItem(name: $0, value: String($1)) }))
    }
    /// Creates a GET request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the query
    ///   string.
    /// - Returns: An `HTTPManagerDataRequest`, or `nil` if the `path`  cannot be
    ///   parsed by `NSURL`.
    @objc(requestForGET:queryItems:)
    public func request(GET path: String, parameters: [NSURLQueryItem]) -> HTTPManagerDataRequest! {
        return constructRequest(path, f: { HTTPManagerDataRequest(apiManager: self, URL: $0, method: .GET, parameters: parameters) })
    }
    
    /// Creates a DELETE request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the query
    ///   string. Default is `[:]`.
    /// - Returns: An `HTTPManagerActionRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForDELETE:parameters:)
    public func request(DELETE path: String, parameters: [String: AnyObject] = [:]) -> HTTPManagerActionRequest! {
        return request(DELETE: path, parameters: parameters.map({ NSURLQueryItem(name: $0, value: String($1)) }))
    }
    /// Creates a DELETE request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the query
    ///   string.
    /// - Returns: An `HTTPManagerActionRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForDELETE:queryItems:)
    public func request(DELETE path: String, parameters: [NSURLQueryItem]) -> HTTPManagerActionRequest! {
        return constructRequest(path, f: { HTTPManagerActionRequest(apiManager: self, URL: $0, method: .DELETE, parameters: parameters) })
    }
    
    /// Creates a POST request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`. Default is `[:]`.
    /// - Returns: An `HTTPManagerUploadFormRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForPOST:parameters:)
    public func request(POST path: String, parameters: [String: AnyObject] = [:]) -> HTTPManagerUploadFormRequest! {
        return request(POST: path, parameters: parameters.map({ NSURLQueryItem(name: $0, value: String($1)) }))
    }
    /// Creates a POST request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`.
    /// - Returns: An `HTTPManagerUploadFormRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForPOST:queryItems:)
    public func request(POST path: String, parameters: [NSURLQueryItem]) -> HTTPManagerUploadFormRequest! {
        return constructRequest(path, f: { HTTPManagerUploadFormRequest(apiManager: self, URL: $0, method: .POST, parameters: parameters) })
    }
    /// Creates a POST request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter json: The JSON data to upload as the body of the request.
    /// - Returns: An `HTTPManagerUploadJSONRequest`, or `nil` if the `path` cannot
    ///   be parsed by `NSURL`.
    @nonobjc public func request(POST path: String, json: JSON) -> HTTPManagerUploadJSONRequest! {
        return constructRequest(path, f: { HTTPManagerUploadJSONRequest(apiManager: self, URL: $0, method: .POST, json: json) })
    }
    
    /// Creates a PUT request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`. Default is `[:]`.
    /// - Returns: An `HTTPManagerUploadFormRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForPUT:parameters:)
    public func request(PUT path: String, parameters: [String: AnyObject] = [:]) -> HTTPManagerUploadFormRequest! {
        return request(PUT: path, parameters: parameters.map({ NSURLQueryItem(name: $0, value: String($1)) }))
    }
    /// Creates a PUT request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`.
    /// - Returns: An `HTTPManagerUploadFormRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForPUT:queryItems:)
    public func request(PUT path: String, parameters: [NSURLQueryItem]) -> HTTPManagerUploadFormRequest! {
        return constructRequest(path, f: { HTTPManagerUploadFormRequest(apiManager: self, URL: $0, method: .PUT, parameters: parameters) })
    }
    /// Creates a PUT request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter json: The JSON data to upload as the body of the request.
    /// - Returns: An `HTTPManagerUploadJSONRequest`, or `nil` if the `path` cannot
    ///   be parsed by `NSURL`.
    @nonobjc public func request(PUT path: String, json: JSON) -> HTTPManagerUploadJSONRequest! {
        return constructRequest(path, f: { HTTPManagerUploadJSONRequest(apiManager: self, URL: $0, method: .PUT, json: json) })
    }
    
    /// Creates a PATCH request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`. Default is `[:]`.
    /// - Returns: An `HTTPManagerUploadFormRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForPATCH:parameters:)
    public func request(PATCH path: String, parameters: [String: AnyObject] = [:]) -> HTTPManagerUploadFormRequest! {
        return request(PATCH: path, parameters: parameters.map({ NSURLQueryItem(name: $0, value: String($1)) }))
    }
    /// Creates a PATCH request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`.
    /// - Returns: An `HTTPManagerUploadFormRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForPATCH:queryItems:)
    public func request(PATCH path: String, parameters: [NSURLQueryItem]) -> HTTPManagerUploadFormRequest! {
        return constructRequest(path, f: { HTTPManagerUploadFormRequest(apiManager: self, URL: $0, method: .PATCH, parameters: parameters) })
    }
    /// Creates a PATCH request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter json: The JSON data to upload as the body of the request.
    /// - Returns: An `HTTPManagerUploadJSONRequest`, or `nil` if the `path` cannot
    ///   be parsed by `NSURL`.
    @nonobjc public func request(PATCH path: String, json: JSON) -> HTTPManagerUploadJSONRequest! {
        return constructRequest(path, f: { HTTPManagerUploadJSONRequest(apiManager: self, URL: $0, method: .PATCH, json: json) })
    }
    
    private func constructRequest<T: HTTPManagerRequest>(path: String, @noescape f: NSURL -> T) -> T? {
        let (environment, credential, defaultRetryBehavior) = inner.sync({ inner -> (Environment?, NSURLCredential?, HTTPManagerRetryBehavior?) in
            return (inner.environment, inner.defaultCredential, inner.defaultRetryBehavior)
        })
        guard let url = NSURL(string: path, relativeToURL: environment?.baseURL) else { return nil }
        let request = f(url)
        if let credential = credential, environment = environment {
            // make sure the requested entity is within the space defined by baseURL
            if environment.isPrefixOf(url) {
                request.credential = credential
            }
        }
        request.retryBehavior = defaultRetryBehavior
        return request
    }
}

// MARK: HTTPManagerError

/// Errors returned by HTTPManager
public enum HTTPManagerError: ErrorType, CustomStringConvertible, CustomDebugStringConvertible {
    /// An HTTP response was returned that indicates failure.
    /// - Parameter statusCode: The HTTP status code. Any code outside of 2xx or 3xx indicates failure.
    /// - Parameter response: The `NSHTTPURLResponse` object.
    /// - Parameter body: The body of the response, if any.
    /// - Parameter bodyJson: If the response `Content-Type` is `application/json`, contains the results
    ///   of decoding the body as JSON. If the decode fails, or the `Content-Type` is not `application/json`,
    ///   `bodyJson` is `nil`.
    /// - Note: 401 Unauthorized errors are represented by `HTTPManagerError.Unauthorized` instead of
    ///   `FailedResponse`.
    case FailedResponse(statusCode: Int, response: NSHTTPURLResponse, body: NSData, bodyJson: JSON?)
    /// A 401 Unauthorized HTTP response was returned.
    /// - Parameter credential: The `NSURLCredential` that was used in the request, if any.
    /// - Parameter response: The `NSHTTPURLResponse` object.
    /// - Parameter body: The body of the response, if any.
    /// - Parameter bodyJson: If the response `Content-Type` is `application/json`, contains the results
    ///   of decoding the body as JSON. If the decode fails, or the `Content-Type` is not `application/json`,
    ///   `bodyJson` is `nil`.
    case Unauthorized(credential: NSURLCredential?, response: NSHTTPURLResponse, body: NSData, bodyJson: JSON?)
    /// An HTTP response was returned that had an incorrect Content-Type header.
    /// - Note: Missing Content-Type headers are not treated as errors.
    /// - Note: Custom parse requests (using `parseWithHandler()`) do not throw this automatically, but
    ///   the parse handler may choose to throw it.
    /// - Parameter contentType: The Content-Type header of the HTTP response.
    /// - Parameter response: The `NSHTTPURLResponse` object.
    /// - Parameter body: The body of the response, if any.
    case UnexpectedContentType(contentType: String, response: NSHTTPURLResponse, body: NSData)
    /// An HTTP response returned a 204 No Content where an entity was expected.
    /// This is only thrown automatically from parse requests with a GET or HEAD method.
    /// - Note: Custom parse requests (using `parseWithHandler(_:)`) do not throw this automatically, but
    ///   the parse handler may choose to throw it.
    /// - Parameter response: The `NSHTTPURLResponse` object.
    case UnexpectedNoContent(response: NSHTTPURLResponse)
    /// A redirect was encountered while trying to parse a response that has redirects disabled.
    /// This can only be returned if `HTTPManagerRequest.shouldFollowRedirects` is set to `false`
    /// and the request is configured to parse the response.
    /// - Parameter statusCode: The 3xx HTTP status code.
    /// - Parameter location: The contents of the `"Location"` header, interpreted as a URL, or `nil` if
    /// - Parameter response: The `NSHTTPURLResponse` object.
    ///   the header is missing or cannot be parsed.
    /// - Parameter body: The body of the response, if any.
    case UnexpectedRedirect(statusCode: Int, location: NSURL?, response: NSHTTPURLResponse, body: NSData)
    
    public var description: String {
        switch self {
        case let .FailedResponse(statusCode, response, body, json):
            let statusText = NSHTTPURLResponse.localizedStringForStatusCode(statusCode)
            var s = "FailedResponse(\(statusCode) \(statusText), \(response.URL?.relativeString ?? "nil"), "
            if let json = json {
                s += "bodyJson: \(json))"
            } else {
                s += "body: \(describeData(body)))"
            }
            return s
        case let .Unauthorized(credential, response, body, json):
            var s = "Unauthorized("
            if let credential = credential {
                if let user = credential.user {
                    s += "user: \(String(reflecting: user))"
                    if !credential.hasPassword {
                        s += " (no password)"
                    }
                } else {
                    s += "invalid credential"
                }
            } else {
                s += "no credential"
            }
            s += ", \(response.URL?.relativeString ?? "nil"), "
            if let json = json {
                s += "bodyJson: \(json))"
            } else {
                s += "body: \(describeData(body)))"
            }
            return s
        case let .UnexpectedContentType(contentType, response, body):
            return "UnexpectedContentType(\(String(reflecting: contentType)), \(response.URL?.relativeString ?? "nil"), body: \(describeData(body)))"
        case let .UnexpectedNoContent(response):
            return "UnexpectedNoContent(\(response.URL?.relativeString ?? "nil"))"
        case let .UnexpectedRedirect(statusCode, location, response, _):
            let statusText = NSHTTPURLResponse.localizedStringForStatusCode(statusCode)
            return "UnexpectedRedirect(\(statusCode) \(statusText), \(response.URL?.relativeString ?? "nil"), location: \(location as ImplicitlyUnwrappedOptional))"
        }
    }
    
    public var debugDescription: String {
        switch self {
        case let .FailedResponse(statusCode, response, body, json):
            let statusText = NSHTTPURLResponse.localizedStringForStatusCode(statusCode)
            return "HTTPManagerError.FailedResponse(statusCode: \(statusCode) \(statusText), "
                + "response: \(response), "
                + "body: \(describeData(body)), "
                + "bodyJson: \(json.map({String(reflecting: $0)}) ?? "nil"))"
        case let .Unauthorized(credential, response, body, json):
            return "HTTPManagerError.Unauthorized(credential: \(credential.map({String(reflecting: $0)}) ?? "nil"), "
                + "response: \(response), "
                + "body: \(describeData(body)), "
                + "bodyJson: \(json.map({String(reflecting: $0)}) ?? "nil"))"
        case let .UnexpectedContentType(contentType, response, body):
            return "HTTPManagerError.UnexpectedContentType(contentType: \(String(reflecting: contentType)), "
                + "response: \(response), "
                + "body: \(describeData(body)))"
        case let .UnexpectedNoContent(response):
            return "HTTPManagerError.UnexpectedNoContent(response: \(response))"
        case let .UnexpectedRedirect(statusCode, location, response, body):
            let statusText = NSHTTPURLResponse.localizedStringForStatusCode(statusCode)
            let bodyText = describeData(body)
            return "HTTPManagerError.UnexpectedRedirect(statusCode: \(statusCode) \(statusText), "
                + "location: \(location as ImplicitlyUnwrappedOptional), "
                + "response: \(response), "
                + "body: \(bodyText))"
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

/// Represents the retry behavior for an HTTP request.
///
/// Retry behaviors provide a mechanism for requests to automatically retry upon failure before
/// notifying the caller about the failure. Any arbitrary retry behavior can be implemented, but
/// convenience methods are provided for some of the more common behaviors.
///
/// Unless otherwise specified, retry behaviors are only evaluated for idempotent requests.
/// This includes GET, HEAD, PUT, DELETE, OPTIONS, and TRACE.
///
/// - Note: Retry behaviors are evaluated on an arbitrary dispatch queue.
public final class HTTPManagerRetryBehavior: NSObject {
    /// Returns a retry behavior that evaluates a block.
    ///
    /// The returned retry behavior will be evaluated only for idempotent requests. If the request involves
    /// redirections, the original request will be evaluated for idempotence (and in the event of a retry,
    /// the original request is the one that is retried).
    ///
    /// - Note: The block will be executed on an arbitrary dispatch queue.
    ///
    /// The block takes the following parameters:
    ///
    /// - Parameter task: The `HTTPManagerTask` under consideration. You can use this task
    ///   to retrieve the last `networkTask` and its `originalRequest` and `response`.
    /// - Parameter error: The error that occurred. This may be an error from the networking portion
    ///   or it may be an error from the processing stage.
    /// - Parameter attempt: The number of retries so far. The first retry block is attempt `0`, the second is
    ///   attempt `1`, etc.
    /// - Parameter callback: A block that must be invoked to determine whether a retry should be done.
    ///   Passing `true` means the request should be automatically retried, `false` means no retry.
    ///   This block may be executed immediately or it may be saved and executed later on any thread or queue.
    ///
    ///   **Important:** This block must be executed at some point or the task will be stuck in the
    ///   `.Processing` state forever.
    ///
    ///   **Requires:** This block must not be executed more than once.
    public init(_ handler: (task: HTTPManagerTask, error: ErrorType, attempt: Int, callback: Bool -> Void) -> Void) {
        self.handler = { task, error, attempt, callback in
            // NSURLSessionTask.originalRequest may be nil if this is a stream task. We don't use stream tasks,
            // so this should never apply to us.
            if task.networkTask.originalRequest?.isIdempotent() ?? false {
                handler(task: task, error: error, attempt: attempt, callback: callback)
            } else {
                callback(false)
            }
        }
        super.init()
    }
    
    /// Returns a retry behavior that evaluates a block.
    ///
    /// The returned retry behavior will be evaluated for all requests regardless of whether the request
    /// is idempotent. If the request involves redirections, the original request is the one that is retried.
    ///
    /// - Important: Your handler needs to be aware of whether it's being invoked on a non-idempotent request
    ///   and only retry those requests where performing the request twice is safe. Your handler shold consult
    ///   the `originalRequest` property of the task for making this determination.
    ///
    /// The block takes the following parameters:
    ///
    /// - Parameter task: The `HTTPManagerTask` under consideration. You can use this task
    ///   to retrieve the last `networkTask` and its `originalRequest` and `response`.
    /// - Parameter error: The error that occurred. This may be an error from the networking portion
    ///   or it may be an error from the processing stage.
    /// - Parameter attempt: The number of retries so far. The first retry block is attempt `0`, the second is
    ///   attempt `1`, etc.
    /// - Parameter callback: A block that must be invoked to determine whether a retry should be done.
    ///   Passing `true` means the request should be automatically retried, `false` means no retry.
    ///   This block may be executed immediately or it may be saved and executed later on any thread or queue.
    ///
    ///   **Important:** This block must be executed at some point or the task will be stuck in the
    ///   `.Processing` state forever.
    ///
    ///   **Requires:** This block must not be executed more than once.
    public init(ignoringIdempotence handler: (task: HTTPManagerTask, error: ErrorType, attempt: Int, callback: Bool -> Void) -> Void) {
        self.handler = handler
        super.init()
    }
    
    public enum Strategy: Equatable {
        // NB: Lowercase enum cases matches expected Swift 3 naming conventions.
        
        /// Retries a single time with no delay.
        case retryOnce
        /// Retries once immediately, and then a second time after the given delay.
        case retryTwiceWithDelay(NSTimeInterval)
        /// Retries once immediately, and then a second time after a default short delay.
        /// - Note: The default delay is currently 2 seconds, but this may be subject
        ///   to changing in the future.
        public static let retryTwiceWithDefaultDelay = Strategy.retryTwiceWithDelay(2)
        /// Retries once immediately, then, assuming a networking error that indicates no
        /// connection could be established to the server, retries again once Reachability
        /// indicates the host associated with the request can be reached. The Reachability
        /// check is subject to the given timeout.
        // TODO: Implement Reachability
        // case retryWithReachability(timeout: NSTimeInterval)
        
        /// Evaluates the retry strategy for the given parameters.
        private func evaluate(task: HTTPManagerTask, error: ErrorType, attempt: Int, callback: Bool -> Void) {
            switch self {
            case .retryOnce:
                callback(attempt == 0)
            case .retryTwiceWithDelay(let delay):
                switch attempt {
                case 0:
                    callback(true)
                case 1:
                    let time = dispatch_time(DISPATCH_TIME_NOW, Int64(delay * NSTimeInterval(NSEC_PER_SEC)))
                    dispatch_after(time, dispatch_get_global_queue(task.userInitiated ? QOS_CLASS_USER_INITIATED : QOS_CLASS_UTILITY, 0), { callback(true) })
                default:
                    callback(false)
                }
            }
        }
    }
    
    /// Returns a retry behavior that retries automatically for networking errors.
    ///
    /// A networking error is defined as many errors in the `NSURLErrorDomain`, or a
    /// `PMJSON.JSONParserError` with a code of `.UnexpectedEOF` (as this may indicate a
    /// truncated response). The request will not be retried for networking errors that
    /// are unlikely to change when retrying.
    ///
    /// If the request is non-idempotent, it only retries if the error indicates that a
    /// connection was never made to the server (such as cannot find host).
    ///
    /// - Parameter strategy: The strategy to use when retrying.
    public static func retryNetworkFailure(withStrategy strategy: Strategy) -> HTTPManagerRetryBehavior {
        return HTTPManagerRetryBehavior(ignoringIdempotence: { task, error, attempt, callback in
            if task.networkTask.originalRequest?.isIdempotent() ?? false {
                if error.isTransientNetworkingError() {
                    strategy.evaluate(task, error: error, attempt: attempt, callback: callback)
                } else {
                    callback(false)
                }
            } else if error.isTransientNoConnectionError() {
                // We did not connect to the host, so idempotence doesn't matter.
                strategy.evaluate(task, error: error, attempt: attempt, callback: callback)
            } else {
                callback(false)
            }
        })
    }
    
    /// Returns a retry behavior that retries automatically for networking errors or a
    /// 503 Service Unavailable response.
    ///
    /// A networking error is defined as many errors in the `NSURLErrorDomain`, or a
    /// `PMJSON.JSONParserError` with a code of `.UnexpectedEOF` (as this may indicate a
    /// truncated response).The request will not be retried for networking errors that
    /// are unlikely to change when retrying.
    ///
    /// If the request is non-idempotent, it only retries if the error indicates that a
    /// connection was never made to the server (such as cannot find host) or in the case
    /// of a 503 Service Unavailable response (which indicates the server did not process
    /// the request).
    ///
    /// - Parameter strategy: The strategy to use when retrying.
    public static func retryNetworkFailureOrServiceUnavailable(withStrategy strategy: Strategy) -> HTTPManagerRetryBehavior {
        return HTTPManagerRetryBehavior(ignoringIdempotence: { task, error, attempt, callback in
            if task.networkTask.originalRequest?.isIdempotent() ?? false {
                if error.isTransientNetworkingError() || error.is503ServiceUnavailable() {
                    strategy.evaluate(task, error: error, attempt: attempt, callback: callback)
                } else {
                    callback(false)
                }
            } else if error.isTransientNoConnectionError()
                // We did not connect to the host, so idempotence doesn't matter.
                || error.is503ServiceUnavailable()
                // We did connect but got a 503 Service Unavailable, so the server didn't handle the request.
            {
                strategy.evaluate(task, error: error, attempt: attempt, callback: callback)
            } else {
                callback(false)
            }
        })
    }
    
    internal let handler: (task: HTTPManagerTask, error: ErrorType, attempt: Int, callback: Bool -> Void) -> Void
}

public func ==(lhs: HTTPManagerRetryBehavior.Strategy, rhs: HTTPManagerRetryBehavior.Strategy) -> Bool {
    switch (lhs, rhs) {
    case (.retryOnce, .retryOnce): return true
    case (.retryTwiceWithDelay(let a), .retryTwiceWithDelay(let b)): return a == b
    default: return false
    }
}

private extension ErrorType {
    /// Returns `true` if `self` is a transient networking error, or is a `PMJSON.JSONParserError`
    /// with a code of `.UnexpectedEOF`.
    func isTransientNetworkingError() -> Bool {
        switch self {
        case let error as JSONParserError where error.code == .UnexpectedEOF:
            return true
        case let error as NSError where error.domain == NSURLErrorDomain:
            // FIXME(Swift 3): Swift 3 will likely have a proper ErrorType enum for URL errors.
            
            switch error.code {
            case NSURLErrorUnknown:
                // We don't know what this is, so we'll err on the side of accepting it.
                return true
            case NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet, NSURLErrorBadServerResponse,
                 NSURLErrorZeroByteResource, NSURLErrorCannotDecodeRawData, NSURLErrorCannotDecodeContentData,
                 NSURLErrorCannotParseResponse,
                 NSURLErrorClientCertificateRequired...NSURLErrorSecureConnectionFailed, // all SSL errors
                 NSURLErrorDataNotAllowed:
                return true
            case NSURLErrorCallIsActive:
                // If we retry immediately this is unlikely to change, but if we retry after a delay
                // then retrying makes sense, so we'll accept it.
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
    
    /// Returns `true` if `self` is a transient networking error that guarantees that no data
    /// was sent to the server. This either means no connection was established, or a connection
    /// was established but the SSL handshake failed.
    func isTransientNoConnectionError() -> Bool {
        switch self {
        case let error as NSError where error.domain == NSURLErrorDomain:
            // FIXME(Swift 3): Swift 3 will likely have a proper ErrorType enum for URL errors.
            switch error.code {
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed,
            NSURLErrorClientCertificateRequired...NSURLErrorSecureConnectionFailed: // all SSL errors
                return true
            case NSURLErrorCallIsActive:
                // If we retry immediately this is unlikely to change, but if we retry after a delay
                // then retrying makes sense, so we'll accept it.
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
    
    /// Returns `true` if `self` is an `HTTPManagerError.FailedResponse(503, ...)`.
    func is503ServiceUnavailable() -> Bool {
        switch self {
        case let error as HTTPManagerError:
            switch error {
            case .FailedResponse(statusCode: 503, response: _, body: _, bodyJson: _):
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}

private extension NSURLRequest {
    /// Returns `true` if the request is idempotent (if the HTTP method is GET, HEAD, PUT,
    /// DELETE, OPTIONS, or TRACE).
    func isIdempotent() -> Bool {
        // HTTPMethod is optional, but it's unclear what happens if you assign nil.
        // I'm assuming it performs the default behavior, which is GET.
        switch HTTPMethod ?? "GET" {
        case "GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE":
            return true
        default:
            return false
        }
    }
}

// MARK: - Private

extension HTTPManager {
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
    weak var apiManager: HTTPManager?
    
    var tasks: [TaskIdentifier: TaskInfo] = [:]
    
    init(apiManager: HTTPManager) {
        self.apiManager = apiManager
        super.init()
    }
    
    /// A task identifier for an `NSURLSessionTask`.
    typealias TaskIdentifier = Int
    
    struct TaskInfo {
        let task: HTTPManagerTask
        let uploadBody: UploadBody?
        let processor: (HTTPManagerTask, HTTPManagerTaskResult<NSData>, attempt: Int, retry: HTTPManager -> Bool) -> Void
        var data: NSMutableData? = nil
        var attempt: Int = 0
        
        init(task: HTTPManagerTask, uploadBody: UploadBody? = nil, processor: (HTTPManagerTask, HTTPManagerTaskResult<NSData>, attempt: Int, retry: HTTPManager -> Bool) -> Void) {
            self.task = task
            self.uploadBody = uploadBody
            self.processor = processor
        }
    }
}

extension HTTPManager {
    /// Creates and returns an `HTTPManagerTask`.
    /// - Parameter request: The request to create the task from.
    /// - Parameter uploadBody: The data to upload, if any.
    /// - Parameter processor: The processing block. The `retry` parameter to the block is a closure that may be
    ///   executed to attempt to retry the task. If executed, the retry block will return `true` if the task could be
    ///   retried or `false` otherwise. If the task is not retried (or if retrying fails), the processor must arrange
    ///   for the task to transition to `.Completed` (unless it's already been canceled).
    /// - Returns: An `HTTPManagerTask`.
    /// - Important: After creating the task, you must start it by calling the `resume()` method.
    internal func createNetworkTaskWithRequest(request: HTTPManagerRequest, uploadBody: UploadBody?, processor: (HTTPManagerTask, HTTPManagerTaskResult<NSData>, attempt: Int, retry: HTTPManager -> Bool) -> Void) -> HTTPManagerTask {
        let urlRequest = request._preparedURLRequest
        var uploadBody = uploadBody
        if case .FormUrlEncoded(let queryItems)? = uploadBody {
            uploadBody = .Data(UploadBody.dataRepresentationForQueryItems(queryItems))
        }
        uploadBody?.evaluatePending()
        if let mock = request.mock ?? mockManager.mockForRequest(urlRequest, environment: environment) {
            NSURLProtocol.setProperty(mock, forKey: HTTPMockURLProtocol.requestProperty, inRequest: urlRequest)
        }
        let apiTask = inner.sync { inner -> HTTPManagerTask in
            let networkTask: NSURLSessionTask
            switch uploadBody {
            case .Data(let data)?:
                networkTask = inner.session.uploadTaskWithRequest(urlRequest, fromData: data)
            case _?:
                networkTask = inner.session.uploadTaskWithStreamedRequest(urlRequest)
            case nil:
                networkTask = inner.session.dataTaskWithRequest(urlRequest)
            }
            let apiTask = HTTPManagerTask(networkTask: networkTask, request: request)
            let taskInfo = SessionDelegate.TaskInfo(task: apiTask, uploadBody: uploadBody, processor: processor)
            inner.session.delegateQueue.addOperationWithBlock { [sessionDelegate=inner.sessionDelegate] in
                assert(sessionDelegate.tasks[networkTask.taskIdentifier] == nil, "internal HTTPManager error: tasks contains unknown taskInfo")
                sessionDelegate.tasks[networkTask.taskIdentifier] = taskInfo
            }
            return apiTask
        }
        #if os(iOS)
            if apiTask.trackingNetworkActivity {
                NetworkActivityManager.shared.incrementCounter()
            }
        #endif
        if apiTask.userInitiated {
            apiTask.networkTask.priority = NSURLSessionTaskPriorityHigh
        }
        return apiTask
    }
    
    /// Transitions the given task back into `.Running` with a new network task.
    ///
    /// This method updates the `SessionDelegate`'s `tasks` dictionary for the new
    /// network task, but it does not attempt to remove any existing entry for the
    /// old task. The caller is responsible for removing the old entry.
    ///
    /// The newly-created `NSURLSessionTask` is automatically resumed.
    ///
    /// - Parameter taskInfo: The `TaskInfo` object representing the task to retry.
    /// - Returns: An `NSURLSessionTask` for the retry, or `nil` if the task could not be retried
    ///   (e.g. because it's already been canceled).
    /// - Important: After creating the new network task, you must start it by calling the `resume()` method.
    private func retryNetworkTask(taskInfo: SessionDelegate.TaskInfo) -> NSURLSessionTask? {
        guard let request = taskInfo.task.networkTask.originalRequest else {
            preconditionFailure("internal HTTPManager error: networkTask.originalRequest is nil")
        }
        let networkTask = inner.sync { inner -> NSURLSessionTask? in
            let networkTask: NSURLSessionTask
            switch taskInfo.uploadBody {
            case .Data(let data)?:
                networkTask = inner.session.uploadTaskWithRequest(request, fromData: data)
            case _?:
                networkTask = inner.session.uploadTaskWithStreamedRequest(request)
            case nil:
                networkTask = inner.session.dataTaskWithRequest(request)
            }
            let result = taskInfo.task.resetStateToRunningWithNetworkTask(networkTask)
            if !result.ok {
                assert(result.oldState == .Canceled, "internal HTTPManager error: could not reset non-canceled task back to Running state")
                networkTask.cancel()
                return nil
            }
            var taskInfo = taskInfo
            taskInfo.attempt += 1
            inner.session.delegateQueue.addOperationWithBlock { [sessionDelegate=inner.sessionDelegate] in
                assert(sessionDelegate.tasks[networkTask.taskIdentifier] == nil, "internal HTTPManager error: tasks contains unknown taskInfo")
                sessionDelegate.tasks[networkTask.taskIdentifier] = taskInfo
            }
            return networkTask
        }
        if let networkTask = networkTask {
            #if os(iOS)
                if taskInfo.task.trackingNetworkActivity {
                    NetworkActivityManager.shared.incrementCounter()
                }
            #endif
            if taskInfo.task.userInitiated {
                networkTask.priority = NSURLSessionTaskPriorityHigh
            }
        }
        return networkTask
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
        #endif
        tasks.removeAll()
    }
    
    @objc func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
        guard var taskInfo = tasks[dataTask.taskIdentifier] else {
            completionHandler(.Cancel)
            return
        }
        assert(taskInfo.task.networkTask === dataTask, "internal HTTPManager error: taskInfo out of sync")
        if taskInfo.data != nil {
            taskInfo.data = nil
            tasks[dataTask.taskIdentifier] = taskInfo
        }
        completionHandler(.Allow)
    }
    
    @objc func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
        guard var taskInfo = tasks[dataTask.taskIdentifier] else { return }
        assert(taskInfo.task.networkTask === dataTask, "internal HTTPManager error: taskInfo out of sync")
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
        assert(apiTask.networkTask === task, "internal HTTPManager error: taskInfo out of sync")
        let processor = taskInfo.processor
        
        #if os(iOS)
            if apiTask.trackingNetworkActivity {
                NetworkActivityManager.shared.decrementCounter()
            }
        #endif
        
        let queue = dispatch_get_global_queue(apiTask.userInitiated ? QOS_CLASS_USER_INITIATED : QOS_CLASS_UTILITY, 0)
        if let error = error where error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            // Either we canceled during the networking portion, or someone called
            // cancel() on the NSURLSessionTask directly. In the latter case, treat it
            // as a cancellation anyway.
            let result = apiTask.transitionStateTo(.Canceled)
            assert(result.ok, "internal HTTPManager error: tried to cancel task that's already completed")
            dispatch_async(queue) {
                processor(apiTask, .Canceled, attempt: taskInfo.attempt, retry: { _ in return false })
            }
        } else {
            let result = apiTask.transitionStateTo(.Processing)
            if result.ok {
                assert(result.oldState == .Running, "internal HTTPManager error: tried to process task that's already processing")
                dispatch_async(queue) {
                    func retry(apiManager: HTTPManager) -> Bool {
                        guard let networkTask = apiManager.retryNetworkTask(taskInfo) else {
                            return false
                        }
                        networkTask.resume()
                        return true
                    }
                    if let error = error {
                        processor(apiTask, .Error(task.response, error), attempt: taskInfo.attempt, retry: retry)
                    } else if let response = task.response {
                        processor(apiTask, .Success(response, taskInfo.data ?? NSData()), attempt: taskInfo.attempt, retry: retry)
                    } else {
                        // this should be unreachable
                        let userInfo = [NSLocalizedDescriptionKey: "internal error: task response was nil with no error"]
                        processor(apiTask, .Error(nil, NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: userInfo)), attempt: taskInfo.attempt, retry: retry)
                    }
                }
            } else {
                assert(result.oldState == .Canceled, "internal HTTPManager error: tried to process task that's already completed")
                // We must have canceled concurrently with the networking portion finishing
                dispatch_async(queue) {
                    processor(apiTask, .Canceled, attempt: taskInfo.attempt, retry: { _ in return false })
                }
            }
        }
    }
    
    private static let cacheControlValues: Set<CaseInsensitiveASCIIString> = ["no-cache", "no-store", "max-age", "s-maxage"]
    
    @objc func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, willCacheResponse proposedResponse: NSCachedURLResponse, completionHandler: (NSCachedURLResponse?) -> Void) {
        guard var taskInfo = tasks[dataTask.taskIdentifier] else {
            completionHandler(proposedResponse)
            return
        }
        assert(taskInfo.task.networkTask === dataTask, "internal HTTPManager error: taskInfo out of sync")
        func hasCachingHeaders(response: NSURLResponse) -> Bool {
            guard let response = response as? NSHTTPURLResponse else { return false }
            if response.allHeaderFields["Expires"] != nil { return true }
            if let cacheControl = response.allHeaderFields["Cache-Control"] as? String {
                // Only treat certain directives as affecting caching.
                // Directives like `public` don't actually change whether something is cached.
                for (key, _) in DelimitedParameters(cacheControl, delimiter: ",") {
                    if SessionDelegate.cacheControlValues.contains(CaseInsensitiveASCIIString(key)) {
                        return true
                    }
                }
            }
            return false
        }
        switch (taskInfo.task.defaultResponseCacheStoragePolicy, proposedResponse.storagePolicy) {
        case (.AllowedInMemoryOnly, .Allowed):
            if hasCachingHeaders(proposedResponse.response) {
                completionHandler(proposedResponse)
            } else {
                completionHandler(NSCachedURLResponse(response: proposedResponse.response, data: proposedResponse.data, userInfo: proposedResponse.userInfo, storagePolicy: .AllowedInMemoryOnly))
            }
        case (.NotAllowed, .Allowed), (.NotAllowed, .AllowedInMemoryOnly):
            if hasCachingHeaders(proposedResponse.response) {
                completionHandler(proposedResponse)
            } else {
                completionHandler(nil)
            }
        default:
            completionHandler(proposedResponse)
        }
    }

    @objc func URLSession(session: NSURLSession, task: NSURLSessionTask, willPerformHTTPRedirection response: NSHTTPURLResponse, newRequest request: NSURLRequest, completionHandler: (NSURLRequest?) -> Void) {
        guard let taskInfo = tasks[task.taskIdentifier] else {
            completionHandler(request)
            return
        }
        assert(taskInfo.task.networkTask === task, "internal HTTPManager error: taskInfo out of sync")
        if taskInfo.task.followRedirects {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
    
    @objc func URLSession(session: NSURLSession, task: NSURLSessionTask, needNewBodyStream completionHandler: (NSInputStream?) -> Void) {
        guard let taskInfo = tasks[task.taskIdentifier] else {
            completionHandler(nil)
            return
        }
        assert(taskInfo.task.networkTask === task, "internal HTTPManager error: taskInfo out of sync")
        switch taskInfo.uploadBody {
        case .Data(let data)?:
            completionHandler(NSInputStream(data: data))
        case .FormUrlEncoded(let queryItems)?:
            completionHandler(NSInputStream(data: UploadBody.dataRepresentationForQueryItems(queryItems)))
        case .JSON(let json)?:
            dispatch_async(dispatch_get_global_queue(taskInfo.task.userInitiated ? QOS_CLASS_USER_INITIATED : QOS_CLASS_UTILITY, 0)) {
                completionHandler(NSInputStream(data: JSON.encodeAsData(json, pretty: false)))
            }
        case .MultipartMixed?:
            // TODO: implement me
            completionHandler(nil)
        case nil:
            completionHandler(nil)
        }
    }
}
