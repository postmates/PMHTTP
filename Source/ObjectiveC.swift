//
//  ObjectiveC.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 12/31/15.
//  Copyright © 2015 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import PMJSON

// obj-c helpers
extension HTTPManager {
    /// The default `HTTPManager` instance.
    @objc(defaultManager) public static var __objc_defaultManager: HTTPManager {
        return HTTP
    }
    
    /// Creates a POST request.
    /// - Parameter path: The path for the request, interpreted relative to the
    ///   environment. May be an absolute URL.
    /// - Parameter json: The JSON-compatible object to upload as the body of the request.
    /// - Returns: An `HTTPManagerUploadJSONRequest`, or `nil` if the `path` cannot
    ///   be parsed by `NSURL` or `json` is not a JSON-compatible object.
    @objc(requestForPOST:json:)
    public func __objc_requestForPOST(path: String, json object: AnyObject) -> HTTPManagerUploadJSONRequest! {
        guard let json = try? JSON(ns: object) else { return nil }
        return request(POST: path, json: json)
    }
}

extension HTTPManagerError {
    /// Returns an `NSError` using the `PMHTTPError` constants for use by Objective-C.
    /// - Important: This is different than the `NSError` produced by casting the error using
    /// `error as NSError`, and cannot be casted back to `HTTPManagerError` using
    /// `nserror as? HTTPManagerError`.
    /// - Note: Errors that carry JSON payloads may have the payloads change when bridging to `NSError`.
    ///   In particular, null values will be stripped and JSON payloads where the top-level value is not an
    ///   object will be omitted.
    /// - SeeAlso: `init?(_ error:)`.
    public func toNSError() -> NSError {
        switch self {
        case let .FailedResponse(statusCode, response, body, json):
            let statusString = NSHTTPURLResponse.localizedStringForStatusCode(statusCode)
            var userInfo: [NSObject: AnyObject] = [
                NSLocalizedDescriptionKey: "HTTP response indicated failure (\(statusCode) \(statusString))",
                PMHTTPURLResponseErrorKey: response,
                PMHTTPStatusCodeErrorKey: statusCode,
                PMHTTPBodyDataErrorKey: body
            ]
            userInfo[PMHTTPBodyJSONErrorKey] = json?.object?.nsNoNull
            return NSError(domain: PMHTTPErrorDomain, code: PMHTTPError.FailedResponse.rawValue, userInfo: userInfo)
        case let .Unauthorized(credential, response, body, json):
            var userInfo: [NSObject: AnyObject] = [
                NSLocalizedDescriptionKey: "401 Unauthorized HTTP response",
                PMHTTPURLResponseErrorKey: response,
                PMHTTPBodyDataErrorKey: body
            ]
            userInfo[PMHTTPCredentialErrorKey] = credential
            userInfo[PMHTTPBodyJSONErrorKey] = json?.object?.nsNoNull
            return NSError(domain: PMHTTPErrorDomain, code: PMHTTPError.Unauthorized.rawValue, userInfo: userInfo)
        case let .UnexpectedContentType(contentType, response, body):
            return NSError(domain: PMHTTPErrorDomain, code: PMHTTPError.UnexpectedContentType.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "HTTP response had unexpected content type \(String(reflecting: contentType))",
                PMHTTPURLResponseErrorKey: response,
                PMHTTPContentTypeErrorKey: contentType,
                PMHTTPBodyDataErrorKey: body
                ])
        case let .UnexpectedNoContent(response):
            return NSError(domain: PMHTTPErrorDomain, code: PMHTTPError.UnexpectedNoContent.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "HTTP response returned 204 No Content when an entity was expected",
                PMHTTPURLResponseErrorKey: response
                ])
        case let .UnexpectedRedirect(statusCode, location, response, body):
            let statusString = NSHTTPURLResponse.localizedStringForStatusCode(statusCode)
            var userInfo = [
                NSLocalizedDescriptionKey: "HTTP response returned a redirection (\(statusCode) \(statusString)) when an entity was expected",
                PMHTTPURLResponseErrorKey: response,
                PMHTTPStatusCodeErrorKey: statusCode,
                PMHTTPBodyDataErrorKey: body
            ]
            userInfo[PMHTTPLocationErrorKey] = location
            return NSError(domain: PMHTTPErrorDomain, code: PMHTTPError.UnexpectedRedirect.rawValue, userInfo: userInfo)
        }
    }
    
    /// Returns an `HTTPManagerError` corresponding to the given `NSError` if the `NSError` was created
    /// by the ObjC variants of the `HTTPManager` methods.
    /// - Important: This is not the same thing as using `as?` to cast the `NSError` to `HTTPManagerError`.
    ///   The ObjC variants of the `HTTPManager` methods return an `NSError` that was not created by bridging
    ///   `HTTPManagerError` to `NSError` (because those errors aren't particularly usable from ObjC).
    /// - Note: Errors that carry JSON payloads may have the payloads change when bridging to `NSError` and back.
    ///   In particular, null values will be stripped and JSON payloads where the top-level value is not an
    ///   object will be omitted from the `NSError` version.
    /// - SeeAlso: `toNSError()`.
    public init?(_ error: NSError) {
        guard error.domain == PMHTTPErrorDomain, let code = PMHTTPError(rawValue: error.code) else { return nil }
        let userInfo = error.userInfo
        switch code {
        case .FailedResponse:
            guard let response = userInfo[PMHTTPURLResponseErrorKey] as? NSHTTPURLResponse,
                statusCode = userInfo[PMHTTPStatusCodeErrorKey] as? Int,
                body = userInfo[PMHTTPBodyDataErrorKey] as? NSData
                else { return nil }
            let json = userInfo[PMHTTPBodyJSONErrorKey].flatMap({try? JSON(ns: $0)})
            self = HTTPManagerError.FailedResponse(statusCode: statusCode, response: response, body: body, bodyJson: json)
        case .Unauthorized:
            guard let response = userInfo[PMHTTPURLResponseErrorKey] as? NSHTTPURLResponse,
                body = userInfo[PMHTTPBodyDataErrorKey] as? NSData
                else { return nil }
            let credential = userInfo[PMHTTPCredentialErrorKey] as? NSURLCredential
            let json = userInfo[PMHTTPBodyJSONErrorKey].flatMap({try? JSON(ns: $0)})
            self = HTTPManagerError.Unauthorized(credential: credential, response: response, body: body, bodyJson: json)
        case .UnexpectedContentType:
            guard let response = userInfo[PMHTTPURLResponseErrorKey] as? NSHTTPURLResponse,
                contentType = userInfo[PMHTTPContentTypeErrorKey] as? String,
                body = userInfo[PMHTTPBodyDataErrorKey] as? NSData
                else { return nil }
            self = HTTPManagerError.UnexpectedContentType(contentType: contentType, response: response, body: body)
        case .UnexpectedNoContent:
            guard let response = userInfo[PMHTTPURLResponseErrorKey] as? NSHTTPURLResponse
                else { return nil }
            self = HTTPManagerError.UnexpectedNoContent(response: response)
        case .UnexpectedRedirect:
            guard let response = userInfo[PMHTTPURLResponseErrorKey] as? NSHTTPURLResponse,
                statusCode = userInfo[PMHTTPStatusCodeErrorKey] as? Int,
                body = userInfo[PMHTTPBodyDataErrorKey] as? NSData
                else { return nil }
            let location = userInfo[PMHTTPLocationErrorKey] as? NSURL
            self = HTTPManagerError.UnexpectedRedirect(statusCode: statusCode, location: location, response: response, body: body)
        }
    }
}

