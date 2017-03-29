//
//  Mocking.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 4/7/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Foundation
import PMJSON

/// Manages a set of mocks for the `HTTPManager`.
///
/// The mocks associated with this class may match requests based on path (relative to the environment)
/// or absolute URL. If the path or URL contains any path component of the form `:name`, any (non-empty)
/// component value will match and the matched value will be made available to block-based mocks.
/// For example the path `"users/:id"` will match a request for `"users/1234"` but will not match
/// a request for `"users"`.
///
/// All mocks are evaluated in reverse order of addition. This means that if two mocks would match the
/// same URL, whichever mock was added last is used.
///
/// **Thread safety:** All methods in this class are safe to call from any thread.
public final class HTTPMockManager: NSObject {
    /// If `true`, any URL that is part of the current environment but not handled by any mocks
    /// will return a 500 Internal Server Error. The default value is `false`.
    /// - SeeAlso: interceptUnhandledExternalURLs
    public var interceptUnhandledEnvironmentURLs: Bool {
        get {
            return inner.sync({ $0.interceptUnhandledEnvironmentURLs })
        }
        set {
            inner.asyncBarrier { inner in
                inner.interceptUnhandledEnvironmentURLs = newValue
            }
        }
    }
    /// If `true`, any URL that is not part of the current environment but not handled by any mocks
    /// will return a 500 Internal Server Error. The default value is `false`.
    /// - SeeAlso: interceptUnhandledEnvironmentURLs
    public var interceptUnhandledExternalURLs: Bool {
        get {
            return inner.sync({ $0.interceptUnhandledExternalURLs })
        }
        set {
            inner.asyncBarrier { inner in
                inner.interceptUnhandledExternalURLs = newValue
            }
        }
    }
    
