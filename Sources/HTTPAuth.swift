//
//  HTTPAuth.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 2/7/17.
//  Copyright © 2017 Postmates. All rights reserved.
//

import Foundation

/// The `HTTPAuth` protocol defines the common interface that authentication mechanisms can use.
/// This includes the ability to set headers and to handle authorization failures.
@objc public protocol HTTPAuth {
    /// Returns the headers that should be added to the given request.
    ///
    /// This is most commonly used to set the `"Authorization"` header.
    ///
    /// - Note: This method may be called from any thread.
    ///
    /// - Note: `HTTPAuth` is not allowed to set `"Content-Type"`, `"Content-Length"`, or
    ///   `"Accept"`, and any attempt to do so will be ignored.
    ///
    /// - Parameter request: The `URLRequest` that the headers should be added to.
    @objc(headersForRequest:)
    func headers(for request: URLRequest) -> [String: String]
    
    /// Returns an opaque token that is associated with the request.
    ///
    /// If implemented, this method is called immediately after` headers(for:)`.
    ///
    /// - Note: This method is not guaranteed to be called every time `headers(for:)` is. Notably,
    ///   when `preparedURLRequest` is accessed, `headers(for:)` will be invoked but not
    ///   `opaqueToken(for:)`.
    ///
    /// This token can be used to uniquely identify the authorization information used for the
    /// request. Then in `handleUnauthorized(_:for:token:completion:)` you can use this token to
    /// determine if you've already refreshed your stored authorization information or if you need
    /// to do extra work (such as fetching a new OAuth2 token) before you can retry the request.
    @objc(opaqueTokenForRequest:)
    optional func opaqueToken(for request: URLRequest) -> Any?
    
    /// Invoked when a 401 Unauthorized response is received.
    ///
    /// This method is only called once per request. If this method is invoked and requests a retry,
    /// and the subsequent retry fails due to 401 Unauthorized, this is considered a permanent
    /// failure.
    ///
    /// - Note: This method will be called on an arbitrary background thread.
    ///
    /// - Note: Special care must be taken when implementing this method. Multiple tasks may be
    ///   created with the same authorization headers in parallel and may all fail even after you've
    ///   refreshed your authorization information (e.g. with OAuth2). You can use
    ///   `opaqueToken(for:)` in order to keep track of whether a given request was created with old
    ///   authorization information or whether you need to refresh your authorization information.
    ///
    /// - Important: The completion block **MUST** be called once and only once. Failing to call the
    ///   completion block will leave the task stuck in the processing state forever. Calling the
    ///   completion block multiple times may cause bad behavior.
    ///
    /// - Note: When the completion block is invoked, if the task is not retried, the task's own
    ///   completion block may run synchronously on the current queue.
    ///
    /// - Parameter response: The `HTTPURLResponse` that was received.
    /// - Parameter body: The body that was received.
    /// - Parameter task: The `HTTPManagerTask` that received the response.
    /// - Parameter token: The opaque token returned from `opaqueToken(for:)`, otherwise `nil`.
    /// - Parameter completion: A completion block that must be called when the `HTTPAuth` object
    ///   has finished handling the response. This block may be called synchronously, or it may be called from any thread.
    @objc(handleUnauthorizedResponse:body:forTask:token:completion:)
    optional func handleUnauthorized(_ response: HTTPURLResponse, body: Data, for task: HTTPManagerTask, token: Any?, completion: @escaping (_ retry: Bool) -> Void)
    
    /// Returns the localized description for an unauthorized error.
    ///
    /// - Parameter error: The unauthorized error. This will always be an instance of
    ///   `HTTPManagerError.unauthorized`.
    /// - Returns: The string to use for the localized description, or `nil` to use the default
    ///   description.
    @objc(localizedDescriptionForError:)
    optional func localizedDescription(for error: Error) -> String?
}

internal extension HTTPAuth {
    func applyHeaders(to request: inout URLRequest) {
        for (key, value) in headers(for: request) {
            switch key {
            case "Content-Type", "Content-Length", "Accept": break
            default: request.setValue(value, forHTTPHeaderField: key)
            }
        }
    }
}

/// An `HTTPAuth` implementation that provides basic auth.
public final class HTTPBasicAuth: NSObject, HTTPAuth {
    /// The `URLCredential` that the `HTTPBasicAuth` was initialized with.
    ///
    /// This is guaranteed to be a password-based credential.
    public let credential: URLCredential
    
    public override var description: String {
        return "<HTTPBasicAuth: user=\(credential.user ?? "")\(credential.hasPassword ? "" : " (no password)")>"
    }
    
    public override var debugDescription: String {
        return "<HTTPBasicAuth: credential=\(String(reflecting: credential))>"
    }
    
    /// Returns a new instance of `HTTPBasicAuth` from a given password-based credential.
    ///
    /// - Parameter credential: A `URLCredential`. This must be a password-based credential.
    /// - Returns: An `HTTPBasicAuth` instance, or `nil` if `credential` isn't a password-based
    ///   credential.
    public init?(credential: URLCredential) {
        guard credential.user != nil && credential.hasPassword else {
            NSLog("[HTTPManager] Warning: Attempting to create an HTTPBasicAuth with a non-password-based credential")
            return nil
        }
        self.credential = credential
        super.init()
    }
    
