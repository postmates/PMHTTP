//
//  HTTPManager.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 12/10/15.
//  Copyright © 2015 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
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
    
    /// A block that is invoked whenever the number of outstanding `HTTPManagerTask`s changes.
    ///
    /// If the value of this property changes while there are outstanding tasks, the old
    /// value is not invoked, but the new value will be invoked asynchronously with the current
    /// number of tasks. If there are no outstanding tasks the new value will not be invoked.
    ///
    /// - Note: This block is always invoked on the main thread.
    public static var networkActivityHandler: ((_ numberOfActiveTasks: Int) -> Void)? {
        get {
            return NetworkActivityManager.shared.networkActivityHandler
        }
        set {
            NetworkActivityManager.shared.networkActivityHandler = newValue
        }
    }
    
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
    public var sessionConfiguration: URLSessionConfiguration {
        get {
            let config = inner.sync({ $0.sessionConfiguration })
            return unsafeDowncast(config.copy() as AnyObject, to: URLSessionConfiguration.self)
        }
        set {
            let config = unsafeDowncast(newValue.copy() as AnyObject, to: URLSessionConfiguration.self)
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
    public var defaultCredential: URLCredential? {
        get {
            return inner.sync({ $0.defaultCredential })
        }
        set {
            var newValue = newValue
            if let credential = newValue, credential.user == nil || !credential.hasPassword {
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
    
    /// Whether errors should be assumed to be JSON. The default value is `false`.
    ///
    /// If `true`, all error bodies are parsed as JSON regardless of their declared
    /// Content-Type. This setting is intended to work around bad servers that
    /// don't declare their Content-Types properly.
    public var defaultAssumeErrorsAreJSON: Bool {
        get {
            return inner.sync({ $0.defaultAssumeErrorsAreJSON })
        }
        set {
            inner.asyncBarrier {
                $0.defaultAssumeErrorsAreJSON = newValue
            }
        }
    }
    
    /// The user agent that's passed to every request.
    public var userAgent: String {
        return inner.sync({
            $0.sessionConfiguration.httpAdditionalHeaders?["User-Agent"] as? String
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
        var sessionConfiguration: URLSessionConfiguration = .default
        var defaultCredential: URLCredential?
        var defaultRetryBehavior: HTTPManagerRetryBehavior?
        var defaultAssumeErrorsAreJSON: Bool = false

        var session: URLSession!
        var sessionDelegate: SessionDelegate!
        var oldSessions: [URLSession] = []
        
        func setHeader(_ header: String, value: String, overwrite: Bool = true) {
            var headers = sessionConfiguration.httpAdditionalHeaders ?? [:]
            if overwrite || headers[header] == nil {
                headers[header] = value
                sessionConfiguration.httpAdditionalHeaders = headers
            }
        }
    }
    
    fileprivate let inner: QueueConfined<Inner> = QueueConfined(label: "HTTPManager internal queue", value: Inner())
    
    fileprivate init(shared: Bool) {
        super.init()
        inner.unsafeDirectAccess { [value=HTTPManager.defaultUserAgent] in
            $0.setHeader("User-Agent", value: value, overwrite: true)
        }
        if shared {
            let setup: HTTPManagerConfigurable?
            #if os(OSX)
                setup = NSApplication.shared().delegate as? HTTPManagerConfigurable
            #elseif os(watchOS)
                setup = WKExtension.shared().delegate as? HTTPManagerConfigurable
            #elseif os(iOS)
                // We have to detect if we're in an app extension, because we can't access UIApplication.sharedApplication().
                // In that event, we can't configure ourselves and the extension must do it for us.
                // We'll check for the presence of the NSExtension key in the Info.plist.
                if Bundle.main.infoDictionary?["NSExtension"] != nil {
                    // This appears to be an application extension. No configuration allowed.
                    setup = nil
                } else {
                    // This is an application. We still can't invoke UIApplication.sharedApplication directly,
                    // but we can use `valueForKey(_:)` to get it, and application extensions can still reference the type.
                    setup = (UIApplication.value(forKey: "sharedApplication") as? UIApplication)?.delegate as? HTTPManagerConfigurable
                }
            #elseif os(tvOS)
                // tvOS seems to respect APPLICATION_EXTENSION_API_ONLY even  though (AFAIK) there
                // are no extensions on tvOS. Use the same iOS hack here.
                setup = (UIApplication.value(forKey: "sharedApplication") as? UIApplication)?.delegate as? HTTPManagerConfigurable
            #endif
            setup?.configure(httpManager: self)
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
    
    private func resetSession(_ inner: Inner, invalidate: Bool) {
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
        let config = unsafeDowncast(inner.sessionConfiguration.copy() as AnyObject, to: URLSessionConfiguration.self)
        var classes = config.protocolClasses ?? []
        classes.insert(HTTPMockURLProtocol.self, at: 0)
        config.protocolClasses = classes
        let session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        inner.session = session
        session.delegateQueue.name = "HTTPManager session delegate queue"
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
    public let baseURL: URL
    
    /// Initializes an environment with a base URL.
    /// - Parameter baseURL: The base URL to use for the environment. Must be a valid absolute URL
    ///   according to RFC 3986.
    /// - Returns: An `HTTPManagerEnvironment` if the base URL is a valid absolute URL, `nil` otherwise.
    ///
    /// - Note: If `baseURL` has a non-empty `path` that does not end in a slash, the path is modified to
    ///   include a trailing slash. If `baseURL` has a query or fragment component, these components are
    ///   stripped.
    public convenience init?(baseURL: URL) {
        guard let comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
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
        guard let comps = URLComponents(string: string) else {
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
    public func isPrefix(of url: URL) -> Bool {
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return false }
        func getPort(_ components: URLComponents) -> Int? {
            if let port = components.port { return port as Int }
            switch components.scheme {
            case CaseInsensitiveASCIIString("http")?: return 80
            case CaseInsensitiveASCIIString("https")?: return 443
            default: return nil
            }
        }
        func caseInsensitiveCompare(_ a: String?, _ b: String?) -> Bool {
            return a.map({CaseInsensitiveASCIIString($0)}) == b.map({CaseInsensitiveASCIIString($0)})
        }
        guard caseInsensitiveCompare(baseURLComponents.scheme, urlComponents.scheme)
            && baseURLComponents.percentEncodedUser == urlComponents.percentEncodedUser
            && baseURLComponents.percentEncodedPassword == urlComponents.percentEncodedPassword
            && caseInsensitiveCompare(baseURLComponents.percentEncodedHost, urlComponents.percentEncodedHost)
            && getPort(baseURLComponents) == getPort(urlComponents)
            else { return false }
        switch (baseURLComponents.percentEncodedPath, urlComponents.percentEncodedPath) {
        case ("", _): return true
        case (_, ""): return false
        case let (a, b): return b.hasPrefix(a)
        }
    }
    
    private init?(components: URLComponents) {
        guard components.scheme != nil else {
            // no scheme? Not an absolute URL
            return nil
        }
        var components = components
        // ensure the URL is terminated with a slash
        if !components.path.isEmpty && !components.path.hasSuffix("/") {
            components.path += "/"
        }
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            return nil
        }
        baseURL = url
        baseURLComponents = components
        super.init()
    }
    
    /// `NSURLComponents` object equivalent to `baseURL`.
    /// This property is `private` because the returned object is mutable but should not be mutated.
    /// It only exists to avoid re-parsing the URL every time its components is accessed.
    private let baseURLComponents: URLComponents
    
    public override var description: String {
        // FIXME: Switch to ObjectIdentifier.address or whatever it's called when it's available
        let ptr = unsafeBitCast(Unmanaged.passUnretained(self).toOpaque(), to: UInt.self)
        return "<HTTPManagerEnvironment: 0x\(String(ptr, radix: 16)) \(baseURL.absoluteString))>"
    }
    
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? HTTPManagerEnvironment else { return false }
        return baseURL == other.baseURL
    }
    
    public override var hash: Int {
        return baseURL.hashValue &+ 1
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
    func configure(httpManager: HTTPManager)
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
    public func request(GET path: String, parameters: [String: Any] = [:]) -> HTTPManagerDataRequest! {
        return request(GET: path, parameters: parameters.map({ URLQueryItem(name: $0, value: String(describing: $1)) }))
    }
    /// Creates a GET request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the query
    ///   string.
    /// - Returns: An `HTTPManagerDataRequest`, or `nil` if the `path`  cannot be
    ///   parsed by `NSURL`.
    @objc(requestForGET:queryItems:)
    public func request(GET path: String, parameters: [URLQueryItem]) -> HTTPManagerDataRequest! {
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
    public func request(DELETE path: String, parameters: [String: Any] = [:]) -> HTTPManagerActionRequest! {
        return request(DELETE: path, parameters: parameters.map({ URLQueryItem(name: $0, value: String(describing: $1)) }))
    }
    /// Creates a DELETE request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the query
    ///   string.
    /// - Returns: An `HTTPManagerActionRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForDELETE:queryItems:)
    public func request(DELETE path: String, parameters: [URLQueryItem]) -> HTTPManagerActionRequest! {
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
    public func request(POST path: String, parameters: [String: Any] = [:]) -> HTTPManagerUploadFormRequest! {
        return request(POST: path, parameters: parameters.map({ URLQueryItem(name: $0, value: String(describing: $1)) }))
    }
    /// Creates a POST request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`.
    /// - Returns: An `HTTPManagerUploadFormRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForPOST:queryItems:)
    public func request(POST path: String, parameters: [URLQueryItem]) -> HTTPManagerUploadFormRequest! {
        return constructRequest(path, f: { HTTPManagerUploadFormRequest(apiManager: self, URL: $0, method: .POST, parameters: parameters) })
    }
    /// Creates a POST request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter contentType: The MIME type of the data. Defaults to `"application/octet-stream"`.
    /// - Parameter data: The data to upload as the body of the request.
    /// - Returns: An `HTTPManagerUploadDataRequest`, or `nil` if the `path` cannot
    ///   be parsed by `NSURL`.
    @objc(requestForPOST:contentType:data:)
    public func request(POST path: String, contentType: String = "application/octet-stream", data: Data) -> HTTPManagerUploadDataRequest! {
        return constructRequest(path, f: { HTTPManagerUploadDataRequest(apiManager: self, URL: $0, method: .POST, contentType: contentType, data: data) })
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
    public func request(PUT path: String, parameters: [String: Any] = [:]) -> HTTPManagerUploadFormRequest! {
        return request(PUT: path, parameters: parameters.map({ URLQueryItem(name: $0, value: String(describing: $1)) }))
    }
    /// Creates a PUT request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`.
    /// - Returns: An `HTTPManagerUploadFormRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForPUT:queryItems:)
    public func request(PUT path: String, parameters: [URLQueryItem]) -> HTTPManagerUploadFormRequest! {
        return constructRequest(path, f: { HTTPManagerUploadFormRequest(apiManager: self, URL: $0, method: .PUT, parameters: parameters) })
    }
    /// Creates a PUT request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter contentType: The MIME type of the data. Defaults to `"application/octet-stream"`.
    /// - Parameter data: The data to upload as the body of the request.
    /// - Returns: An `HTTPManagerUploadDataRequest`, or `nil` if the `path` cannot
    ///   be parsed by `NSURL`.
    @objc(requestForPUT:contentType:data:)
    public func request(PUT path: String, contentType: String = "application/octet-stream", data: Data) -> HTTPManagerUploadDataRequest! {
        return constructRequest(path, f: { HTTPManagerUploadDataRequest(apiManager: self, URL: $0, method: .PUT, contentType: contentType, data: data) })
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
    public func request(PATCH path: String, parameters: [String: Any] = [:]) -> HTTPManagerUploadFormRequest! {
        return request(PATCH: path, parameters: parameters.map({ URLQueryItem(name: $0, value: String(describing: $1)) }))
    }
    /// Creates a PATCH request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter parameters: The request parameters, passed in the body as
    ///   `application/x-www-form-urlencoded`.
    /// - Returns: An `HTTPManagerUploadFormRequest`, or `nil` if the `path` cannot be
    ///   parsed by `NSURL`.
    @objc(requestForPATCH:queryItems:)
    public func request(PATCH path: String, parameters: [URLQueryItem]) -> HTTPManagerUploadFormRequest! {
        return constructRequest(path, f: { HTTPManagerUploadFormRequest(apiManager: self, URL: $0, method: .PATCH, parameters: parameters) })
    }
    /// Creates a PATCH request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter contentType: The MIME type of the data. Defaults to `"application/octet-stream"`.
    /// - Parameter data: The data to upload as the body of the request.
    /// - Returns: An `HTTPManagerUploadDataRequest`, or `nil` if the `path` cannot
    ///   be parsed by `NSURL`.
    @objc(requestForPATCH:contentType:data:)
    public func request(PATCH path: String, contentType: String = "application/octet-stream", data: Data) -> HTTPManagerUploadDataRequest! {
        return constructRequest(path, f: { HTTPManagerUploadDataRequest(apiManager: self, URL: $0, method: .PATCH, contentType: contentType, data: data) })
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
    
    private func constructRequest<T: HTTPManagerRequest>(_ path: String, f: (URL) -> T) -> T? {
        let (environment, credential, defaultRetryBehavior, assumeErrorsAreJSON) = inner.sync({ inner -> (Environment?, URLCredential?, HTTPManagerRetryBehavior?, Bool) in
            return (inner.environment, inner.defaultCredential, inner.defaultRetryBehavior, inner.defaultAssumeErrorsAreJSON)
        })
        // FIXME: Get rid of NSURL when https://github.com/apple/swift/pull/3910 is fixed.
        guard let url = NSURL(string: path, relativeTo: environment?.baseURL) as URL? else { return nil }
        let request = f(url)
        if let credential = credential, let environment = environment {
            // make sure the requested entity is within the space defined by baseURL
            if environment.isPrefix(of: url) {
                request.credential = credential
            }
        }
        request.retryBehavior = defaultRetryBehavior
        request.assumeErrorsAreJSON = assumeErrorsAreJSON
        return request
    }
}

// MARK: HTTPManagerError

/// Errors returned by HTTPManager
public enum HTTPManagerError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    /// An HTTP response was returned that indicates failure.
    /// - Parameter statusCode: The HTTP status code. Any code outside of 2xx or 3xx indicates failure.
    /// - Parameter response: The `NSHTTPURLResponse` object.
    /// - Parameter body: The body of the response, if any.
    /// - Parameter bodyJson: If the response `Content-Type` is `application/json`, contains the results
    ///   of decoding the body as JSON. If the decode fails, or the `Content-Type` is not `application/json`,
    ///   `bodyJson` is `nil`.
    /// - Note: 401 Unauthorized errors are represented by `HTTPManagerError.Unauthorized` instead of
    ///   `FailedResponse`.
    case failedResponse(statusCode: Int, response: HTTPURLResponse, body: Data, bodyJson: JSON?)
    /// A 401 Unauthorized HTTP response was returned.
    /// - Parameter credential: The `NSURLCredential` that was used in the request, if any.
    /// - Parameter response: The `NSHTTPURLResponse` object.
    /// - Parameter body: The body of the response, if any.
    /// - Parameter bodyJson: If the response `Content-Type` is `application/json`, contains the results
    ///   of decoding the body as JSON. If the decode fails, or the `Content-Type` is not `application/json`,
    ///   `bodyJson` is `nil`.
    case unauthorized(credential: URLCredential?, response: HTTPURLResponse, body: Data, bodyJson: JSON?)
    /// An HTTP response was returned that had an incorrect Content-Type header.
    /// - Note: Missing Content-Type headers are not treated as errors.
    /// - Note: Custom parse requests (using `parse(with:)`) do not throw this automatically, but
    ///   the parse handler may choose to throw it.
    /// - Parameter contentType: The Content-Type header of the HTTP response.
    /// - Parameter response: The `NSHTTPURLResponse` object.
    /// - Parameter body: The body of the response, if any.
    case unexpectedContentType(contentType: String, response: HTTPURLResponse, body: Data)
    /// An HTTP response returned a 204 No Content where an entity was expected.
    /// This is only thrown automatically from parse requests with a GET or HEAD method.
    /// - Note: Custom parse requests (using `parse(with:)`) do not throw this automatically, but
    ///   the parse handler may choose to throw it.
    /// - Parameter response: The `NSHTTPURLResponse` object.
    case unexpectedNoContent(response: HTTPURLResponse)
    /// A redirect was encountered while trying to parse a response that has redirects disabled.
    /// This can only be returned if `HTTPManagerRequest.shouldFollowRedirects` is set to `false`
    /// and the request is configured to parse the response.
    /// - Parameter statusCode: The 3xx HTTP status code.
    /// - Parameter location: The contents of the `"Location"` header, interpreted as a URL, or `nil` if
    /// - Parameter response: The `NSHTTPURLResponse` object.
    ///   the header is missing or cannot be parsed.
    /// - Parameter body: The body of the response, if any.
    case unexpectedRedirect(statusCode: Int, location: URL?, response: HTTPURLResponse, body: Data)
    
    public var description: String {
        switch self {
        case let .failedResponse(statusCode, response, body, json):
            let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            var s = "FailedResponse(\(statusCode) \(statusText), \(response.url?.relativeString ?? "nil"), "
            if let json = json {
                s += "bodyJson: \(json))"
            } else {
                s += "body: \(describeData(body)))"
            }
            return s
        case let .unauthorized(credential, response, body, json):
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
            s += ", \(response.url?.relativeString ?? "nil"), "
            if let json = json {
                s += "bodyJson: \(json))"
            } else {
                s += "body: \(describeData(body)))"
            }
            return s
        case let .unexpectedContentType(contentType, response, body):
            return "UnexpectedContentType(\(String(reflecting: contentType)), \(response.url?.relativeString ?? "nil"), body: \(describeData(body)))"
        case let .unexpectedNoContent(response):
            return "UnexpectedNoContent(\(response.url?.relativeString ?? "nil"))"
        case let .unexpectedRedirect(statusCode, location, response, _):
            let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            return "UnexpectedRedirect(\(statusCode) \(statusText), \(response.url?.relativeString ?? "nil"), location: \(location as ImplicitlyUnwrappedOptional))"
        }
    }
    
    public var debugDescription: String {
        switch self {
        case let .failedResponse(statusCode, response, body, json):
            let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            return "HTTPManagerError.FailedResponse(statusCode: \(statusCode) \(statusText), "
                + "response: \(response), "
                + "body: \(describeData(body)), "
                + "bodyJson: \(json.map({String(reflecting: $0)}) ?? "nil"))"
        case let .unauthorized(credential, response, body, json):
            return "HTTPManagerError.Unauthorized(credential: \(credential.map({String(reflecting: $0)}) ?? "nil"), "
                + "response: \(response), "
                + "body: \(describeData(body)), "
                + "bodyJson: \(json.map({String(reflecting: $0)}) ?? "nil"))"
        case let .unexpectedContentType(contentType, response, body):
            return "HTTPManagerError.UnexpectedContentType(contentType: \(String(reflecting: contentType)), "
                + "response: \(response), "
                + "body: \(describeData(body)))"
        case let .unexpectedNoContent(response):
            return "HTTPManagerError.UnexpectedNoContent(response: \(response))"
        case let .unexpectedRedirect(statusCode, location, response, body):
            let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            let bodyText = describeData(body)
            return "HTTPManagerError.UnexpectedRedirect(statusCode: \(statusCode) \(statusText), "
                + "location: \(location as ImplicitlyUnwrappedOptional), "
                + "response: \(response), "
                + "body: \(bodyText))"
        }
    }
}

private func describeData(_ data: Data) -> String {
    // we don't have access to the response so we can't see if it included a MIME type.
    // just assume utf-8 instead. If it's not utf-8, it's unlikely to decode so that's fine.
    if !data.isEmpty, let str = String(data: data, encoding: String.Encoding.utf8) {
        return String(reflecting: str)
    } else {
        return String(describing: data)
    }
}

/// Represents the retry behavior for an HTTP request.
///
/// Retry behaviors provide a mechanism for requests to automatically retry upon failure before
/// notifying the caller about the failure. Any arbitrary retry behavior can be implemented, but
/// convenience methods are provided for some of the more common behaviors.
///
/// Unless otherwise specified, retry behaviors are only evaluated for idempotent requests.
/// This is controlled by the `isIdempotent` property of `HTTPManagerRequest`, which defaults to
/// `true` for GET, HEAD, PUT, DELETE, OPTIONS, and TRACE requests, and `false` otherwise.
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
    public init(_ handler: @escaping (_ task: HTTPManagerTask, _ error: Error, _ attempt: Int, _ callback: @escaping (Bool) -> Void) -> Void) {
        self.handler = { task, error, attempt, callback in
            if task.isIdempotent {
                handler(task, error, attempt, callback)
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
    public init(ignoringIdempotence handler: @escaping (_ task: HTTPManagerTask, _ error: Error, _ attempt: Int, _ callback: @escaping (Bool) -> Void) -> Void) {
        self.handler = handler
        super.init()
    }
    
    public enum Strategy: Equatable {
        // NB: Lowercase enum cases matches expected Swift 3 naming conventions.
        
        /// Retries a single time with no delay.
        case retryOnce
        /// Retries once immediately, and then a second time after the given delay.
        case retryTwiceWithDelay(TimeInterval)
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
        fileprivate func evaluate(_ task: HTTPManagerTask, error: Error, attempt: Int, callback: @escaping (Bool) -> Void) {
            switch self {
            case .retryOnce:
                callback(attempt == 0)
            case .retryTwiceWithDelay(let delay):
                switch attempt {
                case 0:
                    callback(true)
                case 1:
                    let queue = DispatchQueue.global(qos: task.userInitiated ? .userInitiated : .utility)
                    queue.asyncAfter(deadline: DispatchTime.now() + delay, execute: { callback(true) })
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
            if task.isIdempotent {
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
            if task.isIdempotent {
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
    
    internal let handler: (_ task: HTTPManagerTask, _ error: Error, _ attempt: Int, _ callback: @escaping (Bool) -> Void) -> Void
}

public func ==(lhs: HTTPManagerRetryBehavior.Strategy, rhs: HTTPManagerRetryBehavior.Strategy) -> Bool {
    switch (lhs, rhs) {
    case (.retryOnce, .retryOnce): return true
    case (.retryTwiceWithDelay(let a), .retryTwiceWithDelay(let b)): return a == b
    default: return false
    }
}

private extension Error {
    /// Returns `true` if `self` is a transient networking error, or is a `PMJSON.JSONParserError`
    /// with a code of `.UnexpectedEOF`.
    func isTransientNetworkingError() -> Bool {
        switch self {
        case let error as JSONParserError where error.code == .unexpectedEOF:
            return true
        case let error as URLError:
            switch error.code {
            case .unknown:
                // We don't know what this is, so we'll err on the side of accepting it.
                return true
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                 .dnsLookupFailed, .notConnectedToInternet, .badServerResponse,
                 .zeroByteResource, .cannotDecodeRawData, .cannotDecodeContentData,
                 .cannotParseResponse, .dataNotAllowed,
                 // All SSL errors
                 .clientCertificateRequired, .clientCertificateRejected, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .secureConnectionFailed:
                return true
            case .callIsActive:
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
        case let error as URLError:
            switch error.code {
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet, .dataNotAllowed,
                 // All SSL errors
                 .clientCertificateRequired, .clientCertificateRejected, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .secureConnectionFailed:
                return true
            case .callIsActive:
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
            case .failedResponse(statusCode: 503, response: _, body: _, bodyJson: _):
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}

// MARK: - Private

extension HTTPManager {
    // MARK: Default User-Agent
    fileprivate static let defaultUserAgent: String = {
        let bundle = Bundle.main
        
        func appName() -> String {
            if let name = bundle.object(forInfoDictionaryKey: "User Agent App Name") as? String {
                return name
            } else if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                return name
            } else if let name = bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String {
                return name
            } else {
                return "(null)"
            }
        }
        
        func appVersion() -> String {
            let marketingVersionNumber = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let buildVersionNumber = bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
            if let marketingVersionNumber = marketingVersionNumber, let buildVersionNumber = buildVersionNumber, marketingVersionNumber != buildVersionNumber {
                return "\(marketingVersionNumber) rv:\(buildVersionNumber)"
            } else {
                return marketingVersionNumber ?? buildVersionNumber ?? "(null)"
            }
        }
        
        func deviceInfo() -> (model: String, systemName: String) {
            #if os(OSX)
                return ("Macintosh", "Mac OS X")
            #elseif os(iOS) || os(tvOS)
                let device = UIDevice.current
                return (device.model, device.systemName)
            #elseif os(watchOS)
                let device = WKInterfaceDevice.current()
                return (device.model, device.systemName)
            #endif
        }
        
        func systemVersion() -> String {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            var s = "\(version.majorVersion).\(version.minorVersion)"
            if version.patchVersion != 0 {
                s += ".\(version.patchVersion)"
            }
            return s
        }
        
        let localeIdentifier = Locale.current.identifier
        
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
        let processor: (HTTPManagerTask, HTTPManagerTaskResult<Data>, _ attempt: Int, _ retry: @escaping (HTTPManager) -> Bool) -> Void
        var data: NSMutableData? = nil
        var attempt: Int = 0
        
        init(task: HTTPManagerTask, uploadBody: UploadBody? = nil, processor: @escaping (HTTPManagerTask, HTTPManagerTaskResult<Data>, _ attempt: Int, _ retry: @escaping (HTTPManager) -> Bool) -> Void) {
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
    internal func createNetworkTaskWithRequest(_ request: HTTPManagerRequest, uploadBody: UploadBody?, processor: @escaping (HTTPManagerTask, HTTPManagerTaskResult<Data>, _ attempt: Int, _ retry: @escaping (HTTPManager) -> Bool) -> Void) -> HTTPManagerTask {
        var urlRequest = request._preparedURLRequest
        var uploadBody = uploadBody
        if case .formUrlEncoded(let queryItems)? = uploadBody {
            uploadBody = .data(UploadBody.dataRepresentationForQueryItems(queryItems))
        }
        uploadBody?.evaluatePending()
        if let mock = request.mock ?? mockManager.mockForRequest(urlRequest, environment: environment) {
            // we have to go through NSMutableURLRequest in order to set the protocol property
            let mutReq = unsafeDowncast((urlRequest as NSURLRequest).mutableCopy() as AnyObject, to: NSMutableURLRequest.self)
            URLProtocol.setProperty(mock, forKey: HTTPMockURLProtocol.requestProperty, in: mutReq)
            urlRequest = mutReq as URLRequest
        }
        let apiTask = inner.sync { inner -> HTTPManagerTask in
            let networkTask: URLSessionTask
            switch uploadBody {
            case .data(let data)?:
                networkTask = inner.session.uploadTask(with: urlRequest, from: data)
            case _?:
                networkTask = inner.session.uploadTask(withStreamedRequest: urlRequest)
            case nil:
                networkTask = inner.session.dataTask(with: urlRequest)
            }
            let apiTask = HTTPManagerTask(networkTask: networkTask, request: request, sessionDelegateQueue: inner.session.delegateQueue)
            let taskInfo = SessionDelegate.TaskInfo(task: apiTask, uploadBody: uploadBody, processor: processor)
            inner.session.delegateQueue.addOperation { [sessionDelegate=inner.sessionDelegate!] in
                assert(sessionDelegate.tasks[networkTask.taskIdentifier] == nil, "internal HTTPManager error: tasks contains unknown taskInfo")
                sessionDelegate.tasks[networkTask.taskIdentifier] = taskInfo
            }
            return apiTask
        }
        if apiTask.userInitiated {
            apiTask.networkTask.priority = URLSessionTask.highPriority
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
    /// - Returns: `true` if the task is retrying, or `false` if it could not be retried
    ///   (e.g. because it's already been canceled).
    fileprivate func retryNetworkTask(_ taskInfo: SessionDelegate.TaskInfo) -> Bool {
        guard let request = taskInfo.task.networkTask.originalRequest else {
            preconditionFailure("internal HTTPManager error: networkTask.originalRequest is nil")
        }
        let networkTask = inner.sync { inner -> URLSessionTask? in
            let networkTask: URLSessionTask
            switch taskInfo.uploadBody {
            case .data(let data)?:
                networkTask = inner.session.uploadTask(with: request, from: data)
            case _?:
                networkTask = inner.session.uploadTask(withStreamedRequest: request)
            case nil:
                networkTask = inner.session.dataTask(with: request)
            }
            let result = taskInfo.task.resetStateToRunning(with: networkTask)
            if !result.ok {
                assert(result.oldState == .canceled, "internal HTTPManager error: could not reset non-canceled task back to Running state")
                networkTask.cancel()
                return nil
            }
            var taskInfo = taskInfo
            taskInfo.attempt += 1
            inner.session.delegateQueue.addOperation { [sessionDelegate=inner.sessionDelegate!] in
                assert(sessionDelegate.tasks[networkTask.taskIdentifier] == nil, "internal HTTPManager error: tasks contains unknown taskInfo")
                sessionDelegate.tasks[networkTask.taskIdentifier] = taskInfo
            }
            return networkTask
        }
        if let networkTask = networkTask {
            if taskInfo.task.affectsNetworkActivityIndicator {
                taskInfo.task.setTrackingNetworkActivity()
            }
            if taskInfo.task.userInitiated {
                networkTask.priority = URLSessionTask.highPriority
            }
            networkTask.resume()
            return true
        } else {
            return false
        }
    }
}

extension SessionDelegate: URLSessionDataDelegate {
    #if enableDebugLogging
    func log(msg: String) {
        let ptr = unsafeBitCast(unsafeAddressOf(self), UInt.self)
        NSLog("<SessionDelegate: 0x%zx> %@", ptr, msg)
    }
    #else
    // Use @inline(__always) to guarantee the function call is completely removed
    // and @autoclosure to make sure we don't evaluate the arguments.
    @inline(__always) func log(_: @autoclosure () -> String) {}
    #endif
    
    @objc func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        log("didBecomeInvalidWithError: \(error)")
        apiManager?.inner.asyncBarrier { inner in
            if let idx = inner.oldSessions.index(where: { $0 === self }) {
                inner.oldSessions.remove(at: idx)
            }
        }
        for taskInfo in tasks.values {
            taskInfo.task.clearTrackingNetworkActivity()
        }
        tasks.removeAll()
    }
    
    @objc func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard var taskInfo = tasks[dataTask.taskIdentifier] else {
            log("didReceiveResponse; ignoring, task \(dataTask) not tracked")
            completionHandler(.cancel)
            return
        }
        assert(taskInfo.task.networkTask === dataTask, "internal HTTPManager error: taskInfo out of sync")
        log("didReceiveResponse for task \(dataTask)")
        if taskInfo.data != nil {
            taskInfo.data = nil
            tasks[dataTask.taskIdentifier] = taskInfo
        }
        completionHandler(.allow)
    }
    
    @objc func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard var taskInfo = tasks[dataTask.taskIdentifier] else {
            log("didReceiveData; ignoring, task \(dataTask) not tracked")
            return
        }
        assert(taskInfo.task.networkTask === dataTask, "internal HTTPManager error: taskInfo out of sync")
        log("didReceiveData for task \(dataTask)")
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
        taskData.append(data)
    }
    
    @objc func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // NB: If we canceled during the networking portion, we delay reporting the
        // cancellation until the networking portion is done. This should show up here
        // as either an NSURLErrorCancelled error, or simply the inability to transition
        // to processing due to the state being cancelled (which may happen if the task
        // cancellation occurs concurrently with the networking finishing).
        
        guard let taskInfo = tasks.removeValue(forKey: task.taskIdentifier) else {
            log("task:didCompleteWithError; ignoring, task \(task) not tracked")
            return
        }
        let apiTask = taskInfo.task
        assert(apiTask.networkTask === task, "internal HTTPManager error: taskInfo out of sync")
        log("task:didCompleteWithError for task \(task), error: \(error)")
        let processor = taskInfo.processor
        
        apiTask.clearTrackingNetworkActivity()
        
        let queue = DispatchQueue.global(qos: apiTask.userInitiated ? .userInitiated : .utility)
        if let error = error as? URLError, error.code == .cancelled {
            // Either we canceled during the networking portion, or someone called
            // cancel() on the NSURLSessionTask directly. In the latter case, treat it
            // as a cancellation anyway.
            let result = apiTask.transitionState(to: .canceled)
            assert(result.ok, "internal HTTPManager error: tried to cancel task that's already completed")
            queue.async {
                processor(apiTask, .canceled, taskInfo.attempt, { _ in return false })
            }
        } else {
            let result = apiTask.transitionState(to: .processing)
            if result.ok {
                assert(result.oldState == .running, "internal HTTPManager error: tried to process task that's already processing")
                queue.async {
                    func retry(_ apiManager: HTTPManager) -> Bool {
                        return apiManager.retryNetworkTask(taskInfo)
                    }
                    if let error = error {
                        processor(apiTask, .error(task.response, error), taskInfo.attempt, retry)
                    } else if let response = task.response {
                        processor(apiTask, .success(response, taskInfo.data as Data? ?? Data()), taskInfo.attempt, retry)
                    } else {
                        // this should be unreachable
                        let userInfo = [NSLocalizedDescriptionKey: "internal error: task response was nil with no error"]
                        processor(apiTask, .error(nil, NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: userInfo)), taskInfo.attempt, retry)
                    }
                }
            } else {
                assert(result.oldState == .canceled, "internal HTTPManager error: tried to process task that's already completed")
                // We must have canceled concurrently with the networking portion finishing
                queue.async {
                    processor(apiTask, .canceled, taskInfo.attempt, { _ in return false })
                }
            }
        }
    }
    
    private static let cacheControlValues: Set<CaseInsensitiveASCIIString> = ["no-cache", "no-store", "max-age", "s-maxage"]
    
    @objc func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {
        guard var taskInfo = tasks[dataTask.taskIdentifier] else {
            log("willCacheResponse; ignoring, task \(dataTask) not tracked")
            completionHandler(proposedResponse)
            return
        }
        assert(taskInfo.task.networkTask === dataTask, "internal HTTPManager error: taskInfo out of sync")
        log("willCacheResponse for task \(dataTask)")
        func hasCachingHeaders(_ response: URLResponse) -> Bool {
            guard let response = response as? HTTPURLResponse else { return false }
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
        case (.allowedInMemoryOnly, .allowed):
            if hasCachingHeaders(proposedResponse.response) {
                completionHandler(proposedResponse)
            } else {
                completionHandler(CachedURLResponse(response: proposedResponse.response, data: proposedResponse.data, userInfo: proposedResponse.userInfo, storagePolicy: .allowedInMemoryOnly))
            }
        case (.notAllowed, .allowed), (.notAllowed, .allowedInMemoryOnly):
            if hasCachingHeaders(proposedResponse.response) {
                completionHandler(proposedResponse)
            } else {
                completionHandler(nil)
            }
        default:
            completionHandler(proposedResponse)
        }
    }

    @objc func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let taskInfo = tasks[task.taskIdentifier] else {
            log("willPerformHTTPRedirection; ignoring, task \(task) not tracked")
            completionHandler(request)
            return
        }
        assert(taskInfo.task.networkTask === task, "internal HTTPManager error: taskInfo out of sync")
        log("willPerformHTTPRedirection for task \(task)")
        if taskInfo.task.followRedirects {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
    
    @objc func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        guard let taskInfo = tasks[task.taskIdentifier] else {
            log("needNewBodyStream; ignoring, task \(task) not tracked")
            completionHandler(nil)
            return
        }
        assert(taskInfo.task.networkTask === task, "internal HTTPManager error: taskInfo out of sync")
        log("needNewBodyStream for task \(task)")
        switch taskInfo.uploadBody {
        case .data(let data)?:
            log("providing stream for Data")
            completionHandler(InputStream(data: data))
        case .formUrlEncoded(let queryItems)?:
            DispatchQueue.global(qos: taskInfo.task.userInitiated ? .userInitiated : .utility).async {
                #if enableDebugLogging
                    self.log("providing stream for FormUrlEncoded")
                #endif
                completionHandler(InputStream(data: UploadBody.dataRepresentationForQueryItems(queryItems)))
            }
        case .json(let json)?:
            DispatchQueue.global(qos: taskInfo.task.userInitiated ? .userInitiated : .utility).async {
                #if enableDebugLogging
                    self.log("providing stream for JSON")
                #endif
                completionHandler(InputStream(data: JSON.encodeAsData(json, pretty: false)))
            }
        case let .multipartMixed(boundary, parameters, bodyParts)?:
            if bodyParts.contains(where: { if case .pending = $0 { return true } else { return false } }) {
                // We have at least one Pending value, we need to wait for them to evaluate (otherwise we can't
                // accurately implement the `canRead` stream callback) so we'll do it asynchronously.
                let group = DispatchGroup()
                let qos: DispatchQoS = taskInfo.task.userInitiated ? .userInitiated : .utility
                for case .pending(let deferred) in bodyParts {
                    group.enter()
                    deferred.async(qos) { _ in
                        group.leave()
                    }
                }
                log("delaying until body parts have been evaluated")
                group.notify(queue: DispatchQueue.global(qos: qos.qosClass)) {
                    // All our Pending values have been evaluated.
                    #if enableDebugLogging
                        self.log("providing stream for MultipartMixed")
                    #endif
                    completionHandler(HTTPBody.createMultipartMixedStream(boundary, parameters: parameters, bodyParts: bodyParts))
                }
            } else {
                // All our values have been evaluated already, no need to wait.
                log("providing stream for MultipartMixed")
                completionHandler(HTTPBody.createMultipartMixedStream(boundary, parameters: parameters, bodyParts: bodyParts))
            }
        case nil:
            self.log("no uploadBody, providing no stream")
            completionHandler(nil)
        }
    }
}