    /// Adds a mock to the mock manager that returns a given response.
    ///
    /// All requests that match this mock will be given the same response.
    ///
    /// - Parameter url: The URL to mock. This may be a relative URL, which is evaluated against the
    ///   environment active at the time the request is made, or it may be an absolute URL. The URL
    ///   may include path components of the form `:name` to match any (non-empty) component value.
    /// - Parameter httpMethod: (Optional) The HTTP method to be mocked. The default value of `nil`
    ///   means this mock will match any HTTP method.
    /// - Parameter statusCode: The HTTP status code to return.
    /// - Parameter headers: (Optional) A collection of HTTP headers to return.
    /// - Parameter data: (Optional) The body of the response. If the `headers` does not provide a
    ///   `"Content-Length"` header, one is synthesized from the data.
    /// - Parameter delay: (Optional) The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    /// - Returns: An `HTTPMockToken` object that can be used to unregister the mock later.
    @discardableResult
    public func addMock(for url: String, httpMethod: String? = nil, statusCode: Int, headers: [String: String] = [:], data: Data = Data(), delay: TimeInterval = 0.03) -> HTTPMockToken {
        var headers = headers
        if headers["Content-Length"] == nil {
            headers["Content-Length"] = String(data.count)
        }
        return addMock(for: url, httpMethod: httpMethod, queue: DispatchQueue.global(qos: .utility), handler: { (request, parameters, completion) in
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
            if delay > 0 {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + delay) {
                    autoreleasepool {
                        completion(response, data)
                    }
                }
            } else {
                completion(response, data)
            }
        })
    }
    
    /// Adds a mock to the mock manager that returns a given plain text response.
    ///
    /// All requests that match this mock will be given the same response.
    ///
    /// - Parameter url: The URL to mock. This may be a relative URL, which is evaluated against the
    ///   environment active at the time the request is made, or it may be an absolute URL. The URL
    ///   may include path components of the form `:name` to match any (non-empty) component value.
    /// - Parameter httpMethod: (Optional) The HTTP method to be mocked. The default value of `nil`
    ///   means this mock will match any HTTP method.
    /// - Parameter statusCode: The HTTP status code to return.
    /// - Parameter headers: (Optional) A collection of HTTP headers to return. If `"Content-Type"`
    ///   is not specified, it will default to `"text/plain"`.
    /// - Parameter text: The body text to return. If the `headers` does not provide a
    ///   `"Content-Length"` header, one is synthesized from the text.
    /// - Parameter delay: (Optional) The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    /// - Returns: An `HTTPMockToken` object that can be used to unregister the mock later.
    @discardableResult
    public func addMock(for url: String, httpMethod: String? = nil, statusCode: Int, headers: [String: String] = [:], text: String, delay: TimeInterval = 0.03) -> HTTPMockToken {
        let data = text.data(using: String.Encoding.utf8) ?? Data()
        var headers = headers
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "text/plain; charset=utf-8"
        }
        return addMock(for: url, httpMethod: httpMethod, statusCode: statusCode, headers: headers, data: data, delay: delay)
    }
    
    /// Adds a mock to the mock manager that returns a given JSON response.
    ///
    /// All requests that match this mock will be given the same response.
    ///
    /// - Parameter url: The URL to mock. This may be a relative URL, which is evaluated against the
    ///   environment active at the time the request is made, or it may be an absolute URL. The URL
    ///   may include path components of the form `:name` to match any (non-empty) component value.
    /// - Parameter httpMethod: (Optional) The HTTP method to be mocked. The default value of `nil`
    ///   means this mock will match any HTTP method.
    /// - Parameter statusCode: The HTTP status code to return.
    /// - Parameter headers: (Optional) A collection of HTTP headers to return. If `"Content-Type"`
    ///   is not specified, it will default to `"application/json"`.
    /// - Parameter json: The JSON body of the response. If the `headers` does not provide a
    ///   `"Content-Length"` header, one is synthesized from the encoded JSON.
    /// - Parameter delay: (Optional) The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    /// - Returns: An `HTTPMockToken` object that can be used to unregister the mock later.
    @discardableResult
    public func addMock(for url: String, httpMethod: String? = nil, statusCode: Int, headers: [String: String] = [:], json: JSON, delay: TimeInterval = 0.03) -> HTTPMockToken {
        let data = JSON.encodeAsData(json)
        var headers = headers
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json"
        }
        return addMock(for: url, httpMethod: httpMethod, statusCode: statusCode, headers: headers, data: data, delay: delay)
    }
    
    /// Adds a mock to the mock manager that returns a given sequence of responses.
    ///
    /// Each request that matches this mock will be given the next response in the sequence.
    ///
    /// - Parameter url: The URL to mock. This may be a relative URL, which is evaluated against the
    ///   environment active at the time the request is made, or it may be an absolute URL. The URL
    ///   may include path components of the form `:name` to match any (non-empty) component value.
    /// - Parameter httpMethod: (Optional) The HTTP method to be mocked. The default value of `nil`
    ///   means this mock will match any HTTP method.
    /// - Parameter sequence: an `HTTPMockSequence` with the sequence of responses to provide.
    /// - Returns: An `HTTPMockToken` object that can be used to unregister the mock later.
    @discardableResult
    public func addMock(for url: String, httpMethod: String? = nil, sequence: HTTPMockSequence) -> HTTPMockToken {
        var mockGen = Optional.some(sequence.mocks.makeIterator())
        var nextMock = mockGen?.next()
        let repeatsLastResponse = sequence.repeatsLastResponse
        return addMock(for: url, httpMethod: httpMethod, handler: { (request, parameters, completion) in
            guard let mock = nextMock else {
                let data = "Mock sequence exhausted".data(using: String.Encoding.utf8)!
                completion(HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"])!, data)
                return
            }
            nextMock = mockGen?.next()
            if nextMock == nil {
                mockGen = nil
                if repeatsLastResponse {
                    nextMock = mock
                }
            }
            var headers = mock.headers
            let body: Data
            switch mock.payload {
            case .data(let data):
                body = data
            case .text(let text):
                body = text.data(using: String.Encoding.utf8) ?? Data()
                if headers["Content-Type"] == nil {
                    headers["Content-Type"] = "text/plain; charset=utf-8"
                }
            case .json(let json):
                body = JSON.encodeAsData(json)
                if headers["Content-Type"] == nil {
                    headers["Content-Type"] = "application/json"
                }
            }
            if headers["Content-Length"] == nil {
                headers["Content-Length"] = String(body.count)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: mock.statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
            if mock.delay > 0 {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + mock.delay) {
                    autoreleasepool {
                        completion(response, body)
                    }
                }
            } else {
                completion(response, body)
            }
        })
    }
    
    /// Adds a mock to the mock manager that evaluates a block to provide the response.
    ///
    /// - Parameter url: The URL to mock. This may be a relative URL, which is evaluated against the
    ///   environment active at the time the request is made, or it may be an absolute URL. The URL
    ///   may include path components of the form `:name` to match any (non-empty) component value.
    /// - Parameter httpMethod: (Optional) The HTTP method to be mocked. The default value of `nil`
    ///   means this mock will match any HTTP method.
    /// - Parameter queue: (Optional) A `dispatch_queue_t` to run the handler on. The default value
    ///   of `nil` means to use a private serial queue.
    /// - Parameter handler: A block to execute in order to provide the mock response. The block
    ///   has arguments `request`, `parameters`, and `completion`. `request` is the `URLRequest`
    ///   that matched the mock. `parameters` is a dictionary that contains a value for each `:name`
    ///   token from the `url` (note: the key is just `"name"`, not `":name"`). `completion` is a
    ///   block that must be invoked to provide the response. The `completion` block may be invoked
    ///   from any queue, but it is an error to not invoke it at all or to invoke it twice.
    /// - Returns: An `HTTPMockToken` object that can be used to unregister the mock later.
    @discardableResult
    public func addMock(for url: String, httpMethod: String? = nil, queue: DispatchQueue? = nil, handler: @escaping (_ request: URLRequest, _ parameters: [String: String], _ completion: @escaping (_ response: HTTPURLResponse, _ body: Data) -> Void) -> Void) -> HTTPMockToken {
        let mock = HTTPMock(url: url, httpMethod: httpMethod, queue: queue ?? DispatchQueue(label: "HTTPMock queue"), handler: handler)
        inner.asyncBarrier { inner in
            inner.mocks.append(mock)
        }
        return mock
    }
    
    /// Adds a mock to the mock manager that evaluates a block to provide the response.
    ///
    /// All blocks for this mock will be executed on the same serial dispatch queue.
    /// This means the block may close over mutable state safely.
    ///
    /// - Parameter url: The URL to mock. This may be a relative URL, which is evaluated against the
    ///   environment active at the time the request is made, or it may be an absolute URL. The URL
    ///   may include path components of the form `:name` to match any (non-empty) component value.
    /// - Parameter httpMethod: (Optional) The HTTP method to be mocked. The default value of `nil`
    ///   means this mock will match any HTTP method.
    /// - Parameter state: A value that is provided (as an `inout` parameter) to the block. This is
    ///   really just a convenient way to create mutable state that the block can access.
    /// - Parameter handler: A block to execute in order to provide the mock response. The block
    ///   has arguments `state`, `request`, `parameters`, and `completion`. `state` is the same `state`
    ///   value passed to this method, and any mutations to `state` are visible to subsequent invocations
    ///   of this same block. `request` is the `URLRequest` that matched the mock. `parameters` is a
    ///   dictionary that contains a value for each `:name` token from the `url` (note: the key is just
    ///   `"name"`, not `":name"`). `completion` is a block that must be invoked to provide the response.
    ///   The `completion` block may be invoked from any queue, but it is an error to not invoke it at
    ///   all or to invoke it twice.
    /// - Returns: An `HTTPMockToken` object that can be used to unregister the mock later.
    @discardableResult
    public func addMock<T>(for url: String, httpMethod: String? = nil, state: T, handler: @escaping (_ state: inout T, _ request: URLRequest, _ parameters: [String: String], _ completion: @escaping (_ response: HTTPURLResponse, _ body: Data) -> Void) -> Void) -> HTTPMockToken {
        var state = state
        return addMock(for: url, httpMethod: httpMethod, handler: { (request, parameters, completion) in
            handler(&state, request, parameters, completion)
        })
    }
    
    /// Removes a previously-registered mock from the mock manager.
    ///
    /// Calling this with a token that was already removed, or with a token from another mock
    /// manager, is a no-op.
    ///
    /// - Parameter token: An `HTTPMockToken` returned by a previous call to `addMock`.
    public func removeMock(_ token: HTTPMockToken) {
        inner.asyncBarrier { inner in
            if let idx = inner.mocks.index(where: { $0 === token }) {
                inner.mocks.remove(at: idx)
            }
        }
    }
    
    /// Removes all mocks from the mock manager.
    public func removeAllMocks() {
        inner.asyncBarrier { inner in
            inner.mocks.removeAll()
        }
    }
    
    /// Resets the mock manager back to the defaults.
    ///
    /// This removes all mocks and resets all properties back to their default values.
    public func reset() {
        inner.asyncBarrier({ $0.reset() })
    }
    
    internal func mockForRequest(_ request: URLRequest, environment: HTTPManager.Environment?) -> HTTPMockInstance? {
        guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        let method = request.httpMethod
        return inner.sync { inner in
            for mock in inner.mocks.reversed() {
                if case .matches(let parameters) = mock.handleURL(components, method, environment) {
                    return HTTPMockInstance(queue: mock.queue, parameters: parameters, handler: mock.handler)
                }
            }
            if environment?.isPrefix(of: url) ?? false {
                if inner.interceptUnhandledEnvironmentURLs {
                    return HTTPMockInstance.unhandledURLMock
                }
            } else if inner.interceptUnhandledExternalURLs {
                return HTTPMockInstance.unhandledURLMock
            }
            return nil
        }
    }
    
    private var inner: QueueConfined<Inner> = QueueConfined(label: "HTTPMockManager internal queue", value: Inner())
    
    private class Inner {
        var mocks: [HTTPMock] = []
        var interceptUnhandledEnvironmentURLs: Bool = false
        var interceptUnhandledExternalURLs: Bool = false
        
        func reset() {
            mocks.removeAll()
            interceptUnhandledExternalURLs = false
            interceptUnhandledEnvironmentURLs = false
        }
    }
}