extension HTTPManagerRetryBehavior {
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
    @objc(retryBehaviorWithHandler:)
    public convenience init(__handler handler: (task: HTTPManagerTask, error: NSError, attempt: Int, callback: Bool -> Void) -> Void) {
        self.init({ task, error, attempt, callback in
            switch error {
            case let error as HTTPManagerError:
                handler(task: task, error: error.toNSError(), attempt: attempt, callback: callback)
            default:
                handler(task: task, error: error as NSError, attempt: attempt, callback: callback)
            }
        })
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
    @objc(retryBehaviorIgnoringIdempotenceWithHandler:)
    public convenience init(__ignoringIdempotence handler: (task: HTTPManagerTask, error: NSError, attempt: Int, callback: Bool -> Void) -> Void) {
        self.init(ignoringIdempotence: { task, error, attempt, callback in
            switch error {
            case let error as HTTPManagerError:
                handler(task: task, error: error.toNSError(), attempt: attempt, callback: callback)
            default:
                handler(task: task, error: error as NSError, attempt: attempt, callback: callback)
            }
        })
    }
    
    /// Returns a retry behavior that retries once automatically for networking errors.
    ///
    /// A networking error is defined as many errors in the `NSURLErrorDomain`, or a
    /// `PMJSON.JSONParserError` with a code of `.UnexpectedEOF` (as this may indicate a
    /// truncated response). The request will not be retried for networking errors that
    /// are unlikely to change when retrying.
    ///
    /// If the request is non-idempotent, it only retries if the error indicates that a
    /// connection was never made to the server (such as cannot find host).
    ///
    /// - Parameter including503ServiceUnavailable: If `YES`, retries on a 503 Service Unavailable
    ///   response as well. Non-idempotent requests will also be retried on a 503 Service Unavailable
    ///   as the server did not handle the original request. If `NO`, only networking failures
    ///   are retried.
    @objc(retryNetworkFailureOnceIncluding503ServiceUnavailable:)
    public class func __retryNetworkFailureOnce(including503ServiceUnavailable: Bool) -> HTTPManagerRetryBehavior {
        if including503ServiceUnavailable {
            return HTTPManagerRetryBehavior.retryNetworkFailureOrServiceUnavailable(withStrategy: .retryOnce)
        } else {
            return HTTPManagerRetryBehavior.retryNetworkFailure(withStrategy: .retryOnce)
        }
    }
    
    /// Returns a retry behavior that retries twice automatically for networking errors.
    ///
    /// The first retry happens immediately, and the second retry happens after a given
    /// delay.
    ///
    /// A networking error is defined as many errors in the `NSURLErrorDomain`, or a
    /// `PMJSON.JSONParserError` with a code of `.UnexpectedEOF` (as this may indicate a
    /// truncated response). The request will not be retried for networking errors that
    /// are unlikely to change when retrying.
    ///
    /// If the request is non-idempotent, it only retries if the error indicates that a
    /// connection was never made to the server (such as cannot find host).
    ///
    /// - Parameter delay: The amount of time in seconds to wait before the second retry.
    /// - Parameter including503ServiceUnavailable: If `YES`, retries on a 503 Service Unavailable
    ///   response as well. Non-idempotent requests will also be retried on a 503 Service Unavailable
    ///   as the server did not handle the original request. If `NO`, only networking failures
    ///   are retried.
    @objc(retryNetworkFailureTwiceWithDelay:including503ServiceUnavailable:)
    public class func __retryNetworkFailureTwice(withDelay delay: NSTimeInterval, including503ServiceUnavailable: Bool) -> HTTPManagerRetryBehavior {
        if including503ServiceUnavailable {
            return HTTPManagerRetryBehavior.retryNetworkFailureOrServiceUnavailable(withStrategy: .retryTwiceWithDelay(delay))
        } else {
            return HTTPManagerRetryBehavior.retryNetworkFailure(withStrategy: .retryTwiceWithDelay(delay))
        }
    }
}

// MARK: - Result

/// The results of an HTTP request.
public class PMHTTPResult: NSObject, NSCopying {
    /// `true` iff the task finished successfully.
    public let isSuccess: Bool
    
