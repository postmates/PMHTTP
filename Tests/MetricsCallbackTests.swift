//
//  MetricsCallbackTests.swift
//  PMHTTPTests
//
//  Created by Lily Ballard on 6/15/18.
//  Copyright © 2018 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import XCTest
import PMHTTP

final class MetricsCallbackTests: PMHTTPTestCase {
    override func tearDown() {
        if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *) {
            HTTP.metricsCallback = nil
        }
        super.tearDown()
    }
    
    func testBasicMetrics() {
        if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *) {
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .ok, text: "Hello world"))
            }
            var task: HTTPManagerTask?
            let expectation = self.expectation(description: "task metrics")
            HTTP.metricsCallback = .init(queue: nil, handler: { (task_, networkTask, metrics) in
                XCTAssert(task === task_, "unexpected task")
                expectation.fulfill()
            })
            task = expectationForRequestSuccess(HTTP.request(GET: "foo"), startAutomatically: false)
            task!.resume()
            waitForExpectations(timeout: 1, handler: nil)
        }
    }
    
    func testMetricsQueue() {
        if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *) {
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .ok, text: "Hello world"))
            }
            var task: HTTPManagerTask?
            let operationQueue = OperationQueue()
            let expectation = self.expectation(description: "task metrics")
            HTTP.metricsCallback = .init(queue: operationQueue, handler: { (task_, networkTask, metrics) in
                XCTAssertEqual(OperationQueue.current, operationQueue)
                XCTAssert(task === task_, "unexpected task")
                expectation.fulfill()
            })
            task = expectationForRequestSuccess(HTTP.request(GET: "foo"), startAutomatically: false)
            task!.resume()
            waitForExpectations(timeout: 1, handler: nil)
        }
    }
    
    func testMetricsQueueOrdering() {
        if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *) {
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .ok, text: "Hello world"))
            }
            let operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = 1
            var gotMetrics = false
            var requestFinished = false
            var task: HTTPManagerTask?
            let expectation = self.expectation(description: "task metrics")
            HTTP.metricsCallback = .init(queue: operationQueue, handler: { (task_, networkTask, metrics) in
                XCTAssertEqual(OperationQueue.current, operationQueue)
                XCTAssert(task === task_, "unexpected task")
                XCTAssertFalse(requestFinished, "recieved metrics after task finished")
                gotMetrics = true
                expectation.fulfill()
            })
            task = expectationForRequestSuccess(HTTP.request(GET: "foo"), queue: operationQueue, startAutomatically: false) { (task, response, value) in
                XCTAssertTrue(gotMetrics, "expected to have received metrics already")
                requestFinished = true
            }
            task!.resume()
            waitForExpectations(timeout: 1, handler: nil)
        }
    }
    
    func testMetricsMultipleTimesForRetry() {
        if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *) {
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .internalServerError))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .internalServerError))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .ok))
            }
            let req = HTTP.request(GET: "foo")!
            req.retryBehavior = HTTPManagerRetryBehavior({ (task, error, attempt, callback) in
                callback(attempt < 3)
            })
            var task: HTTPManagerTask?
            let operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = 1
            let expectation = self.expectation(description: "task metrics")
            expectation.expectedFulfillmentCount = 3
            expectation.assertForOverFulfill = true
            HTTP.metricsCallback = .init(queue: operationQueue, handler: { (task_, networkTask, metrics) in
                XCTAssert(task === task_, "unexpected task")
                expectation.fulfill()
            })
            task = expectationForRequestSuccess(req, startAutomatically: false)
            task!.resume()
            waitForExpectations(timeout: 1, handler: nil)
        }
    }
    
    func testSettingMetricsCallbackDoesntInvalidateRunningTasks() {
        if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *) {
            let sema = DispatchSemaphore(value: 0)
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                sema.wait()
                completionHandler(HTTPServer.Response(status: .ok))
            }
            expectationForRequestSuccess(HTTP.request(GET: "foo"), startAutomatically: true)
            HTTP.metricsCallback = .init(queue: nil, handler: { (_, _, _) in }) // this resets the session asynchronously
            _ = HTTP.sessionConfiguration // this waits for the session reset to complete
            sema.signal()
            waitForExpectations(timeout: 1, handler: nil)
        }
    }
    
    func testSettingMetricsCallbackAfterTaskCreationDoesntTrigger() {
        if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *) {
            let sema = DispatchSemaphore(value: 0)
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                sema.wait()
                completionHandler(HTTPServer.Response(status: .ok, text: "Hello world"))
            }
            let operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = 1
            expectationForRequestSuccess(HTTP.request(GET: "foo"), queue: operationQueue, startAutomatically: true)
            let expectation = XCTestExpectation(description: "task metrics")
            expectation.isInverted = true
            HTTP.metricsCallback = .init(queue: operationQueue, handler: { (_, _, _) in
                expectation.fulfill()
            })
            sema.signal()
            waitForExpectations(timeout: 1, handler: nil)
            wait(for: [expectation], timeout: 0)
        }
    }
    
    func testChangingMetricsCallbackAfterTaskCreationInvokesNewCallback() {
        if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *) {
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .ok, text: "Hello world"))
            }
            let expectationFirst = XCTestExpectation(description: "first task metrics")
            expectationFirst.isInverted = true
            HTTP.metricsCallback = .init(queue: nil, handler: { (task_, networkTask, metrics) in
                expectationFirst.fulfill()
            })
            let task = expectationForRequestSuccess(HTTP.request(GET: "foo"), startAutomatically: false)
            let expectationSecond = self.expectation(description: "second task metrics")
            HTTP.metricsCallback = .init(queue: nil, handler: { (task_, networkTask, metrics) in
                XCTAssert(task === task_, "unexpected task")
                expectationSecond.fulfill()
            })
            task.resume()
            waitForExpectations(timeout: 1, handler: nil)
            wait(for: [expectationFirst], timeout: 0)
        }
    }
    
    func testClearingMetricsCallbackAfterTaskRunningDoesntTrigger() {
        if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *) {
            let sema = DispatchSemaphore(value: 0)
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                sema.wait()
                completionHandler(HTTPServer.Response(status: .ok, text: "Hello world"))
            }
            let expectation = XCTestExpectation(description: "task metrics")
            expectation.isInverted = true
            HTTP.metricsCallback = .init(queue: nil, handler: { (_, _, _) in
                expectation.fulfill()
            })
            let operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = 1
            expectationForRequestSuccess(HTTP.request(GET: "foo"), queue: operationQueue, startAutomatically: true)
            HTTP.metricsCallback = nil
            sema.signal()
            waitForExpectations(timeout: 1, handler: nil)
            wait(for: [expectation], timeout: 0)
        }
    }
}