public extension HTTPMockManager {
    /// A convenience function for reading the body data from a `URLRequest`.
    ///
    /// If the request has `HTTPBody` set, it is returned, otherwise if it has `HTTPBodyStream`,
    /// the stream is read to exhaustion. If the request has no body, an empty `NSData` is returned.
    ///
    /// - Warning: If the request has an `HTTPBodyStream` but it cannot be opened (e.g. because it
    ///   has already been read), an empty `NSData` is returned. Similarly, if the stream takes longer
    ///   than 400ms to open, an empty `NSData` is returned.
    ///
    /// This function is primarily intended to be used from within a handler block passed to
    /// `addMock(for:httpMethod:queue:handler:)`.
    func dataFromRequest(_ request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        if let stream = request.httpBodyStream {
            stream.open()
            switch stream.streamStatus {
            case .opening:
                // I don't think any of the streams we expect to get have an Opening phase but
                // we'll handle it anyway by polling for up to the fairly arbitrarily-chosen 400ms.
                let start = getMachAbsoluteTimeInNanoseconds()
                repeat {
                    // yield to the scheduler so we're not actually spinning too much
                    sched_yield()
                } while stream.streamStatus == .opening && getMachAbsoluteTimeInNanoseconds() &- start < 400_000_000
            case .open:
                break
            default:
                // We couldn't open it
                return Data()
            }
            defer { stream.close() }
            var data = Data()
            let bufferSize = 64 * 1024 // 64kB
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate(capacity: bufferSize) }
            loop: repeat {
                switch stream.read(buffer, maxLength: bufferSize) {
                case 0: // EOF
                    break loop
                case let count where count > 0:
                    data.append(buffer, count: count)
                default: // error occurred
                    // if we can't read, just return what we have
                    break loop
                }
            } while true
            return data
        }
        return Data()
    }
}