    /// Returns a new instance of `HTTPBasicAuth` with the given username and password.
    ///
    /// - Note: The `URLCredential` that this creates has a persistence of `.none`.
    ///
    /// - Parameter username: The username to use.
    /// - Parameter password: The password to use.
    /// - Returns: An `HTTPBasicAuth` instance.
    public init(username: String, password: String) {
        credential = URLCredential(user: username, password: password, persistence: .none)
        super.init()
    }
    
    public func headers(for request: URLRequest) -> [String : String] {
        let phrase = "\(credential.user ?? ""):\(credential.password ?? "")"
        guard let data = phrase.data(using: String.Encoding.utf8) else {
            assertionFailure("unexpected failure converting basic auth phrase to utf-8")
            return [:]
        }
        let encoded = data.base64EncodedString()
        return ["Authorization": "Basic \(encoded)"]
    }
}

/// The base class for `HTTPAuth` implementations that refresh their authentication automatically.
///
/// This class provides support for refreshing authentication information, e.g. for OAuth2 token
/// refresh. It is recommended that you subclass this class in order to provide your own
/// initializer.
///
/// - Note: This class assumes that each instance manages a single authentication realm, and makes
///   no provision for refreshing authentication for multiple realms simultaneously.
open class HTTPRefreshableAuth: NSObject, HTTPAuth {
    /// Returns a new `HTTPRefreshableAuth`.
    ///
    /// - Parameter info: A value that is used to calculate authentication headers and refresh
    ///   authentication information. This parameter may have any type, as long as it's thread-safe.
    /// - Parameter authenticationHeadersBlock: A block that is used to return the authentication
    ///   headers for a request. The `info` parameter is provided to this block.
    ///
    ///   This block may be called from any thread.
    /// - Parameter authenticationRefreshBlock: A block that is invoked in response to a 401
    ///   Unauthorized response in order to refresh the authentication information. This block will
    ///   not be invoked multiple times concurrent with each other. Any requests that fail while
    ///   refreshing will use the results of the outstanding refresh.
    ///
    ///   This block returns an optional `HTTPManagerTask`. If non-`nil`, the task will be tracked
    ///   and will be canceled if the `HTTPRefreshableAuth` is deinited.
    ///
    ///   This block may be called from any thread.
    ///
    ///   **Important:** Any request you create for refreshing the token should not have its `auth`
    ///   property set to this `HTTPRefreshableAuth` instance. Doing so will end up deadlocking the
    ///   request forever if the server returns a 401 Unauthorized response. The only exception is
    ///   if your subclass of `HTTPRefreshableAuth` detects this case and overrides
    ///   `handleUnauthorized(_:body:for:token:completion:)` and avoids calling `super`.
    ///
    ///   **Note:** If this `HTTPRefreshableAuth` instance is the `defaultAuth` for the
    ///   `HTTPManager`, any requests created from within the `authenticationRefreshBlock` will
    ///   automatically have their `auth` properties set to `nil` instead of inheriting the
    ///   `defaultAuth`.
    ///
    ///   The `completion` parameter to this block must be invoked with the results of the refresh.
    ///   The first parameter to this block is the new `info` value that represents the new
    ///   authentication information, or `nil` if there is no new info. The second parameter is a
    ///   boolean that indicates whether the refresh succeeded. If this parameter is `true` all
    ///   pending failed tasks are retried with the new info. If `false` all pending failed tasks
    ///   will complete with the error `HTTPManagerError.unauthorized`. The `completion` block may
    ///   be invoked from any thread, including being invoked synchronously from
    ///   `authenticationRefreshBlock`.
    public init<T>(info: T, authenticationHeadersBlock: @escaping (_ request: URLRequest, _ info: T) -> [String: String], authenticationRefreshBlock: @escaping (_ response: HTTPURLResponse, _ body: Data, _ info: T, _ completion: @escaping (_ info: T?, _ retry: Bool) -> Void) -> HTTPManagerTask?) {
        self.authenticationHeadersBlock = { authenticationHeadersBlock($0, $1 as! T) }
        self.authenticationRefreshBlock = { authenticationRefreshBlock($0, $1, $2 as! T, $3) }
        self.inner = QueueConfined(label: "HTTPRefreshableAuth private queue", value: Inner(info: info))
        super.init()
    }
    
