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
    
    /// The underlying `URLSessionTask`.
    ///
    /// If a failed request is automatically retried, this property value
    /// will change.
    ///
    /// - Note: This property supports key-value observing.
    public var networkTask: URLSessionTask {
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
    
    /// The `HTTPAuth` used to authenticate the request, if any.
    public let auth: HTTPAuth?
    
    /// The current state of the task.
    /// - Note: This property is thread-safe and may be accessed concurrently.
    /// - Note: This property supports KVO. The KVO notifications will execute
    ///   on an arbitrary thread.
    public var state: State {
        return State(_stateBox.state)
    }
    
    @objc public override class func automaticallyNotifiesObservers(forKey _: String) -> Bool {
        return false
    }
    
    /// Invokes `resume()` on the underlying `URLSessionTask`.
    ///
    /// - Important: You should always use this method instead of invoking `resume()`
    ///   on the `networkTask`.
    ///
    /// - Note: To suspend the underlying task you can access it with the
    ///   `networkTask` property. However, suspending the task will not remove it from
    ///   the list of outstanding tasks used to control the network activity indicator.
    public func resume() {
        if affectsNetworkActivityIndicator {
            // We need to hop onto our session delegate queue in order to inspect our state,
            // otherwise we might show the activity indicator after we've transitioned out of running.
            // We can't check it here because that leads to a race condition between this thread and
            // the session delegate queue. But we know that all transitions into and out of the Running
            // state happen on that queue, so we can safely inspect the state there.
            sessionDelegateQueue.addOperation {
                if self.state == .running {
                    self.setTrackingNetworkActivity()
                }
            }
        }
        networkTask.resume()
    }
    
    /// Use `networkTask.suspend()` instead.
    @available(*, unavailable, message: "use networkTask.suspend() instead")
    @nonobjc
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
    /// Calling this on a task that's already moved to `.completed` is a no-op.
    public func cancel() {
        // NB: We don't call _cancel() because we want our KVO notifications to wrap the network
        // task cancellation too.
        willChangeValue(forKey: "state")
        defer { didChangeValue(forKey: "state") }
        let result = _stateBox.transitionState(to: .canceled)
        if result.completed && result.oldState != .canceled {
            networkTask.cancel()
        }
    }
    
    /// Cancels the HTTPManagerTask without canceling the underlying network task.
    /// - Returns: `true` if the task could be canceled.
    internal func _cancel() -> Bool {
        willChangeValue(forKey: "state")
        defer { didChangeValue(forKey: "state") }
        let result = _stateBox.transitionState(to: .canceled)
        return result.completed && result.oldState != .canceled
    }
    
    internal let userInitiated: Bool
    internal let followRedirects: Bool
    internal let assumeErrorsAreJSON: Bool
    internal let defaultResponseCacheStoragePolicy: URLCache.StoragePolicy
    internal let retryBehavior: HTTPManagerRetryBehavior?
    internal let affectsNetworkActivityIndicator: Bool
    private let sessionDelegateQueue: OperationQueue
    
    internal init(networkTask: URLSessionTask, request: HTTPManagerRequest, sessionDelegateQueue: OperationQueue) {
        _stateBox = _PMHTTPManagerTaskStateBox(state: State.running.boxState, networkTask: networkTask)
        isIdempotent = request.isIdempotent
        auth = request.auth
        userInitiated = request.userInitiated
        followRedirects = request.shouldFollowRedirects
        assumeErrorsAreJSON = request.assumeErrorsAreJSON
        defaultResponseCacheStoragePolicy = request.defaultResponseCacheStoragePolicy
        retryBehavior = request.retryBehavior
        affectsNetworkActivityIndicator = request.affectsNetworkActivityIndicator
        self.sessionDelegateQueue = sessionDelegateQueue
        super.init()
    }
    
    deinit {
        // clear associated objects now so that way KVO libraries that use associated objects
        // can deregister before we release our properties
        objc_removeAssociatedObjects(self)
    }
    
    internal func transitionState(to newState: State) -> (ok: Bool, oldState: State) {
        willChangeValue(forKey: "state")
        defer { didChangeValue(forKey: "state") }
        let result = _stateBox.transitionState(to: newState.boxState)
        return (result.completed, State(result.oldState))
    }
    
    /// Resets the state back to `.running` and replaces the `networkTask` property with
    /// a new value. If the state cannot be transitioned back to `.running` the `networkTask`
    /// property is not modified.
    /// - Parameter networkTask: The new `URLSessionTask` to use for the `networkTask` property.
    /// - Returns: A tuple where `ok` is `true` if the task was reset, otherwise `false`, and `oldState`
    ///   describes the state the task was in when the transition was attempted.
    internal func resetStateToRunning(with networkTask: URLSessionTask) -> (ok: Bool, oldState: State) {
        willChangeValue(forKey: "state")
        willChangeValue(forKey: "networkTask")
        defer {
            didChangeValue(forKey: "networkTask")
            didChangeValue(forKey: "state")
        }
        let result = _stateBox.transitionState(to: State.running.boxState)
        if result.completed {
            _stateBox.networkTask = networkTask
        }
        return (result.completed, State(result.oldState))
    }
    
    /// Sets the tracking network activity flag and increments the `NetworkActivityManager` counter
    /// if the flag wasn't previously set.
    internal func setTrackingNetworkActivity() {
        if !_stateBox.setTrackingNetworkActivity() {
            NetworkActivityManager.shared.incrementCounter()
        }
    }
    
    /// Clears the tracking network activity flag and decrements the `NetworkActivityManager` counter
    /// if the flag was previously set.
    internal func clearTrackingNetworkActivity() {
        if _stateBox.clearTrackingNetworkActivity() {
            NetworkActivityManager.shared.decrementCounter()
        }
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
    
    private func getDescription(_ debug: Bool) -> String {
        // FIXME: Use ObjectIdentifier.address or whatever it's called when it's available
        #if swift(>=3.1)
            let ptr = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        #else
            let ptr = unsafeBitCast(Unmanaged.passUnretained(self).toOpaque(), to: UInt.self)
        #endif
        var s = "<HTTPManagerTask: 0x\(String(ptr, radix: 16)) (\(state))"
        if let auth = auth {
            let desc = debug ? String(reflecting: auth) : String(describing: auth)
            s += " auth=\(desc)"
        }
        if userInitiated {
            s += " userInitiated"
        }
        if followRedirects {
            s += " followRedirects"
        }
        if affectsNetworkActivityIndicator {
            s += " affectsNetworkActivityIndicator"
        }
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
    case running = 0
    /// The task is processing results (e.g. parsing JSON).
    case processing = 1
    /// The task has been canceled. The completion handler may or may not
    /// have been invoked yet.
    case canceled = 2
    /// The task has completed. The completion handler may or may not have
    /// been invoked yet.
    case completed = 3
    
    public var description: String {
        switch self {
        case .running: return "Running"
        case .processing: return "Processing"
        case .canceled: return "Canceled"
        case .completed: return "Completed"
        }
    }
    
    fileprivate init(_ boxState: _PMHTTPManagerTaskStateBoxState) {
        self = unsafeBitCast(boxState, to: HTTPManagerTaskState.self)
    }
    
    fileprivate var boxState: _PMHTTPManagerTaskStateBoxState {
        return unsafeBitCast(self, to: _PMHTTPManagerTaskStateBoxState.self)
    }
}

// MARK: - HTTPManagerTaskResult

/// The results of an HTTP request.
public enum HTTPManagerTaskResult<Value> {
    /// The task finished successfully.
    case success(URLResponse, Value)
    /// An error occurred, either during networking or while processing the
    /// data.
    ///
    /// The `Error` may be any error type returned by `URLSession`,
    /// `HTTPManagerError` for errors returned by this class, or any error type
    /// thrown by a parse handler (including JSON errors returned by `PMJSON`).
    case error(URLResponse?, Error)
    /// The task was canceled before it completed.
    case canceled
    
    /// Returns the `Value` from a successful task result, otherwise returns `nil`.
    public var success: Value? {
        switch self {
        case .success(_, let value): return value
        default: return nil
        }
    }
    
    /// Returns the `URLResponse` from a successful task result. For errored results,
    /// if the error includes a response, the response is returned. Otherwise,
    /// returns `nil`.
    public var urlResponse: URLResponse? {
        switch self {
        case .success(let response, _): return response
        case .error(let response, _): return response
        case .canceled: return nil
        }
    }
    
    /// Returns the `Value` from a successful task result, otherwise returns `nil`.
    public var value: Value? {
        switch self {
        case .success(_, let value): return value
        default: return nil
        }
    }
    
    /// Returns the `ErrorType` from an errored task result, otherwise returns `nil`.
    public var error: Error? {
        switch self {
        case .error(_, let error): return error
        default: return nil
        }
    }
    
    /// Returns `true` iff `self` is `.success`.
    public var isSuccess: Bool {
        switch self {
        case .success: return true
        default: return false
        }
    }
    
    /// Returns `true` iff `self` is `.error`.
    public var isError: Bool {
        switch self {
        case .error: return true
        default: return false
        }
    }
    
    /// Returns `true` iff `self` is `.canceled`.
    public var isCanceled: Bool {
        switch self {
        case .canceled: return true
        default: return false
        }
    }
    
    /// Maps a successful task result through the given block.
    /// Errored and canceled results are returned as they are.
    public func map<T>(_ f: (URLResponse, Value) throws -> T) rethrows -> HTTPManagerTaskResult<T> {
        switch self {
        case let .success(response, value): return .success(response, try f(response, value))
        case let .error(response, type): return .error(response, type)
        case .canceled: return .canceled
        }
    }
    
    /// Maps a successful task result through the given block.
    /// Errored and canceled results are returned as they are.
    /// Errors thrown by the block are caught and turned into `.error` results.
    public func map<T>(try f: (URLResponse, Value) throws -> T) -> HTTPManagerTaskResult<T> {
        switch self {
        case let .success(response, value):
            do {
                return .success(response, try f(response, value))
            } catch {
                return .error(response, error)
            }
        case let .error(response, type): return .error(response, type)
        case .canceled: return .canceled
        }
    }
    
    /// Maps a successful task result through the given block.
    /// Errored and canceled results are returned as they are.
    public func andThen<T>(_ f: (URLResponse, Value) throws -> HTTPManagerTaskResult<T>) rethrows -> HTTPManagerTaskResult<T> {
        switch self {
        case let .success(response, value): return try f(response, value)
        case let .error(response, type): return .error(response, type)
        case .canceled: return .canceled
        }
    }
    
    /// Maps a successful task result through the given block.
    /// Errored and canceled results are returned as they are.
    /// Errors thrown by the block are caught and turned into `.error` results.
    public func andThen<T>(try f: (URLResponse, Value) throws -> HTTPManagerTaskResult<T>) -> HTTPManagerTaskResult<T> {
        switch self {
        case let .success(response, value):
            do {
                return try f(response, value)
            } catch {
                return .error(response, error)
            }
        case let .error(response, type): return .error(response, type)
        case .canceled: return .canceled
        }
    }
}

extension HTTPManagerTaskResult : CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .success(response, value):
            return "success(\(response), \(String(reflecting: value)))"
        case let .error(response, error):
            return "error(\(response.map(String.init(describing:)) ?? "nil"), \(String(reflecting: error)))"
        case .canceled:
            return "canceled"
        }
    }
}

public func ??<Value>(result: HTTPManagerTaskResult<Value>, defaultValue: @autoclosure () throws -> HTTPManagerTaskResult<Value>) rethrows -> HTTPManagerTaskResult<Value> {
    switch result {
    case .success: return result
    default: return try defaultValue()
    }
}

public func ??<Value>(result: HTTPManagerTaskResult<Value>, defaultValue: @autoclosure () throws -> Value) rethrows -> Value {
    switch result {
    case .success(_, let value): return value
    default: return try defaultValue()
    }
}