/// Represents a sequence of mock responses that will be returned from successive requests
/// that are handled by the same mock.
///
/// Responses added to the sequence are returned in the same order. If more requests are made
/// than responses added to the sequence, all subsequence requests will return a generic
/// 500 Internal Server Error response. The property `repeatsLastResponse` can be used to
/// instead repeat the final response over and over.
///
/// **Thread safety:** Instances of this class may not be accessed concurrently from multiple
/// threads at the same time.
public final class HTTPMockSequence: NSObject {
    /// If `true`, the last response in the sequence is repeated for all future requests.
    /// Otherwise, once the sequence has been exhausted, future requests will serve up a
    /// 500 Internal Server Error response. The default value is `false`.
    public var repeatsLastResponse: Bool = false
    
    /// Adds a mock to the sequence that returns a given response.
    ///
    /// - Parameter statusCode: The HTTP status code to return.
    /// - Parameter headers: (Optional) A collection of HTTP headers to return.
    /// - Parameter data: (Optional) The body of the response. If the `headers` does not provide a
    ///   `"Content-Length"` header, one is synthesized from the data.
    /// - Parameter delay: (Optional) The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    public func addMock(statusCode: Int, headers: [String: String] = [:], data: Data = Data(), delay: TimeInterval = 0.03) {
        mocks.append((statusCode: statusCode, headers: headers, payload: .data(data), delay: delay))
    }
    /// Adds a mock to the sequence that returns a given plain text response.
    ///
    /// - Parameter statusCode: The HTTP status code to return.
    /// - Parameter headers: (Optional) A collection of HTTP headers to return. If `"Content-Type"`
    ///   is not specified, it will default to `"text/plain"`.
    /// - Parameter text: The body text to return. If the `headers` does not provide a
    ///   `"Content-Length"` header, one is synthesized from the text.
    /// - Parameter delay: (Optional) The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    public func addMock(statusCode: Int, headers: [String: String] = [:], text: String, delay: TimeInterval = 0.03) {
        mocks.append((statusCode: statusCode, headers: headers, payload: .text(text), delay: delay))
    }
    /// Adds a mock to the sequence that returns a given JSON response.
    ///
    /// - Parameter statusCode: The HTTP status code to return.
    /// - Parameter headers: (Optional) A collection of HTTP headers to return. If `"Content-Type"`
    ///   is not specified, it will default to `"application/json"`.
    /// - Parameter json: The JSON body of the response. If the `headers` does not provide a
    ///   `"Content-Length"` header, one is synthesized from the encoded JSON.
    /// - Parameter delay: (Optional) The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    public func addMock(statusCode: Int, headers: [String: String] = [:], json: JSON, delay: TimeInterval = 0.03) {
        mocks.append((statusCode: statusCode, headers: headers, payload: .json(json), delay: delay))
    }
    
    fileprivate enum Payload {
        case data(Data)
        case text(String)
        case json(PMJSON.JSON)
    }
    
    fileprivate var mocks: [(statusCode: Int, headers: [String: String], payload: Payload, delay: TimeInterval)] = []
}

