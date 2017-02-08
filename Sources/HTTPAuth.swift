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