    /// `true` iff the task failed with an error.
    public var isError: Bool {
        return error != nil
    }
    
    /// `true` iff the task was canceled before it finished.
    public var isCanceled: Bool {
        return !isSuccess && error == nil
    }
    
    /// If the task finished successfully, returns the resulting value, if any.
    /// Otherwise, returns `nil`.
    /// - Note: A successful result may still have a `nil` value if the parse handler
    ///   returns `nil` or if it's a POST/PUT/PATCH/DELETE request and the response
    ///   is 204 No Content.
    public let value: AnyObject?
    
    /// If the task finished successfully, or if it failed with an error
    /// during processing after receiving the response, returns the `NSURLResponse`.
    /// Otherwise, if the task failed with a networking error or was canceled,
    /// returns `nil`.
    public let response: NSURLResponse?
    
    /// If the task failed with an error, returns the `NSError`.
    /// Otherwise, returns `nil`.
    /// - Note: Canceled tasks are not considered to be in error and therefore
    ///   return `nil` from both `value` and `error`.
    public let error: NSError?
    
    /// Creates and returns a new `PMHTTPResult` representing a successful result.
    public init(value: AnyObject?, response: NSURLResponse) {
        isSuccess = true
        self.value = value
        self.response = response
        error = nil
        super.init()
    }
    
    /// Creates and returns a new `PMHTTPResult` representing a failed task.
    public init(error: NSError, response: NSURLResponse?) {
        isSuccess = false
        self.error = error
        self.response = response
        value = nil
        super.init()
    }
    
    /// Creates and returns a new `PMHTTPResult` representing a canceled task.
    public class func canceledResult() -> PMHTTPResult {
        return PMHTTPResult(canceled: ())
    }
    
    public func copyWithZone(zone: NSZone) -> AnyObject {
        return self
    }
    
    private init(canceled: ()) {
        isSuccess = false
        value = nil
        response = nil
        error = nil
        super.init()
    }
    
    private convenience init<T: AnyObject>(_ result: HTTPManagerTaskResult<T>) {
        switch result {
        case let .Success(response, value):
            self.init(value: value, response: response)
        case let .Error(response, error as HTTPManagerError):
            self.init(error: error.toNSError(), response: response)
        case let .Error(response, error):
            self.init(error: error as NSError, response: response)
        case .Canceled:
            self.init(canceled: ())
        }
    }
    
    private convenience init<T: AnyObject>(_ result: HTTPManagerTaskResult<T?>) {
        switch result {
        case let .Success(response, value):
            self.init(value: value, response: response)
        case let .Error(response, error as HTTPManagerError):
            self.init(error: error.toNSError(), response: response)
        case let .Error(response, error):
            self.init(error: error as NSError, response: response)
        case .Canceled:
            self.init(canceled: ())
        }
    }
}

/// The results of an HTTP request that returns an `NSData`.
public final class PMHTTPDataResult: PMHTTPResult {
    /// If the task finished successfully, returns the resulting `NSData`, if any.
    /// Otherwise, returns `nil`.
    /// - Note: A successful result may still have a `nil` value if it's a
    ///   POST/PUT/PATCH/DELETE request and the response is 204 No Content.
    ///   Successful GET/HEAD requests will never have a `nil` value.
    /// - Note: This property returns the same value that `value` does.
    public var data: NSData? {
        return value as! NSData?
    }
    
    /// Creates and returns a new `PMHTTPDataResult` representing a successful result.
    public init(data: NSData?, response: NSURLResponse) {
        super.init(value: data, response: response)
    }
    
    /// Creates and returns a new `PMHTTPDataResult` representing a failed task.
    public override init(error: NSError, response: NSURLResponse?) {
        super.init(error: error, response: response)
    }
    
    /// Creates and returns a new `PMHTTPDataResult` representing a canceled task.
    public override class func canceledResult() -> PMHTTPDataResult {
        return PMHTTPDataResult(canceled: ())
    }
    
    private override init(canceled: ()) {
        super.init(canceled: ())
    }
    
    private convenience init(_ result: HTTPManagerTaskResult<NSData>) {
        switch result {
        case let .Success(response, data):
            self.init(data: data, response: response)
        case let .Error(response, error as HTTPManagerError):
            self.init(error: error.toNSError(), response: response)
        case let .Error(response, error):
            self.init(error: error as NSError, response: response)
        case .Canceled:
            self.init(canceled: ())
        }
    }
    