public extension HTTPManagerNetworkRequest {
    /// Returns a new request that returns a mock response.
    ///
    /// - Parameter statusCode: The HTTP status code to return.
    /// - Parameter headers: (Optional) A collection of HTTP headers to return.
    /// - Parameter data: (Optional) The body of the response. If the `headers` does not provide a
    ///   `"Content-Length"` header, one is synthesized from the data.
    /// - Parameter delay: (Optional) The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    /// - Returns: A copy of `self` that returns a mock response.
    public func mock(statusCode: Int, headers: [String: String] = [:], data: Data = Data(), delay: TimeInterval = 0.03) -> Self {
        let newRequest = type(of: self).init(__copyOfRequest: self)
        var headers = headers
        if headers["Content-Length"] == nil {
            headers["Content-Length"] = String(data.count)
        }
        newRequest.mock = HTTPMockInstance(queue: DispatchQueue.global(qos: .utility), parameters: [:], handler: { (request, parameters, completion) in
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
            if delay > 0 {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + delay) {
                    autoreleasepool {
                        completion(response, data)
                    }
                }
            } else {
                completion(response, data)
            }
        })
        return newRequest
    }
    
    /// Retursn a new request that returns a mock plain text response.
    ///
    /// - Parameter statusCode: The HTTP status code to return.
    /// - Parameter headers: (Optional) A collection of HTTP headers to return. If `"Content-Type"`
    ///   is not specified, it will default to `"text/plain"`.
    /// - Parameter text: The body text to return. If the `headers` does not provide a
    ///   `"Content-Length"` header, one is synthesized from the text.
    /// - Parameter delay: (Optional) The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    /// - Returns: A copy of `self` that returns a mock plain text response.
    public func mock(statusCode: Int, headers: [String: String] = [:], text: String, delay: TimeInterval = 0.03) -> Self {
        let data = text.data(using: String.Encoding.utf8) ?? Data()
        var headers = headers
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "text/plain; charset=utf-8"
        }
        return mock(statusCode: statusCode, headers: headers, data: data, delay: delay)
    }
    
    /// Returns a new request that returns a mock JSON response.
    ///
    /// - Parameter statusCode: The HTTP status code to return.
    /// - Parameter headers: (Optional) A collection of HTTP headers to return. If `"Content-Type"`
    ///   is not specified, it will default to `"application/json"`.
    /// - Parameter json: The JSON body of the response. If the `headers` does not provide a
    ///   `"Content-Length"` header, one is synthesized from the encoded JSON.
    /// - Parameter delay: (Optional) The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    /// - Returns: A copy of `self` that returns a mock JSON response.
    public func mock(statusCode: Int, headers: [String: String] = [:], json: JSON, delay: TimeInterval = 0.03) -> Self {
        let data = JSON.encodeAsData(json)
        var headers = headers
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json"
        }
        return mock(statusCode: statusCode, headers: headers, data: data, delay: delay)
    }
}

public extension HTTPManagerParseRequest {
    /// Returns a new request that returns a mock response.
    ///
    /// Requests with a mock response will not hit the network and will not invoke the
    /// parse handler.
    ///
    /// Any network mock inherited from an `HTTPManagerNetworkRequest` will be overwritten
    /// by this method.
    ///
    /// - Parameter headers: (Optional) A collection of HTTP headers to return.
    /// - Parameter value: The parsed value to return.
    /// - Parameter delay: (Optional) The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    /// - Returns: A copy of `self` that returns a mock response.
    ///
    /// - Note: If the parse result type `T` is `JSON` and `headers` does not define the
    ///   `"Content-Type"` header, a default value of `"application/json"` will be used.
    public func mock(headers: [String: String] = [:], value: T, delay: TimeInterval = 0.03) -> Self {
        let newRequest = type(of: self).init(__copyOfRequest: self)
        var headers = headers
        if T.self is JSON.Type && headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json"
        }
        // Add a network mock that returns a 200 response with no data.
        newRequest.mock = HTTPMockInstance(queue: DispatchQueue.global(qos: .utility), parameters: [:], handler: { (request, parameters, completion) in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            if delay > 0 {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + delay) {
                    autoreleasepool {
                        completion(response, Data())
                    }
                }
            } else {
                completion(response, Data())
            }
        })
        // NB: Don't use @autoclosure(escaping) on `value` because that has surprising behavior when
        // closing over a mutable variable (e.g. it doesn't make a copy of the value).
        newRequest.dataMock = { value }
        return newRequest
    }
}

