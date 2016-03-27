//
//  PMHTTPTestCase.swift
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 1/22/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

import XCTest
@testable import PMHTTP

class PMHTTPTestCase: XCTestCase {
    static var httpServer: HTTPServer!
    
    class override func setUp() {
        super.setUp()
        httpServer = try! HTTPServer()
    }
    
    class override func tearDown() {
        httpServer.invalidate()
        httpServer = nil
        HTTP.resetSession()
        super.tearDown()
    }
    
    override func setUp() {
        super.setUp()
        httpServer.reset()
        HTTP.environment = HTTPManagerEnvironment(string: "http://\(httpServer.address)")!
        HTTP.sessionConfiguration.URLCache?.removeAllCachedResponses()
    }
    
    override func tearDown() {
        httpServer.reset()
        HTTP.resetSession()
        super.tearDown()
    }
    
    var httpServer: HTTPServer! {
        return PMHTTPTests.httpServer
    }
    
    private let expectationTasks: Locked<[HTTPManagerTask]> = Locked([])
    
    @available(*, unavailable)
    override func waitForExpectationsWithTimeout(timeout: NSTimeInterval, handler: XCWaitCompletionHandler?) {
        waitForExpectationsWithTimeout(timeout, file: #file, line: #line, handler: handler)
    }
    
    func waitForExpectationsWithTimeout(timeout: NSTimeInterval, file: StaticString = #file, line: UInt = #line, handler: XCWaitCompletionHandler?) {
        var setUnhandledRequestCallback = false
        if httpServer.unhandledRequestCallback == nil {
            setUnhandledRequestCallback = true
            httpServer.unhandledRequestCallback = { request, response, completionHandler in
                XCTFail("Unhandled request \(request)", file: file, line: line)
            }
        }
        super.waitForExpectationsWithTimeout(timeout) { error in
            if error != nil {
                // timeout
                var outstandingTasks: String = ""
                self.expectationTasks.with { tasks in
                    outstandingTasks = String(tasks)
                    for task in tasks {
                        task.cancel()
                    }
                    tasks.removeAll()
                }
                let outstandingHandlers = self.clearOutstandingHTTPRequestHandlers()
                XCTFail("Timeout while waiting for expectations with outstanding tasks: \(outstandingTasks), outstanding request handlers: \(outstandingHandlers)", file: file, line: line)
            }
            if setUnhandledRequestCallback {
                self.httpServer.unhandledRequestCallback = nil
            }
            handler?(error)
        }
    }
    
    func expectationForRequestSuccess<Request: HTTPManagerRequest where Request: HTTPManagerRequestPerformable>(
        request: Request, file: StaticString = #file, line: UInt = #line,
        completion: (task: HTTPManagerTask, response: NSURLResponse, value: Request.ResultValue) -> Void
        ) -> HTTPManagerTask
    {
        let expectation = expectationWithDescription("\(request.requestMethod) request for \(request.url)")
        let task = request.performRequestWithCompletion { [expectationTasks] task, result in
            switch result {
            case let .Success(response, value):
                completion(task: task, response: response, value: value)
            case .Error(_, let error):
                XCTFail("network request error: \(error)", file: file, line: line)
            case .Canceled:
                XCTFail("network request canceled", file: file, line: line)
            }
            expectationTasks.with { tasks in
                if let idx = tasks.indexOf({ $0 === task }) {
                    tasks.removeAtIndex(idx)
                }
            }
            expectation.fulfill()
        }
        expectationTasks.with { tasks in
            let _ = tasks.append(task)
        }
        return task
    }
    
    func expectationForRequestFailure<Request: HTTPManagerRequest where Request: HTTPManagerRequestPerformable>(
        request: Request, file: StaticString = #file, line: UInt = #line,
        completion: (task: HTTPManagerTask, response: NSURLResponse?, error: ErrorType) -> Void
        ) -> HTTPManagerTask
    {
        let expectation = expectationWithDescription("\(request.requestMethod) request for \(request.url)")
        return request.performRequestWithCompletion { [expectationTasks] task, result in
            switch result {
            case .Success(let response, _):
                XCTFail("network request expected failure but was successful: \(response)", file: file, line: line)
            case let .Error(response, error):
                completion(task: task, response: response, error: error)
            case .Canceled:
                XCTFail("network request canceled", file: file, line: line)
            }
            expectationTasks.with { tasks in
                if let idx = tasks.indexOf({ $0 === task }) {
                    tasks.removeAtIndex(idx)
                }
            }
            expectation.fulfill()
        }
    }
}

private final class Locked<T> {
    let _lock: NSLock = NSLock()
    var _value: T
    
    init(_ value: T) {
        _value = value
    }
    
    func with<R>(@noescape f: (inout T) -> R) -> R {
        _lock.lock()
        defer { _lock.unlock() }
        return f(&_value)
    }
    
    func with(@noescape f: (inout T) -> Void) {
        _lock.lock()
        defer { _lock.unlock() }
        f(&_value)
    }
}