    private convenience init(_ result: HTTPManagerTaskResult<NSData?>) {
        switch result {
        case let .Success(response, data):
            self.init(data: data, response: response)
        case let .Error(response, error as HTTPManagerError):
            self.init(error: error.toNSError(), response: response)
        case let .Error(response, error):
            self.init(error: error as NSError, response: response)
        case .Canceled:
            self.init(canceled: ())
        }
    }
}

// MARK: - Task

extension HTTPManagerTask {
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
    @objc(idempotent)
    public var __objc_idempotent: Bool {
        @objc(isIdempotent) get { return isIdempotent }
    }
}

// MARK: - Request

extension HTTPManagerRequest {
    /// The request method.
    @objc(requestMethod) public var __objc_requestMethod: String {
        return requestMethod.rawValue
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
    @objc(idempotent) public var __objc_idempotent: Bool {
        @objc(isIdempotent) get { return isIdempotent }
        set { isIdempotent = newValue }
    }
    
    /// The timeout interval of the request, in seconds. If `nil`, the session's default
    /// timeout interval is used. Default is `nil`.
    @objc(timeoutInterval) public var __objc_timeoutInterval: NSNumber? {
        get { return timeoutInterval }
        set { timeoutInterval = newValue as NSTimeInterval? }
    }
    
    /// The cache policy to use for the request. If `NSURLRequestUseProtocolCachePolicy`,
    /// the default cache policy is used. Default is `NSURLRequestUseProtocolCachePolicy`
    /// for GET/HEAD requests and `NSURLRequestReloadIgnoringLocalCacheData` for
    /// POST/PUT/PATCH/DELETE requests.
    @objc(cachePolicy) public var __objc_cachePolicy: NSURLRequestCachePolicy {
        return cachePolicy ?? NSURLRequestCachePolicy.UseProtocolCachePolicy
    }
    
    /// Additional HTTP header fields to pass in the request. Default is `[:]`.
    ///
    /// If not specified, the request will fill in `Accept` and `Accept-Language`
    /// automatically when performing the request.
    ///
    /// - Note: If `self.credential` is non-`nil`, the `Authorization` header will be
    /// ignored. `Content-Type` and `Content-Length` are always ignored.
    @objc(headerFields) public var __objc_headerFields: [String: String] {
        return headerFields.dictionary
    }
    
    /// Adds an HTTP header to the list of header fields.
    ///
    /// - Parameter value: The value for the header field.
    /// - Parameter field: The name of the header field. Header fields are case-insensitive.
    ///
    /// If a value was previously set for the specified *field*, the supplied *value* is appended
    /// to the existing value using the appropriate field delimiter.
    @objc(addValue:forHeaderField:) public func __objc_addValue(value: String, forHeaderField field: String) {
        headerFields.addValue(value, forHeaderField: field)
    }
    
    /// Sets a specified HTTP header field.
    ///
    /// - Parameter value: The value for the header field.
    /// - Parameter field: The name of the header field. Header fields are case-insensitive.
    @objc(setValue:forHeaderField:) public func __objc_setValue(value: String, forHeaderField field: String) {
        headerFields[field] = value
    }
    
    /// Returns a specified HTTP header field, if set.
    ///
    /// - Parameter field: The name of the header field. Header fields are case-insensitive.
    /// - Returns: The value for the header field, or `nil` if no value was set.
    @objc(valueForHeaderField:) public func __objc_valueForHeaderField(field: String) -> String? {
        return headerFields[field]
    }
}

// MARK: - Network Request

extension HTTPManagerNetworkRequest {
    /// Returns a new request that parses the data with the specified handler.
    /// - Note: If the server responds with 204 No Content, the parse handler is
    ///   invoked with an empty data. The handler may choose to return the error
    ///   `HTTPManagerError.UnexpectedNoContent` if it does not handle this case.
    /// - Parameter handler: The handler to call as part of the request
    ///   processing. This handler is not guaranteed to be called on any
    ///   particular thread. The handler returns the new value for the request.
    ///   If the handler returns `nil`, then if `error` is filled in with an
    ///   error the parse is considered to have errored, otherwise the parse is
    ///   treated as successful but with a `nil` value.
    /// - Returns: An `HTTPManagerObjectParseRequest`.
    /// - Note: If you need to parse on a particular thread, such as on the main
    ///   thread, you should just use `performRequestWithCompletion(_:)`
    ///   instead.
    /// - Note: If the request is canceled, the results of the handler may be
    ///   discarded. Any side-effects performed by your handler must be safe in
    ///   the event of a cancelation.
    @objc(parseWithHandler:)
    public func __objc_parseWithHandler(handler: @convention(block) (response: NSURLResponse, data: NSData, error: NSErrorPointer) -> AnyObject?) -> HTTPManagerObjectParseRequest {
        return HTTPManagerObjectParseRequest(request: parseWithHandler({ response, data -> AnyObject? in
            var error: NSError?
            if let object = handler(response: response, data: data, error: &error) {
                return object
            } else if let error = error {
                throw error
            } else {
                return nil
            }
        }))
    }
    
    /// Creates a suspended `HTTPManagerTask` for the request with the given completion handler.
    ///
    /// This method is intended for cases where you need access to the `NSURLSessionTask` prior to
    /// the task executing, e.g. if you need to record the task identifier somewhere before the
    /// completion block fires.
    /// - Parameter handler: The handler to call when the request is done. This handler
    ///   will be invoked on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    /// - Important: After you create the task, you must start it by calling the `-resume` method.
    @objc(createTaskWithCompletion:)
    public func __objc_createTaskWithCompletion(handler: @convention(block) (task: HTTPManagerTask, result: PMHTTPDataResult) -> Void) -> HTTPManagerTask {
        return createTaskWithCompletion { task, result in
            handler(task: task, result: PMHTTPDataResult(result))
        }
    }
    