public extension HTTPManagerObjectParseRequest {
    /// Returns a new request that returns a mock response.
    ///
    /// Requests with a mock response will not hit the network and will not invoke the
    /// parse handler.
    ///
    /// Any network mock inherited from an `HTTPManagerNetworkRequest` will be overwritten
    /// by this method.
    ///
    /// - Parameter value: The parsed value to return.
    /// - Returns: A copy of `self` that returns a mock response.
    ///
    /// - SeeAlso: `mock(headers:value:delay:)`.
    @objc public func mock(_ value: Any?) -> HTTPManagerObjectParseRequest {
        return HTTPManagerObjectParseRequest(request: _request.mock(value: value))
    }
    
    /// Returns a new request that returns a mock response.
    ///
    /// Requests with a mock response will not hit the network and will not invoke the
    /// parse handler.
    ///
    /// Any network mock inherited from an `HTTPManagerNetworkRequest` will be overwritten
    /// by this method.
    ///
    /// - Parameter headers: A collection of HTTP headers to return.
    /// - Parameter value: The parsed object to return.
    /// - Parameter delay: The amount of time in seconds to wait before returning the
    ///   response. The default value is 30ms.
    /// - Returns: A copy of `self` that returns a mock response.
    @objc public func mock(headers: [String: String], value: Any?, delay: TimeInterval) -> HTTPManagerObjectParseRequest {
        return HTTPManagerObjectParseRequest(request: _request.mock(headers: headers, value: value, delay: delay))
    }
}

/// A token that can be used to unregister a mock from an `HTTPMockManager`.
@objc public protocol HTTPMockToken {}

internal class HTTPMock: HTTPMockToken, CustomStringConvertible {
    enum MatchResult {
        case noMatch
        case matches(parameters: [String: String])
    }
    
    let handleURL: (URLComponents, _ httpMethod: String?, _ environment: HTTPManager.Environment?) -> MatchResult
    
    fileprivate let handler: (_ request: URLRequest, _ parameters: [String: String], _ completion: @escaping (_ response: HTTPURLResponse, _ body: Data) -> Void) -> Void
    fileprivate let queue: DispatchQueue
    /// The `url` parameter provided to `init`. Only used for `description`.
    private let urlString: String
    /// The `httpMethod` parameter provided to `init`. Only used for `description`.
    private let httpMethod: String?
    
    init(url: String, httpMethod: String?, queue: DispatchQueue, handler: @escaping (_ request: URLRequest, _ parameters: [String: String], _ completion: @escaping (_ response: HTTPURLResponse, _ body: Data) -> Void) -> Void) {
        urlString = url
        self.httpMethod = httpMethod
        self.queue = queue
        self.handler = handler
        // NB: URLComponents parses ":foo/bar" as a path but URL does not.
        guard var comps = URLComponents(string: url) else {
            NSLog("[HTTPManager] Warning: Mock was added with the URL \(String(reflecting: url)) but the URL could not be parsed, so the mock will never match.")
            handleURL = { _ in .noMatch}
            return
        }
        // Don't convert comps into absolute yet as environment changes should affect relative mocks.
        // But do parse out the :tokens right now so that way :tokens in the environment path aren't treated as parameters.
        enum Component {
            case string(Swift.String)
            case token(Swift.String)
            init(_ string: Swift.String) {
                if string.hasPrefix(":") && string != ":" {
                    self = .token(Swift.String(string.unicodeScalars.dropFirst()))
                } else {
                    self = .string(string)
                }
            }
        }
        let mockComps: [Component]
        do {
            var pathComps = comps.pathComponents ?? []
            // Drop the leading "/" if present since we'll test that against the absolute path instead.
            if pathComps.first == "/" {
                pathComps.removeFirst()
                comps.percentEncodedPath = "/"
            } else {
                comps.percentEncodedPath = ""
            }
            mockComps = pathComps.map(Component.init)
        }
        
        handleURL = { (requestComponents, requestMethod, environment) in
            // Compare HTTP method
            switch (httpMethod, requestMethod) {
            case (nil, _): break
            case let (a?, b?) where a.caseInsensitiveCompare(b) == .orderedSame: break
            default: return .noMatch
            }
            
            // Compare URL
            let absoluteComps: URLComponents
            if comps.scheme != nil {
                // Absolute URL.
                absoluteComps = comps
            } else {
                // Relative URL.
                guard let environment = environment,
                    let baseComps = URLComponents(url: environment.baseURL as URL, resolvingAgainstBaseURL: true)
                    else { return .noMatch }
                absoluteComps = comps.componentsRelativeTo(baseComps)
            }
            guard requestComponents.matchesComponents(absoluteComps, includePath: false) else { return .noMatch }
            guard let requestPathComps = requestComponents.pathComponents.map({ $0.isEmpty ? ["/"] : $0 }),
                let pathComps = absoluteComps.pathComponents.map({ $0.isEmpty ? ["/"] : $0 })
                else { return .noMatch }
            guard requestPathComps.count == (pathComps.count + mockComps.count) else { return .noMatch }
            // Walk the paths and handle any :name tokens (if any).
            var parameters: [String: String] = [:]
            for (urlComp, comp) in zip(requestPathComps, pathComps.lazy.map(Component.string).chain(mockComps)) {
                switch comp {
                case .string(urlComp): break
                case .token(let token):
                    parameters[token] = urlComp
                case .string: return .noMatch
                }
            }
            return .matches(parameters: parameters)
        }
    }
    