    /// Returns a new `HTTPRefreshableAuth`.
    ///
    /// - Parameter info: A value that is used to calculate authentication headers and refresh
    ///   authentication information. This parameter may have any type, as long as it's thread-safe.
    /// - Parameter authenticationHeadersBlock: A block that is used to return the authentication
    ///   headers for a request. The `info` parameter is provided to this block.
    ///
    ///   This block may be called from any thread.
    /// - Parameter authenticationRefreshBlock: A block that is invoked in response to a 401
    ///   Unauthorized response in order to refresh the authentication information. This block will
    ///   not be invoked multiple times concurrent with each other. Any requests that fail while
    ///   refreshing will use the results of the outstanding refresh.
    ///
    ///   This block returns an optional `HTTPManagerTask`. If non-`nil`, the task will be tracked
    ///   and will be canceled if the `HTTPRefreshableAuth` is deinited.
    ///
    ///   This block may be called from any thread.
    ///
    ///   The `completion` parameter to this block must be invoked with the results of the refresh.
    ///   The first parameter to this block is the new `info` value that represents the new
    ///   authentication information, or `nil` if there is no new info. The second parameter is a
    ///   boolean that indicates whether the refresh succeeded. If this parameter is `true` all
    ///   pending failed tasks are retried with the new info. If `false` all pending failed tasks
    ///   will complete with the error `HTTPManagerError.unauthorized`. The `completion` block may
    ///   be invoked from any thread, including being invoked synchronously from
    ///   `authenticationRefreshBlock`.
    @objc(initWithInfo:authenticationHeadersBlock:authenticationRefreshBlock:)
    public convenience init(__info info: Any, authenticationHeadersBlock: @escaping (_ request: URLRequest, _ info: Any) -> [String: String], authenticationRefreshBlock: @escaping (_ response: HTTPURLResponse, _ body: Data, _ info: Any, _ completion: @escaping (_ info: Any?, _ retry: Bool) -> Void) -> HTTPManagerTask?) {
        self.init(info: info, authenticationHeadersBlock: authenticationHeadersBlock, authenticationRefreshBlock: authenticationRefreshBlock)
    }
    
    public final func headers(for request: URLRequest) -> [String: String] {
        let info = inner.sync({ $0.info })
        return authenticationHeadersBlock(request, info)
    }
    
    public final func opaqueToken(for request: URLRequest) -> Any? {
        return inner.sync({ $0.currentToken })
    }
    
    /// Invoked when a 401 Unauthorized response is received.
    ///
    /// The default implementation refreshes the authentication information if necessary. If you
    /// override this method, you should call `super` unless you want to skip refreshing
    /// authentication information for any reason.
    open func handleUnauthorized(_ response: HTTPURLResponse, body: Data, for task: HTTPManagerTask, token: Any?, completion: @escaping (_ retry: Bool) -> Void) {
        guard let token = token as? Inner.Token else {
            // This shouldn't be reachable, but if it is, don't retry
            return completion(false)
        }
        
        let queue = DispatchQueue.global(qos: .userInitiated)
        inner.asyncBarrier { [weak self] inner in
            guard token === inner.currentToken else {
                // if the token is different, we already refreshed our credentials
                queue.async {
                    completion(true)
                }
                return
            }
            
            inner.completions.append(completion)
            guard inner.refreshToken === nil else { return }
            let refreshToken = Inner.Token()
            inner.refreshToken = refreshToken
            let info = inner.info
            queue.async {
                guard let this = self else { return }
                let task = HTTPManager.withoutDefaultAuth(this) {
                    return this.authenticationRefreshBlock(response, body, info, { (info, retry) in
                        guard let this = self else { return }
                        this.inner.asyncBarrier { [selfType=type(of: this)] inner in
                            guard inner.refreshToken === refreshToken else {
                                NSLog("[HTTPManager] HTTPRefreshableAuth authenticationRefreshBlock invoked multiple times (\(selfType))")
                                assertionFailure("HTTPRefreshableAuth authenticationRefreshBlock invoked multiple times")
                                return
                            }
                            inner.refreshToken = nil
                            inner.task = nil
                            if let info = info {
                                inner.info = info
                                inner.currentToken = Inner.Token()
                            }
                            let completions = inner.completions
                            inner.completions = []
                            queue.async {
                                DispatchQueue.concurrentPerform(iterations: completions.count, execute: { i in
                                    completions[i](retry)
                                })
                            }
                        }
                    })
                }
                this.inner.asyncBarrier { inner in
                    guard inner.refreshToken === refreshToken else { return }
                    inner.task = task
                }
            }
        }
    }
    
    private let authenticationHeadersBlock: (_ request: URLRequest, _ info: Any) -> [String: String]
    private let authenticationRefreshBlock: (_ response: HTTPURLResponse, _ body: Data, _ info: Any, _ completion: @escaping (_ info: Any?, _ retry: Bool) -> Void) -> HTTPManagerTask?
    private let inner: QueueConfined<Inner>
    
    private class Inner {
        init(info: Any) {
            self.info = info
        }
        
        var info: Any
        
        /// A class that exists only to be compared using `===`.
        class Token {}
        
        /// A token that identifies the authentication information.
        var currentToken = Token()
        /// A token that identifies the refresh attempt.
        var refreshToken: Token?
        var task: HTTPManagerTask?
        var completions: [(Bool) -> Void] = []
        
        
        deinit {
            task?.cancel()
            if !completions.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async { [completions] in
                    DispatchQueue.concurrentPerform(iterations: completions.count, execute: { i in
                        completions[i](false)
                    })
                }
            }
        }
    }
}