    /// Creates a suspended `HTTPManagerTask` for the request with the given completion handler.
    ///
    /// This method is intended for cases where you need access to the `NSURLSessionTask` prior to
    /// the task executing, e.g. if you need to record the task identifier somewhere before the
    /// completion block fires.
    /// - Parameter queue: The queue to call the handler on. `nil` means the handler will
    ///   be called on a global concurrent queue.
    /// - Parameter handler: The handler to call when the request is done. This handler
    ///   will be invoked on *queue* if provided, otherwise on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    /// - Important: After you create the task, you must start it by calling the `resume()` method.
    @objc(createTaskWithCompletionOnQueue:handler:)
    public func __objc_createTaskWithCompletion(onQueue queue: NSOperationQueue?, handler: @convention(block) (task: HTTPManagerTask, result: PMHTTPDataResult) -> Void) -> HTTPManagerTask {
        return createTaskWithCompletion(onQueue: queue) { task, result in
            handler(task: task, result: PMHTTPDataResult(result))
        }
    }
    
    /// Performs an asynchronous request and calls the specified handler when
    /// done.
    /// - Parameter handler: The handler to call when the request is done. This
    ///   handler is called on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    @objc(performRequestWithCompletion:)
    public func __objc_performRequestWithCompletion(handler: @convention(block) (task: HTTPManagerTask, result: PMHTTPDataResult) -> Void) -> HTTPManagerTask {
        return performRequestWithCompletion { task, result in
            handler(task: task, result: PMHTTPDataResult(result))
        }
    }
    
    /// Performs an asynchronous request and calls the specified handler when
    /// done.
    /// - Parameter queue: The queue to call the handler on. May be `nil`.
    /// - Parameter handler: The handler to call when the request is done. This handler
    ///   will be invoked on *queue* if provided, otherwise on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    @objc(performRequestWithCompletionOnQueue:handler:)
    public func __objc_performRequestWithCompletionOnQueue(queue: NSOperationQueue?, handler: @convention(block) (task: HTTPManagerTask, result: PMHTTPDataResult) -> Void) -> HTTPManagerTask {
        return performRequestWithCompletion(onQueue: queue) { task, result in
            handler(task: task, result: PMHTTPDataResult(result))
        }
    }
}

// MARK: - Data Request

extension HTTPManagerDataRequest {
    /// The cache policy to use for the request. If `NSURLRequestUseProtocolCachePolicy`,
    /// the default cache policy is used. Default is `NSURLRequestUseProtocolCachePolicy`.
    @objc(cachePolicy) public override var __objc_cachePolicy: NSURLRequestCachePolicy {
        get { return super.__objc_cachePolicy }
        set {
            if newValue == NSURLRequestCachePolicy.UseProtocolCachePolicy {
                cachePolicy = nil
            } else {
                cachePolicy = newValue
            }
        }
    }
    
    /// Returns a new request that parses the data as JSON.
    /// Any nulls in the JSON are represented as `NSNull`.
    /// - Note: If the server responds with 204 No Content, the parse is skipped
    ///   and `HTTPManagerError.UnexpectedNoContent` is returned as the parse result.
    /// - Returns: An `HTTPManagerObjectParseRequest`.
    @objc(parseAsJSON)
    public func __objc_parseAsJSON() -> HTTPManagerObjectParseRequest {
        return __objc_parseAsJSONOmitNulls(false)
    }
    
    /// Returns a new request that parses the data as JSON.
    /// - Note: If the server responds with 204 No Content, the parse is skipped
    ///   and `HTTPManagerError.UnexpectedNoContent` is returned as the parse result.
    /// - Parameter omitNulls: If `true`, nulls in the JSON are omitted from the result.
    ///   If `false`, nulls are represented as `NSNull`. If the top-level value is null,
    ///   it is always represented as `NSNull` regardless of this parameter.
    /// - Returns: An `HTTPManagerObjectParseRequest`.
    @objc(parseAsJSONOmitNulls:)
    public func __objc_parseAsJSONOmitNulls(omitNulls: Bool) -> HTTPManagerObjectParseRequest {
        return HTTPManagerObjectParseRequest(request: parseAsJSONWithHandler({ response, json -> AnyObject? in
            return omitNulls ? (json.nsNoNull ?? NSNull()) : json.ns
        }))
    }
    
    /// Returns a new request that parses the data as JSON and passes it through
    /// the specified handler. Any nulls in the JSON are represented as `NSNull`.
    /// - Note: If the server responds with 204 No Content, the parse is skipped
    ///   and `HTTPManagerError.UnexpectedNoContent` is returned as the parse result.
    /// - Parameter handler: The handler to call as part of the request
    ///   processing. This handler is not guaranteed to be called on any
    ///   particular thread. The handler returns the new value for the request.
    ///   If the handler returns `nil`, then if `error` is filled in with an
    ///   error the parse is considered to have errored, otherwise the parse is
    ///   treated as successful but with a `nil` value.
    /// - Returns: An `HTTPManagerObjectParseRequest`.
    /// - Note: If you need to parse on a particular thread, such as on the main
    ///   thread, you should just use `performRequestWithCompletion(_:)`
    ///   instead.
    /// - Note: If the request is canceled, the results of the handler may be
    ///   discarded. Any side-effects performed by your handler must be safe in
    ///   the event of a cancelation.
    @objc(parseAsJSONWithHandler:)
    public func __objc_parseAsJSONWithHandler(handler: @convention(block) (response: NSURLResponse, json: AnyObject, error: NSErrorPointer) -> AnyObject?) -> HTTPManagerObjectParseRequest {
        return __objc_parseAsJSONOmitNulls(false, withHandler: handler)
    }
    