    var description: String {
        // FIXME: Use ObjectIdentifier.address or whatever it's called once it's available
        #if swift(>=3.1)
            let ptr = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        #else
            let ptr = unsafeBitCast(Unmanaged.passUnretained(self).toOpaque(), to: UInt.self)
        #endif
        return "<HTTPMock: 0x\(String(ptr, radix: 16)) \(String(reflecting: urlString))\(httpMethod.map({ " \($0)" }) ?? "")>"
    }
}

internal class HTTPMockInstance {
    let parameters: [String: String]
    
    fileprivate let handler: (_ request: URLRequest, _ parameters: [String: String], _ completion: @escaping (_ response: HTTPURLResponse, _ body: Data) -> Void) -> Void
    
    fileprivate let queue: DispatchQueue
    
    init(queue: DispatchQueue, parameters: [String: String], handler: @escaping (_ request: URLRequest, _ parameters: [String: String], _ completion: @escaping (_ response: HTTPURLResponse, _ body: Data) -> Void) -> Void) {
        self.queue = queue
        self.parameters = parameters
        self.handler = handler
    }
    
    static let unhandledURLMock = HTTPMockInstance(queue: DispatchQueue.global(qos: .utility), parameters: [:]) { (request, parameters, completion) in
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain; charset=utf-8"])!
        let data = "No mock found for URL.".data(using: String.Encoding.utf8)!
        completion(response, data)
    }
}

private extension URLComponents {
    /// Returns `true` if `self` matches `components`, otherwise `false`.
    /// Any `nil` value in `components` matches any value in `self`, except for
    /// the `port`. If `components` does not specify a `port`, the default port
    /// is assumed (for http and https only).
    /// If `components` specifies a query, the specified query items must match
    /// exactly, but `self` is allowed to have other query items. The order of
    /// query items is ignored.
    /// Any fragment is ignored.
    /// The path is compared only if the `includePath` parameter is `true`.
    func matchesComponents(_ components: URLComponents, includePath: Bool) -> Bool {
        func getPort(_ components: URLComponents, fallbackScheme: String? = nil) -> Int? {
            if let port = components.port { return port as Int }
            switch components.scheme ?? fallbackScheme {
            case CaseInsensitiveASCIIString("http")?: return 80
            case CaseInsensitiveASCIIString("https")?: return 443
            default: return nil
            }
        }
        func caseInsensitiveCompare(_ a: String?, _ b: String?) -> Bool {
            return a.map({CaseInsensitiveASCIIString($0)}) == b.map({CaseInsensitiveASCIIString($0)})
        }
        guard (components.scheme.map({ caseInsensitiveCompare(scheme, $0) }) ?? true)
            && (components.percentEncodedHost.map({ caseInsensitiveCompare(percentEncodedHost, $0) }) ?? true)
            && (components.percentEncodedUser.map({ caseInsensitiveCompare(percentEncodedUser, $0) }) ?? true)
            && (components.percentEncodedPassword.map({ caseInsensitiveCompare(percentEncodedPassword, $0) }) ?? true)
            && getPort(self) == getPort(components, fallbackScheme: scheme)
            else { return false }
        if includePath {
            // if `self` or `components` has a non-parseable path we treat that as a match failure
            guard let ourPath = pathComponents, let theirPath = components.pathComponents,
                ourPath == theirPath
                else { return false }
        }
        if let queryItems = components.queryItems, !queryItems.isEmpty {
            var querySet = Set(queryItems)
            querySet.subtract(self.queryItems ?? [])
            if !querySet.isEmpty {
                // `components` had a query item that we don't
                return false
            }
        }
        return true
    }
    
