//
//  PMHTTPTestCase.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 1/22/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import XCTest
@testable import PMHTTP

class PMHTTPTestCase: XCTestCase {
    static var httpServer: HTTPServer!
    static var cacheConfigured = false
    
    #if os(OSX)
    static var _workaroundXCTestTimeoutTimer: DispatchSourceTimer?
    #endif
    
    class override func setUp() {
        super.setUp()
        #if os(OSX)
            // Xcode 8 on OS X 10.11 has a weird bug where it frequently waits for the full timeout for expectations
            // even though all expectations have been fulfilled. It turns out that merely dispatching a block to the
            // main queue while it's waiting is enough to cause it to wake up and realize that it's done.
            // So we'll set up a timer that runs on the main queue every 50ms, to keep the tests nice and speedy.
            // Filed as rdar://problem/28064036.
            if _workaroundXCTestTimeoutTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue: .main)
                _workaroundXCTestTimeoutTimer = timer
                timer.setEventHandler {}
                let interval = DispatchTimeInterval.milliseconds(50)
                timer.scheduleRepeating(deadline: .now() + interval, interval: interval)
                timer.resume()
            }
        #endif
        httpServer = try! HTTPServer()
        if !cacheConfigured {
            // Bypass the shared URL cache and use an in-memory cache only.
            // This avoids issues seen with the on-disk cache being locked when we try to remove cached responses.
            let config = HTTP.sessionConfiguration
            config.urlCache = URLCache(memoryCapacity: 20*1024*1024, diskCapacity: 0, diskPath: nil)
            HTTP.sessionConfiguration = config
            cacheConfigured = true
        }
    }
    
    class override func tearDown() {
        httpServer.invalidate()
        httpServer = nil
        HTTP.resetSession()
        HTTP.mockManager.reset()
        super.tearDown()
    }
    
    override func setUp() {
        super.setUp()
        httpServer.reset()
        HTTP.environment = HTTPManagerEnvironment(string: "http://\(httpServer.address)")!
        HTTP.sessionConfiguration.urlCache?.removeAllCachedResponses()
        HTTP.defaultCredential = nil
        HTTP.defaultRetryBehavior = nil
    }
    
    override func tearDown() {
        httpServer.reset()
        HTTP.resetSession()
        HTTP.mockManager.reset()
        super.tearDown()
    }
    
    var httpServer: HTTPServer! {
        return PMHTTPTestCase.httpServer
    }
    
    private let expectationTasks: Locked<[HTTPManagerTask]> = Locked([])
    
    @available(*, unavailable)
    override func waitForExpectations(timeout: TimeInterval, handler: XCWaitCompletionHandler?) {
        waitForExpectations(timeout: timeout, file: #file, line: #line, handler: handler)
    }
    
    func waitForExpectations(timeout: TimeInterval, file: StaticString = #file, line: UInt = #line, handler: XCWaitCompletionHandler?) {
        var setUnhandledRequestCallback = false
        if httpServer.unhandledRequestCallback == nil {
            setUnhandledRequestCallback = true
            httpServer.unhandledRequestCallback = { request, response, completionHandler in
                XCTFail("Unhandled request \(request)", file: file, line: line)
                completionHandler(HTTPServer.Response(status: .notFound, text: "Unhandled request"))
            }
        }
        super.waitForExpectations(timeout: timeout) { error in
            if error != nil {
                // timeout
                var outstandingTasks: String = ""
                self.expectationTasks.with { tasks in
                    outstandingTasks = String(describing: tasks)
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
    
    @discardableResult
    func expectationForRequestSuccess<Request: HTTPManagerRequest>(
        _ request: Request, queue: OperationQueue? = nil, startAutomatically: Bool = true, file: StaticString = #file, line: UInt = #line,
        completion: @escaping (_ task: HTTPManagerTask, _ response: URLResponse, _ value: Request.ResultValue) -> Void = { _ in () }
        ) -> HTTPManagerTask
        where Request: HTTPManagerRequestPerformable
    {
        let expectation = self.expectation(description: "\(request.requestMethod) request for \(request.url)")
        let task = request.createTask(withCompletionQueue: queue) { [expectationTasks, weak expectation] task, result in
            if case let .success(response, value) = result {
                completion(task, response, value)
            }
            DispatchQueue.main.async {
                switch result {
                case .success: break
                case .error(_, let error):
                    XCTFail("network request error: \(error)", file: file, line: line)
                case .canceled:
                    XCTFail("network request canceled", file: file, line: line)
                }
                expectationTasks.with { tasks in
                    if let idx = tasks.index(where: { $0 === task }) {
                        tasks.remove(at: idx)
                    }
                }
                expectation?.fulfill()
            }
        }
        expectationTasks.with { tasks in
            let _ = tasks.append(task)
        }
        if startAutomatically {
            task.resume()
        }
        return task
    }
    
    @discardableResult
    func expectationForRequestFailure<Request: HTTPManagerRequest>(
        _ request: Request, queue: OperationQueue? = nil, startAutomatically: Bool = true, file: StaticString = #file, line: UInt = #line,
        completion: @escaping (_ task: HTTPManagerTask, _ response: URLResponse?, _ error: Error) -> Void = { _ in () }
        ) -> HTTPManagerTask
        where Request: HTTPManagerRequestPerformable
    {
        let expectation = self.expectation(description: "\(request.requestMethod) request for \(request.url)")
        let task = request.createTask(withCompletionQueue: queue) { [expectationTasks, weak expectation] task, result in
            if case let .error(response, error) = result {
                completion(task, response, error)
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let response, _):
                    XCTFail("network request expected failure but was successful: \(response)", file: file, line: line)
                case .error: break
                case .canceled:
                    XCTFail("network request canceled", file: file, line: line)
                }
                expectationTasks.with { tasks in
                    if let idx = tasks.index(where: { $0 === task }) {
                        tasks.remove(at: idx)
                    }
                }
                expectation?.fulfill()
            }
        }
        expectationTasks.with { tasks in
            let _ = tasks.append(task)
        }
        if startAutomatically {
            task.resume()
        }
        return task
    }
    
    @discardableResult
    func expectationForRequestCanceled<Request: HTTPManagerRequest>(
        _ request: Request, queue: OperationQueue? = nil, startAutomatically: Bool = true, file: StaticString = #file, line: UInt = #line,
        completion: @escaping (_ task: HTTPManagerTask) -> Void = { _ in () }
        ) -> HTTPManagerTask
        where Request: HTTPManagerRequestPerformable
    {
        let expectation = self.expectation(description: "\(request.requestMethod) request for \(request.url)")
        let task = request.createTask(withCompletionQueue: queue) { [expectationTasks, weak expectation] task, result in
            if case .canceled = result {
                completion(task)
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let response, _):
                    XCTFail("network request expected cancellation but was successful: \(response)", file: file, line: line)
                case .error(_, let error):
                    XCTFail("network request error: \(error)", file: file, line: line)
                case .canceled: break
                }
                expectationTasks.with { tasks in
                    if let idx = tasks.index(where: { $0 === task }) {
                        tasks.remove(at: idx)
                    }
                }
                expectation?.fulfill()
            }
        }
        expectationTasks.with { tasks in
            let _ = tasks.append(task)
        }
        if startAutomatically {
            task.resume()
        }
        return task
    }
}

private final class Locked<T> {
    let _lock: NSLock = NSLock()
    var _value: T
    
    init(_ value: T) {
        _value = value
    }
    
    func with<R>(_ f: (inout T) -> R) -> R {
        _lock.lock()
        defer { _lock.unlock() }
        return f(&_value)
    }
}

extension HTTPServer.Method {
    init(_ requestMethod: HTTPManagerRequest.Method) {
        switch requestMethod {
        case .GET: self = .GET
        case .POST: self = .POST
        case .PUT: self = .PUT
        case .PATCH: self = .PATCH
        case .DELETE: self = .DELETE
        }
    }
}