    /// Returns a new request that parses the data as JSON and passes it through
    /// the specified handler.
    /// - Note: If the server responds with 204 No Content, the parse is skipped
    ///   and `HTTPManagerError.UnexpectedNoContent` is returned as the parse result.
    /// - Parameter omitNulls: If `true`, nulls in the JSON are omitted from the result.
    ///   If `false`, nulls are represented as `NSNull`. If the top-level value is null,
    ///   it is always represented as `NSNull` regardless of this parameter.
    /// - Parameter handler: The handler to call as part of the request
    ///   processing. This handler is not guaranteed to be called on any
    ///   particular thread. The handler returns the new value for the request.
    ///   If the handler returns `nil`, then if `error` is filled in with an
    ///   error the parse is considered to have errored, otherwise the parse is
    ///   treated as successful but with a `nil` value.
    /// - Returns: An `HTTPManagerObjectParseRequest`.
    /// - Note: If you need to parse on a particular thread, such as on the main
    ///   thread, you should just use `performRequestWithCompletion(_:)`
    ///   instead.
    /// - Note: If the request is canceled, the results of the handler may be
    ///   discarded. Any side-effects performed by your handler must be safe in
    ///   the event of a cancelation.
    @objc(parseAsJSONOmitNulls:withHandler:)
    public func __objc_parseAsJSONOmitNulls(omitNulls: Bool, withHandler handler: @convention(block) (response: NSURLResponse, json: AnyObject, error: NSErrorPointer) -> AnyObject?) -> HTTPManagerObjectParseRequest {
        return HTTPManagerObjectParseRequest(request: parseAsJSONWithHandler({ response, json -> AnyObject? in
            var error: NSError?
            let jsonObject = omitNulls ? (json.nsNoNull ?? NSNull()) : json.ns
            if let object = handler(response: response, json: jsonObject, error: &error) {
                return object
            } else if let error = error {
                throw error
            } else {
                return nil
            }
        }))
    }
}

// MARK: - Object Parse Request

/// An HTTP request that has a parse handler.
///
/// - Note: This class is only meant to be used from Obj-C.
public final class HTTPManagerObjectParseRequest: HTTPManagerRequest, HTTPManagerRequestPerformable {
    // NB: All mutable properties need to be overridden here
    
    @nonobjc public override var isIdempotent: Bool {
        get { return _request.isIdempotent }
        set { _request.isIdempotent = newValue }
    }
    
    public override var url: NSURL {
        return _request.url
    }
    
    public override var parameters: [NSURLQueryItem] {
        return _request.parameters
    }
    
    public override var credential: NSURLCredential? {
        get { return _request.credential }
        set { _request.credential = newValue }
    }
    
    public override var timeoutInterval: NSTimeInterval? {
        get { return _request.timeoutInterval }
        set { _request.timeoutInterval = newValue }
    }
    
    public override var cachePolicy: NSURLRequestCachePolicy? {
        return _request.cachePolicy
    }
    
    public override var shouldFollowRedirects: Bool {
        get { return _request.shouldFollowRedirects }
        set { _request.shouldFollowRedirects = newValue }
    }
    
    public override var contentType: String {
        return _request.contentType
    }
    
    public override var allowsCellularAccess: Bool {
        get { return _request.allowsCellularAccess }
        set { _request.allowsCellularAccess = newValue }
    }
    
    public override var userInitiated: Bool {
        get { return _request.userInitiated }
        set { _request.userInitiated = newValue }
    }
    
    public override var retryBehavior: HTTPManagerRetryBehavior? {
        get { return _request.retryBehavior }
        set { _request.retryBehavior = newValue }
    }
    
    #if os(iOS)
    public override var affectsNetworkActivityIndicator: Bool {
        get { return _request.affectsNetworkActivityIndicator }
        set { _request.affectsNetworkActivityIndicator = newValue }
    }
    #endif
    
    public override var headerFields: HTTPHeaders {
        get { return _request.headerFields }
        set { _request.headerFields = newValue }
    }
    
    internal override var mock: HTTPMockInstance? {
        get { return _request.mock }
        set { _request.mock = newValue }
    }
    
    /// The expected MIME type of the response. Defaults to `["application/json"]` for
    /// JSON parse requests, or `[]` for requests created with `-parseWithHandler:`.
    ///
    /// This property is used to generate the `Accept` header, if not otherwise specified by
    /// the request. If multiple values are provided, they're treated as a priority list
    /// for the purposes of the `Accept` header.
    ///
    /// This property is also used to validate the MIME type of the response. If the
    /// response is a 204 No Content, the MIME type is not checked. For all other 2xx
    /// responses, if at least one expected content type is provided, the MIME type
    /// must match one of them. If it doesn't match any, the parse handler will be
    /// skipped and `HTTPManagerError.UnexpectedContentType` will be returned as the result.
    ///
    /// - Note: The MIME type is only tested if the response includes a `Content-Type` header.
    ///   If the `Content-Type` header is missing, the response will always be assumed to be
    ///   valid. The value is tested against both the `Content-Type` header and, if it differs,
    ///   the `NSURLResponse` property `MIMEType`. This is to account for cases where the
    ///   protocol implementation detects a different content type than the server declared.
    ///
    /// Each media type in the list may include parameters. These parameters will be included
    /// in the `Accept` header, but will be ignored for the purposes of comparing against the
    /// resulting MIME type. If the media type includes a parameter named `q`, this parameter
    /// should be last, as it will be interpreted by the `Accept` header as the priority
    /// instead of as a parameter of the media type.
    ///
    /// - Note: Changing the `expectedContentTypes` does not affect the behavior of the parse
    ///   handler. If you create a request using `-parseAsJSON` and then change the
    ///   `expectedContentTypes` to `["text/plain"]`, if the server returns a `"text/plain"`
    ///   response, the parse handler will still assume it's JSON and attempt to decode it.
    ///
    /// - Important: The media types in this list will not be checked for validity. They must
    ///   follow the rules for well-formed media types, otherwise the server may handle the
    ///   request incorrectly.
    public var expectedContentTypes: [String] {
        get { return _request.expectedContentTypes }
        set { _request.expectedContentTypes = newValue }
    }
    
