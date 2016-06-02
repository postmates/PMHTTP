//
//  HTTPManagerTask.swift
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
import PMHTTP.Private

/// An initiated HTTP operation.
///
/// **Thread safety:** All methods in this class are safe to call from any thread.
public final class HTTPManagerTask: NSObject {
    public typealias State = HTTPManagerTaskState
    
    /// The underlying `NSURLSessionTask`.
    ///
    /// If a failed request is automatically retried, this property value
    /// will change.
    ///
    /// - Note: This property supports key-value observing.
    public var networkTask: NSURLSessionTask {
        get { return _stateBox.networkTask }
    }
    
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
    /// error dialog.
    @nonobjc public let isIdempotent: Bool
    
    /// The `NSURLCredential` used to authenticate the request, if any.
    public let credential: NSURLCredential?
    
    /// The current state of the task.
    /// - Note: This property is thread-safe and may be accessed concurrently.
    /// - Note: This property supports KVO. The KVO notifications will execute
    ///   on an arbitrary thread.
    public var state: State {
        return State(_stateBox.state)
    }
    
    @objc public override class func automaticallyNotifiesObserversForKey(_: String) -> Bool {
        return false
    }
    
    /// Invokes `resume()` on the underlying `NSURLSessionTask`.
    /// - Note: To suspend the underlying task you can access it with the
    ///   `networkTask` property.
    public func resume() {
        networkTask.resume()
    }
    
    /// Use `networkTask.suspend()` instead.
    @available(*, unavailable, message="use networkTask.suspend() instead")
    public func suspend() {}
    
    // NB: We don't expose a suspend() method here because that would produce surprising
    // behavior in the face of automatic retries. If the user calls suspend() while the
    // HTTP manager is in the process of handling the failure, the retry will be resumed
    // automatically, which would be surprising to the user. Requiring the user to call
    // suspend() on the underlying networkTask solves this issue as the underlying
    // networkTask changes on retries (and therefore it's not surprising that suspending
    // the old networkTask has no effect on the new one).
    
    /// Cancels the operation, if it hasn't already completed.
    ///
    /// If the operation is still talking to the network, the underlying network
    /// task is canceled. If the operation is processing the results, the
    /// results processor is canceled at the earliest opportunity.
    ///
    /// Calling this on a task that's already moved to `.Completed` is a no-op.
    public func cancel() {
        willChangeValueForKey("state")
        defer { didChangeValueForKey("state") }
        let result = _stateBox.transitionStateTo(.Canceled)
        if result.completed && result.oldState != .Canceled {
            networkTask.cancel()
        }
    }
    
    internal let userInitiated: Bool
    internal let followRedirects: Bool
    internal let defaultResponseCacheStoragePolicy: NSURLCacheStoragePolicy
    internal let retryBehavior: HTTPManagerRetryBehavior?
    #if os(iOS)
    internal let trackingNetworkActivity: Bool
    #endif
    
    internal init(networkTask: NSURLSessionTask, request: HTTPManagerRequest) {
        _stateBox = _PMHTTPManagerTaskStateBox(state: State.Running.boxState, networkTask: networkTask)
        isIdempotent = request.isIdempotent
        credential = request.credential
        userInitiated = request.userInitiated
        followRedirects = request.shouldFollowRedirects
        defaultResponseCacheStoragePolicy = request.defaultResponseCacheStoragePolicy
        retryBehavior = request.retryBehavior
        #if os(iOS)
            trackingNetworkActivity = request.affectsNetworkActivityIndicator
        #endif
        super.init()
    }
    
    internal func transitionStateTo(newState: State) -> (ok: Bool, oldState: State) {
        willChangeValueForKey("state")
        defer { didChangeValueForKey("state") }
        let result = _stateBox.transitionStateTo(newState.boxState)
        return (result.completed, State(result.oldState))
    }
    
    /// Resets the state back to `.Running` and replaces the `networkTask` property with
    /// a new value. If the state cannot be transitioned back to `.Running` the `networkTask`
    /// property is not modified.
    /// - Parameter networkTask: The new `NSURLSessionTask` to use for the `networkTask` property.
    /// - Returns: A tuple where `ok` is `true` if the task was reset, otherwise `false`, and `oldState`
    ///   describes the state the task was in when the transition was attempted.
    internal func resetStateToRunningWithNetworkTask(networkTask: NSURLSessionTask) -> (ok: Bool, oldState: State) {
        willChangeValueForKey("state")
        willChangeValueForKey("networkTask")
        defer {
            didChangeValueForKey("networkTask")
            didChangeValueForKey("state")
        }
        let result = _stateBox.transitionStateTo(State.Running.boxState)
        if result.completed {
            _stateBox.networkTask = networkTask
        }
        return (result.completed, State(result.oldState))
    }
    
    private let _stateBox: _PMHTTPManagerTaskStateBox
}

extension HTTPManagerTask {
    // NSObject already conforms to CustomStringConvertible and CustomDebugStringConvertible
    
    public override var description: String {
        return getDescription(false)
    }
    
    public override var debugDescription: String {
        return getDescription(true)
    }
    
    private func getDescription(debug: Bool) -> String {
        var s = "<HTTPManagerTask: 0x\(String(unsafeBitCast(unsafeAddressOf(self), UInt.self), radix: 16)) (\(state))"
        if let user = credential?.user {
            s += " user=\(String(reflecting: user))"
        }
        if userInitiated {
            s += " userInitiated"
        }
        if followRedirects {
            s += " followRedirects"
        }
        #if os(iOS)
            if trackingNetworkActivity {
                s += " trackingNetworkActivity"
            }
        #endif
        if debug {
            s += " networkTask=\(networkTask)"
        }
        s += ">"
        return s
    }
}

// MARK: HTTPManagerTaskState

