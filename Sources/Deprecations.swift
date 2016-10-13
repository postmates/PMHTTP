//
//  Deprecations.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 9/21/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Foundation

public extension HTTPManager {
    @available(*, unavailable, renamed: "parsedDateHeader(from:)")
    @nonobjc static func parsedDateHeaderFromResponse(_ response: URLResponse) -> Date? {
        return parsedDateHeader(from: response)
    }
    
    @available(*, unavailable, renamed: "parsedDateHeader(from:)")
    @nonobjc static func parsedDateHeaderFromString(_ string: String) -> Date? {
        return parsedDateHeader(from: string)
    }
}

public extension HTTPManagerEnvironment {
    @available(*, unavailable, renamed: "isPrefix(of:)")
    @nonobjc func isPrefixOf(_ url: URL) -> Bool {
        return isPrefix(of: url)
    }
}

public extension HTTPManagerError {
    @available(*, unavailable, renamed: "failedResponse")
    static func FailedResponse(statusCode: Int, response: HTTPURLResponse, body: Data, bodyJson: JSON?) -> HTTPManagerError {
        return .failedResponse(statusCode: statusCode, response: response, body: body, bodyJson: bodyJson)
    }
    
    @available(*, unavailable, renamed: "unauthorized")
    static func Unauthorized(credential: URLCredential?, response: HTTPURLResponse, body: Data, bodyJson: JSON?) -> HTTPManagerError {
        return .unauthorized(credential: credential, response: response, body: body, bodyJson: bodyJson)
    }
    
    @available(*, unavailable, renamed: "unexpectedContentType")
    static func UnexpectedContentType(contentType: String, response: HTTPURLResponse, body: Data) -> HTTPManagerError {
        return .unexpectedContentType(contentType: contentType, response: response, body: body)
    }
    
    @available(*, unavailable, renamed: "unexpectedNoContent")
    static func UnexpectedNoContent(response: HTTPURLResponse) -> HTTPManagerError {
        return .unexpectedNoContent(response: response)
    }
    
    @available(*, unavailable, renamed: "unexpectedRedirect")
    static func UnexpectedRedirect(statusCode: Int, location: URL?, response: HTTPURLResponse, body: Data) -> HTTPManagerError {
        return .unexpectedRedirect(statusCode: statusCode, location: location, response: response, body: body)
    }
}

public extension HTTPManagerActionRequest.JSONResult {
    @available(*, unavailable, renamed: "noContent")
    static func NoContent(_ response: HTTPURLResponse) -> HTTPManagerActionRequest.JSONResult {
        return .noContent(response)
    }
    
    @available(*, unavailable, renamed: "success")
    static func Success(_ response: URLResponse, _ json: JSON) -> HTTPManagerActionRequest.JSONResult {
        return .success(response, json)
    }
}

// NB: Can't move the HTTPManagerConfigurable deprecation here as it must be in the protocol declaration

public extension HTTPManagerNetworkRequest {
    @available(*, unavailable, renamed: "parse(with:)")
    @nonobjc func parseWithHandler<T>(_ handler: @escaping (_ response: URLResponse, _ data: Data) throws -> T) -> HTTPManagerParseRequest<T> {
        return parse(with: handler)
    }
    
    @available(*, unavailable, renamed: "createTask(withCompletionQueue:completion:)")
    @nonobjc func createTaskWithCompletion(onQueue queue: OperationQueue? = nil, _ handler: @escaping (_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<Data>) -> Void) -> HTTPManagerTask {
        return createTask(withCompletionQueue: queue, completion: handler)
    }
}

extension HTTPManagerRequestPerformable {
    @available(*, unavailable, renamed: "performRequest(withCompletionQueue:completion:)")
    public func performRequestWithCompletion(onQueue queue: OperationQueue? = nil, _ handler: @escaping (_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<ResultValue>) -> Void) -> HTTPManagerTask {
        return performRequest(withCompletionQueue: queue, completion: handler)
    }
}