    /// Performs an asynchronous request and calls the specified handler when done.
    /// - Parameter queue: (Optional) The queue to call the handler on. The default value
    ///   of `nil` means the handler will be called on a global concurrent queue.
    /// - Parameter handler: The handler to call when the request is done. The handler
    ///   will be invoked on *queue* if provided, otherwise on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    @nonobjc
    public func createTaskWithCompletion(onQueue queue: NSOperationQueue? = nil, _ handler: (task: HTTPManagerTask, result: HTTPManagerTaskResult<AnyObject?>) -> Void) -> HTTPManagerTask {
        return _request.createTaskWithCompletion(onQueue: queue, handler)
    }
    
    /// Creates a suspended `HTTPManagerTask` for the request with the given completion handler.
    ///
    /// This method is intended for cases where you need access to the `NSURLSessionTask` prior to
    /// the task executing, e.g. if you need to record the task identifier somewhere before the
    /// completion block fires.
    /// - Parameter handler: The handler to call when the request is done. This handler
    ///   will be invoked on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    /// - Important: After you create the task, you must start it by calling the `-resume` method.
    @objc(createTaskWithCompletion:)
    public func __objc_createTaskWithCompletion(handler: @convention(block) (task: HTTPManagerTask, result: PMHTTPResult) -> Void) -> HTTPManagerTask {
        return createTaskWithCompletion { task, result in
            handler(task: task, result: PMHTTPResult(result))
        }
    }
    
    /// Creates a suspended `HTTPManagerTask` for the request with the given completion handler.
    ///
    /// This method is intended for cases where you need access to the `NSURLSessionTask` prior to
    /// the task executing, e.g. if you need to record the task identifier somewhere before the
    /// completion block fires.
    /// - Parameter queue: The queue to call the handler on. `nil` means the handler will
    ///   be called on a global concurrent queue.
    /// - Parameter handler: The handler to call when the request is done. This handler
    ///   will be invoked on *queue* if provided, otherwise on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    /// - Important: After you create the task, you must start it by calling the `resume()` method.
    @objc(createTaskWithCompletionOnQueue:handler:)
    public func __objc_createTaskWithCompletion(onQueue queue: NSOperationQueue?, handler: @convention(block) (task: HTTPManagerTask, result: PMHTTPResult) -> Void) -> HTTPManagerTask {
        return createTaskWithCompletion(onQueue: queue) { task, result in
            handler(task: task, result: PMHTTPResult(result))
        }
    }
    
    /// Performs an asynchronous request and calls the specified handler when
    /// done.
    /// - Parameter handler: The handler to call when the request is done. This
    ///   handler is called on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    @objc(performRequestWithCompletion:)
    public func __objc_performRequestWithCompletion(handler: @convention(block) (task: HTTPManagerTask, result: PMHTTPResult) -> Void) -> HTTPManagerTask {
        return performRequestWithCompletion { task, result in
            handler(task: task, result: PMHTTPResult(result))
        }
    }
    
    /// Performs an asynchronous request and calls the specified handler when
    /// done.
    /// - Parameter queue: The queue to call the handler on. May be `nil`.
    /// - Parameter handler: The handler to call when the request is done. This handler
    ///   will be invoked on *queue* if provided, otherwise on a global concurrent queue.
    /// - Returns: An `HTTPManagerTask` that represents the operation.
    @objc(performRequestWithCompletionOnQueue:handler:)
    public func __objc_performRequestWithCompletionOnQueue(queue: NSOperationQueue?, handler: @convention(block) (task: HTTPManagerTask, result: PMHTTPResult) -> Void) -> HTTPManagerTask {
        return performRequestWithCompletion(onQueue: queue) { task, result in
            handler(task: task, result: PMHTTPResult(result))
        }
    }
    
    internal let _request: HTTPManagerParseRequest<AnyObject?>
    
    private init(request: HTTPManagerParseRequest<AnyObject?>) {
        _request = request
        super.init(apiManager: request.apiManager, URL: request.baseURL, method: request.requestMethod, parameters: [])
    }

    public required init(__copyOfRequest request: HTTPManagerRequest) {
        let request: HTTPManagerObjectParseRequest = unsafeDowncast(request)
        _request = HTTPManagerParseRequest(__copyOfRequest: request._request)
        super.init(__copyOfRequest: request)
    }
    