/// The state of an `HTTPManagerTask`.
@objc public enum HTTPManagerTaskState: CUnsignedChar, CustomStringConvertible {
    // Important: The constants here must match those defined in _PMHTTPManagerTaskStateBoxState
    
    /// The task is currently running.
    case Running = 0
    /// The task is processing results (e.g. parsing JSON).
    case Processing = 1
    /// The task has been canceled. The completion handler may or may not
    /// have been invoked yet.
    case Canceled = 2
    /// The task has completed. The completion handler may or may not have
    /// been invoked yet.
    case Completed = 3
    
    public var description: String {
        switch self {
        case .Running: return "Running"
        case .Processing: return "Processing"
        case .Canceled: return "Canceled"
        case .Completed: return "Completed"
        }
    }
    
    private init(_ boxState: _PMHTTPManagerTaskStateBoxState) {
        self = unsafeBitCast(boxState, HTTPManagerTaskState.self)
    }
    
    private var boxState: _PMHTTPManagerTaskStateBoxState {
        return unsafeBitCast(self, _PMHTTPManagerTaskStateBoxState.self)
    }
}

// MARK: - HTTPManagerTaskResult

/// The results of an HTTP request.
public enum HTTPManagerTaskResult<Value> {
    /// The task finished successfully.
    case Success(NSURLResponse, Value)
    /// An error occurred, either during networking or while processing the
    /// data.
    ///
    /// The `ErrorType` may be `NSError` for errors returned by `NSURLSession`,
    /// `HTTPManagerError` for errors returned by this class, or any error type
    /// thrown by a parse handler (including JSON errors returned by `PMJSON`).
    case Error(NSURLResponse?, ErrorType)
    /// The task was canceled before it completed.
    case Canceled
    
    /// Returns the `Value` from a successful task result, otherwise returns `nil`.
    public var success: Value? {
        switch self {
        case .Success(_, let value): return value
        default: return nil
        }
    }
    
    /// Returns the `NSURLResponse` from a successful task result. For errored results,
    /// if the error includes a response, the response is returned. Otherwise,
    /// returns `nil`.
    public var URLResponse: NSURLResponse? {
        switch self {
        case .Success(let response, _): return response
        case .Error(let response, _): return response
        case .Canceled: return nil
        }
    }
    
    /// Returns the `ErrorType` from an errored task result, otherwise returns `nil`.
    public var error: ErrorType? {
        switch self {
        case .Error(_, let error): return error
        default: return nil
        }
    }
    
    /// Returns `true` iff `self` is `.Success`.
    public var isSuccess: Bool {
        switch self {
        case .Success: return true
        default: return false
        }
    }
    
    /// Returns `true` iff `self` is `.Error`.
    public var isError: Bool {
        switch self {
        case .Error: return true
        default: return false
        }
    }
    
    /// Returns `true` iff `self` is `.Canceled`.
    public var isCanceled: Bool {
        switch self {
        case .Canceled: return true
        default: return false
        }
    }
    
    /// Maps a successful task result through the given block.
    /// Errored and canceled results are returned as they are.
    public func map<T>(@noescape f: (NSURLResponse, Value) throws -> T) rethrows -> HTTPManagerTaskResult<T> {
        switch self {
        case let .Success(response, value): return .Success(response, try f(response, value))
        case let .Error(response, type): return .Error(response, type)
        case .Canceled: return .Canceled
        }
    }
    
    /// Maps a successful task result through the given block.
    /// Errored and canceled results are returned as they are.
    /// Errors thrown by the block are caught and turned into `.Error` results.
    public func map<T>(@noescape `try` f: (NSURLResponse, Value) throws -> T) -> HTTPManagerTaskResult<T> {
        switch self {
        case let .Success(response, value):
            do {
                return .Success(response, try f(response, value))
            } catch {
                return .Error(response, error)
            }
        case let .Error(response, type): return .Error(response, type)
        case .Canceled: return .Canceled
        }
    }
    
    /// Maps a successful task result through the given block.
    /// Errored and canceled results are returned as they are.
    public func andThen<T>(@noescape f: (NSURLResponse, Value) throws -> HTTPManagerTaskResult<T>) rethrows -> HTTPManagerTaskResult<T> {
        switch self {
        case let .Success(response, value): return try f(response, value)
        case let .Error(response, type): return .Error(response, type)
        case .Canceled: return .Canceled
        }
    }
    
    /// Maps a successful task result through the given block.
    /// Errored and canceled results are returned as they are.
    /// Errors thrown by the block are caught and turned into `.Error` results.
    public func andThen<T>(@noescape `try` f: (NSURLResponse, Value) throws -> HTTPManagerTaskResult<T>) -> HTTPManagerTaskResult<T> {
        switch self {
        case let .Success(response, value):
            do {
                return try f(response, value)
            } catch {
                return .Error(response, error)
            }
        case let .Error(response, type): return .Error(response, type)
        case .Canceled: return .Canceled
        }
    }
}

extension HTTPManagerTaskResult : CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .Success(response, value):
            return "Success(\(response), \(String(reflecting: value)))"
        case let .Error(response, error):
            return "Error(\(response), \(String(reflecting: error)))"
        case .Canceled:
            return "Canceled"
        }
    }
}

public func ??<Value>(result: HTTPManagerTaskResult<Value>, @autoclosure defaultValue: () throws -> HTTPManagerTaskResult<Value>) rethrows -> HTTPManagerTaskResult<Value> {
    switch result {
    case .Success: return result
    default: return try defaultValue()
    }
}

public func ??<Value>(result: HTTPManagerTaskResult<Value>, @autoclosure defaultValue: () throws -> Value) rethrows -> Value {
    switch result {
    case .Success(_, let value): return value
    default: return try defaultValue()
    }
}
