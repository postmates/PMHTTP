//
//  MetricsCallbackTests.swift
//  PMHTTPTests
//
//  Created by Kevin Ballard on 6/15/18.
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
            let task = expectationForRequestSuccess(HTTP.request(GET: "foo"), startAutomatically: false)
            let expectation = self.expectation(description: "task metrics")
            HTTP.metricsCallback = .init(queue: nil, callback: { (task_, metrics) in
                XCTAssert(task === task_, "unexpected task")
                expectation.fulfill()
            })
            task.resume()
            waitForExpectations(timeout: 1, handler: nil)
        }
    }
    
    func testMetricsQueue() {
        if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *) {
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .ok, text: "Hello world"))
            }
            let task = expectationForRequestSuccess(HTTP.request(GET: "foo"), startAutomatically: false)
            let operationQueue = OperationQueue()
            let expectation = self.expectation(description: "task metrics")
            HTTP.metricsCallback = .init(queue: operationQueue, callback: { (task_, metrics) in
                XCTAssertEqual(OperationQueue.current, operationQueue)
                XCTAssert(task === task_, "unexpected task")
                expectation.fulfill()
            })
            task.resume()
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
            let task = expectationForRequestSuccess(HTTP.request(GET: "foo"), queue: operationQueue, startAutomatically: false) { (task, response, value) in
                XCTAssertTrue(gotMetrics, "expected to have received metrics already")
                requestFinished = true
            }
            let expectation = self.expectation(description: "task metrics")
            HTTP.metricsCallback = .init(queue: operationQueue, callback: { (task_, metrics) in
                XCTAssertEqual(OperationQueue.current, operationQueue)
                XCTAssert(task === task_, "unexpected task")
                XCTAssertFalse(requestFinished, "recieved metrics after task finished")
                gotMetrics = true
                expectation.fulfill()
            })
            task.resume()
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
            let task = expectationForRequestSuccess(req, startAutomatically: false)
            let operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = 1
            let expectation = self.expectation(description: "task metrics")
            expectation.expectedFulfillmentCount = 3
            expectation.assertForOverFulfill = true
            HTTP.metricsCallback = .init(queue: operationQueue, callback: { (task_, metrics) in
                XCTAssert(task === task_, "unexpected task")
                expectation.fulfill()
            })
            task.resume()
            waitForExpectations(timeout: 1, handler: nil)
        }
    }
}