    internal override func prepareURLRequest() -> (NSMutableURLRequest -> Void)? {
        return _request.prepareURLRequest()
    }
}

// MARK: - Action Request

extension HTTPManagerActionRequest {
    /// Returns a new request that parses the data as JSON.
    /// Any nulls in the JSON are represented as `NSNull`.
    /// - Note: The parse result is `nil` if and only if the server responded with
    ///   204 No Content.
    /// - Returns: An `HTTPManagerObjectParseRequest`.
    /// - Note: If the response is a 204 No Content, the result object
    ///   will return `nil` for `value`.
    @objc(parseAsJSON)
    public func __objc_parseAsJSON() -> HTTPManagerObjectParseRequest {
        return __objc_parseAsJSONOmitNulls(false)
    }
    
    /// Returns a new request that parses the data as JSON.
    /// - Note: The parse result is `nil` if and only if the server responded with
    ///   204 No Content.
    /// - Parameter omitNulls: If `true`, nulls in the JSON are omitted from the result.
    ///   If `false`, nulls are represented as `NSNull`. If the top-level value is null,
    ///   it is always represented as `NSNull` regardless of this parameter.
    /// - Returns: An `HTTPManagerObjectParseRequest`.
    /// - Note: If the response is a 204 No Content, the result object
    ///   will return `nil` for `value`.
    @objc(parseAsJSONOmitNulls:)
    public func __objc_parseAsJSONOmitNulls(omitNulls: Bool) -> HTTPManagerObjectParseRequest {
        return HTTPManagerObjectParseRequest(request: parseAsJSONWithHandler({ result -> AnyObject? in
            return result.json.map({ omitNulls ? $0.nsNoNull ?? NSNull() : $0.ns })
        }))
    }
    
    /// Returns a new request that parses the data as JSON and passes it through
    /// the specified handler. Any nulls in the JSON are represented as `NSNull`.
    /// - Note: If the `json` argument to the handler is `nil`, this means the server
    ///   responded with 204 No Content and the `response` argument is guaranteed
    ///   to be an instance of `NSHTTPURLResponse`.
    /// - Parameter handler: The handler to call as part of the request
    ///   processing. This handler is not guaranteed to be called on any
    ///   particular thread. The handler returns the new value for the request.
    /// - Returns: An `HTTPManagerObjectParseRequest`.
    /// - Note: If the response is a 204 No Content, the result object
    ///   will return `nil` for `value`.
    /// - Note: If you need to parse on a particular thread, such as on the main
    ///   thread, you should just use `performRequestWithCompletion(_:)`
    ///   instead.
    /// - Note: If the request is canceled, the results of the handler may be
    ///   discarded. Any side-effects performed by your handler must be safe in
    ///   the event of a cancelation.
    @objc(parseAsJSONWithHandler:)
    public func __objc_parseAsJSONWithHandler(handler: @convention(block) (response: NSURLResponse, json: AnyObject?, error: NSErrorPointer) -> AnyObject?) -> HTTPManagerObjectParseRequest {
        return __objc_parseAsJSONOmitNulls(false, withHandler: handler)
    }
    
    /// Returns a new request that parses the data as JSON and passes it through
    /// the specified handler.
    /// - Note: If the `json` argument to the handler is `nil`, this means the server
    ///   responded with 204 No Content and the `response` argument is guaranteed
    ///   to be an instance of `NSHTTPURLResponse`.
    /// - Parameter omitNulls: If `true`, nulls in the JSON are omitted from the result.
    ///   If `false`, nulls are represented as `NSNull`. If the top-level value is null,
    ///   it is always represented as `NSNull` regardless of this parameter.
    /// - Parameter handler: The handler to call as part of the request
    ///   processing. This handler is not guaranteed to be called on any
    ///   particular thread. The handler returns the new value for the request.
    ///   If the handler returns `nil`, then if `error` is filled in with an
    ///   error the parse is considered to have errored, otherwise the parse is
    ///   treated as successful but with a `nil` value.
    /// - Returns: An `HTTPManagerObjectParseRequest`.
    /// - Note: If you need to parse on a particular thread, such as on the main
    ///   thread, you should just use `performRequestWithCompletion(_:)`
    ///   instead.
    /// - Note: If the request is canceled, the results of the handler may be
    ///   discarded. Any side-effects performed by your handler must be safe in
    ///   the event of a cancelation.
    @objc(parseAsJSONOmitNulls:withHandler:)
    public func __objc_parseAsJSONOmitNulls(omitNulls: Bool, withHandler handler: @convention(block) (response: NSURLResponse, json: AnyObject?, error: NSErrorPointer) -> AnyObject?) -> HTTPManagerObjectParseRequest {
        return HTTPManagerObjectParseRequest(request: parseAsJSONWithHandler({ result -> AnyObject? in
            var error: NSError?
            let jsonObject = result.json.map({ omitNulls ? $0.nsNoNull ?? NSNull() : $0.ns })
            if let object = handler(response: result.response, json: jsonObject, error: &error) {
                return object
            } else if let error = error {
                throw error
            } else {
                return nil
            }
        }))
    }
}

// MARK: - Upload Form Request

// It looks like HTTPManagerUploadFormRequest is already fully ObjC-compatible

// MARK: - Upload JSON Request

extension HTTPManagerUploadJSONRequest {
    /// The JSON data to upload.
    /// - Requires: Values assigned to this property must be json-compatible.
    @objc(uploadJSON)
    public var __objc_uploadJSON: AnyObject {
        get { return uploadJSON.ns }
        set { uploadJSON = try! JSON(ns: newValue) }
    }
}

// MARK: - Upload Data Request

// It looks like HTTPManagerUploadDataRequest is already fully ObjC-compatible