public extension HTTPManagerDataRequest {
    @available(*, unavailable, renamed: "parseAsJSON(with:)")
    @nonobjc public func parseAsJSONWithHandler<T>(_ handler: @escaping (_ response: URLResponse, _ json: JSON) throws -> T) -> HTTPManagerParseRequest<T> {
        return parseAsJSON(with: handler)
    }
}

public extension HTTPManagerParseRequest {
    @available(*, unavailable, renamed: "createTask(withCompletionQueue:completion:)")
    @nonobjc public func createTaskWithCompletion(onQueue queue: OperationQueue? = nil, _ handler: @escaping (_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<T>) -> Void) -> HTTPManagerTask {
        return createTask(withCompletionQueue: queue, completion: handler)
    }
}

public extension HTTPManagerActionRequest {
    @available(*, unavailable, renamed: "parseAsJSON(with:)")
    @nonobjc public func parseAsJSONWithHandler<T>(_ handler: @escaping (_ result: JSONResult) throws -> T) -> HTTPManagerParseRequest<T> {
        return parseAsJSON(with: handler)
    }
}

public extension HTTPManagerUploadFormRequest {
    @available(*, unavailable, renamed: "addMultipart(data:withName:mimeType:filename:)")
    @nonobjc public func addMultipartData(_ data: Data, withName name: String, mimeType: String? = nil, filename: String? = nil) {
        addMultipart(data: data, withName: name, mimeType: mimeType, filename: filename)
    }
    
    @available(*, unavailable, renamed: "addMultipart(text:withName:)")
    @nonobjc public func addMultipartText(_ text: String, withName name: String) {
        addMultipart(text: text, withName: name)
    }
    
    @available(*, unavailable, renamed: "addMultipartBody(with:)")
    @nonobjc public func addMultipartBodyWithBlock(_ block: @escaping (HTTPManagerUploadMultipart) -> Void) {
        addMultipartBody(with: block)
    }
}

public extension HTTPManagerUploadMultipart {
    @available(*, unavailable, renamed: "addMultipart(data:withName:mimeType:filename:)")
    @nonobjc public func addMultipartData(_ data: Data, withName name: String, mimeType: String? = nil, filename: String? = nil) {
        addMultipart(data: data, withName: name, mimeType: mimeType, filename: filename)
    }
    
    @available(*, unavailable, renamed: "addMultipart(text:withName:)")
    @nonobjc public func addMultipartText(_ text: String, withName name: String) {
        addMultipart(text: text, withName: name)
    }
}

public extension HTTPManagerTaskState {
    @available(*, unavailable, renamed: "running")
    static let Running = HTTPManagerTaskState.running
    
    @available(*, unavailable, renamed: "processing")
    static let Processing = HTTPManagerTaskState.processing
    
    @available(*, unavailable, renamed: "canceled")
    static let Canceled = HTTPManagerTaskState.canceled
    
    @available(*, unavailable, renamed: "completed")
    static let Completed = HTTPManagerTaskState.completed
}

public extension HTTPManagerTaskResult {
    @available(*, unavailable, renamed: "success")
    static func Success(_ response: URLResponse, _ value: Value) -> HTTPManagerTaskResult {
        return .success(response, value)
    }
    
    @available(*, unavailable, renamed: "error")
    static func Error(_ response: URLResponse?, _ error: Error) -> HTTPManagerTaskResult {
        return .error(response, error)
    }
    
    @available(*, unavailable, renamed: "canceled")
    static var Canceled: HTTPManagerTaskResult { return .canceled }
}

public extension HTTPMockManager {
    @available(*, unavailable, renamed: "addMock(for:httpMethod:statusCode:headers:data:delay:)")
    @discardableResult
    @nonobjc public func addMock(_ url: String, httpMethod: String? = nil, statusCode: Int, headers: [String: String] = [:], data: Data = Data(), delay: TimeInterval = 0.03) -> HTTPMockToken {
        return addMock(for: url, httpMethod: httpMethod, statusCode: statusCode, headers: headers, data: data, delay: delay)
    }
    