    /// An array containing the path components.
    ///
    /// The array contains the individual path components unescaped using `stringByRemovingPercentEncoding`.
    /// If the path begins with `"/"` the returned array will start with the component `"/"`.
    /// Doubled slashes in the path (e.g. `"foo//bar"`) or a trailing slash will be ignored.
    ///
    /// - Returns: An array containing the path components, or `nil` if the path contains an illegal
    ///   percent-encoding sequence. If `self` has no path, `[]` will be returned.
    var pathComponents: [String]? {
        let path = percentEncodedPath
        guard !path.isEmpty else { return [] }
        let comps = path.unicodeScalars.split(separator: "/")
        let hasLeadingSlash = path.hasPrefix("/")
        var result: [String] = []
        result.reserveCapacity(comps.count + (hasLeadingSlash ? 1 : 0))
        if hasLeadingSlash {
            result.append("/")
        }
        for comp in comps {
            guard let elt = String(comp).removingPercentEncoding else {
                return nil
            }
            result.append(elt)
        }
        return result
    }
    
    /// Returns a `URLComponents` that represents `self` resolved against a base components.
    ///
    /// This is roughly equivalent to `URLComponents.url(relativeTo:)?.absoluteURL` except
    /// it doesn't touch `URL` and so preserves RFC 3986 behavior throughout. Notably, this
    /// correctly handles paths beginning with `:`.
    func componentsRelativeTo(_ components: URLComponents) -> URLComponents {
        var result: URLComponents = self
        guard result.scheme == nil else {
            // URL is absolute. We still return a copy so the caller can mutate the result.
            return result
        }
        result.scheme = components.scheme
        // The authority section is all-or-none, e.g. if we have a host, we don't copy the user/password from components.
        guard !result.hasAuthority else { return result }
        (result.percentEncodedUser, result.percentEncodedPassword) = (components.percentEncodedUser, components.percentEncodedPassword)
        (result.percentEncodedHost, result.port) = (components.percentEncodedHost, components.port)
        if case let path = result.percentEncodedPath, !path.isEmpty {
            if !path.hasPrefix("/") {
                // relative path
                if case let basePath = components.percentEncodedPath, !basePath.isEmpty {
                    result.percentEncodedPath = basePath.hasSuffix("/") ? "\(basePath)\(path)" : "\(basePath)/\(path)"
                } else if !result.startsWithPath {
                    // We need a / prefix
                    result.percentEncodedPath = "/\(path)"
                }
            }
            return result
        }
        result.percentEncodedPath = components.percentEncodedPath
        guard result.percentEncodedQuery == nil else { return result }
        result.percentEncodedQuery = components.percentEncodedQuery
        guard result.percentEncodedFragment == nil else { return result }
        result.percentEncodedFragment = components.percentEncodedFragment
        return result
    }
    
    /// `true` iff `self` starts with a (non-empty) path.
    var startsWithPath: Bool {
        if #available(iOS 9, OSX 10.11, *) {
            guard let range = rangeOfPath, !range.isEmpty else { return false }
            return range.lowerBound == string?.startIndex
        } else {
            return scheme == nil && !hasAuthority && !percentEncodedPath.isEmpty
        }
    }
    
    /// `true` iff `self` has an authority component (user, password, host, or port).
    var hasAuthority: Bool {
        // If user/password are `""` that counts, but `host` may be `""` without affecting anything,
        // because the former produces a URL like `//@` and the latter just produces `//`
        return percentEncodedUser != nil || percentEncodedPassword != nil
            || !(percentEncodedHost?.isEmpty ?? true) || port != nil
    }
}

internal class HTTPMockURLProtocol: URLProtocol {
    static let requestProperty = "com.postmates.PMHTTP.mock"
    
    private let mock: HTTPMockInstance
    private let queue = DispatchQueue(label: "HTTPMockURLProtocol queue")
    private var loading: Bool = false
    
    override class func canInit(with request: URLRequest) -> Bool {
        return URLProtocol.property(forKey: requestProperty, in: request) is HTTPMockInstance
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        // We ignore caching, so it should be safe to avoid canonicalizing the request as well.
        return request
    }
    
    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        guard let mock = URLProtocol.property(forKey: HTTPMockURLProtocol.requestProperty, in: request) as? HTTPMockInstance else {
            fatalError("HTTPMockURLProtocol: Could not find HTTPMockInstance for request")
        }
        self.mock = mock
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }
    
    override func startLoading() {
        guard request.url != nil else {
            // I don't know how a URLRequest URL can be nil but we can't evaluate our mock if it is.
            struct InvalidURLError: Error {}
            client?.urlProtocol(self, didFailWithError: InvalidURLError())
            return
        }
        queue.async { 
            self.loading = true
        }
        mock.queue.async {
            autoreleasepool {
                self.mock.handler(self.request, self.mock.parameters) { (response, body) in
                    self.queue.async {
                        guard self.loading else { return }
                        autoreleasepool {
                            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                            if !body.isEmpty {
                                self.client?.urlProtocol(self, didLoad: body)
                            }
                            self.client?.urlProtocolDidFinishLoading(self)
                        }
                    }
                }
            }
        }
    }
    
    override func stopLoading() {
        queue.sync { 
            self.loading = false
        }
    }
}