    @available(*, unavailable, renamed: "addMock(for:httpMethod:statusCode:headers:text:delay:)")
    @discardableResult
    @nonobjc public func addMock(_ url: String, httpMethod: String? = nil, statusCode: Int, headers: [String: String] = [:], text: String, delay: TimeInterval = 0.03) -> HTTPMockToken {
        return addMock(for: url, httpMethod: httpMethod, statusCode: statusCode, headers: headers, text: text, delay: delay)
    }
    
    @available(*, unavailable, renamed: "addMock(for:httpMethod:statusCode:headers:json:delay:)")
    @discardableResult
    @nonobjc public func addMock(_ url: String, httpMethod: String? = nil, statusCode: Int, headers: [String: String] = [:], json: JSON, delay: TimeInterval = 0.03) -> HTTPMockToken {
        return addMock(for: url, httpMethod: httpMethod, statusCode: statusCode, headers: headers, json: json, delay: delay)
    }
    
    @available(*, unavailable, renamed: "addMock(for:httpMethod:sequence:)")
    @discardableResult
    @nonobjc public func addMock(_ url: String, httpMethod: String? = nil, sequence: HTTPMockSequence) -> HTTPMockToken {
        return addMock(for: url, httpMethod: httpMethod, sequence: sequence)
    }
    
    @available(*, unavailable, renamed: "addMock(for:httpMethod:queue:handler:)")
    @discardableResult
    @nonobjc public func addMock(_ url: String, httpMethod: String? = nil, queue: DispatchQueue? = nil, handler: @escaping (_ request: URLRequest, _ parameters: [String: String], _ completion: @escaping (_ response: HTTPURLResponse, _ body: Data) -> Void) -> Void) -> HTTPMockToken {
        return addMock(for: url, httpMethod: httpMethod, queue: queue, handler: handler)
    }
    
    @available(*, unavailable, renamed: "addMock(for:httpMethod:state:handler:)")
    @discardableResult
    @nonobjc public func addMock<T>(_ url: String, httpMethod: String? = nil, state: T, handler: @escaping (_ state: inout T, _ request: URLRequest, _ parameters: [String: String], _ completion: @escaping (_ response: HTTPURLResponse, _ body: Data) -> Void) -> Void) -> HTTPMockToken {
        return addMock(for: url, httpMethod: httpMethod, state: state, handler: handler)
    }
}

public extension HTTPMockSequence {
    @available(*, unavailable, renamed: "addMock(statusCode:headers:data:delay:)")
    @nonobjc public func addMock(_ statusCode: Int, headers: [String: String] = [:], data: Data = Data(), delay: TimeInterval = 0.03) {
        addMock(statusCode: statusCode, headers: headers, data: data, delay: delay)
    }
    
    @available(*, unavailable, renamed: "addMock(statusCode:headers:text:delay:)")
    @nonobjc public func addMock(_ statusCode: Int, headers: [String: String] = [:], text: String, delay: TimeInterval = 0.03) {
        addMock(statusCode: statusCode, headers: headers, text: text, delay: delay)
    }
    
    @available(*, unavailable, renamed: "addMock(statusCode:headers:json:delay:)")
    @nonobjc public func addMock(_ statusCode: Int, headers: [String: String] = [:], json: JSON, delay: TimeInterval = 0.03) {
        addMock(statusCode: statusCode, headers: headers, json: json, delay: delay)
    }
}

public extension HTTPManagerObjectParseRequest {
    @available(*, unavailable, renamed: "createTask(withCompletionQueue:completion:)")
    @nonobjc public func createTaskWithCompletion(onQueue queue: OperationQueue? = nil, _ handler: @escaping (_ task: HTTPManagerTask, _ result: HTTPManagerTaskResult<Any?>) -> Void) -> HTTPManagerTask {
        return createTask(withCompletionQueue: queue, completion: handler)
    }
}
