//
//  NetworkActivityTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 6/22/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

import XCTest
import PMHTTP

class NetworkActivityTests: PMHTTPTestCase {
    var numberOfOutstandingTasks: Int?
    
    override func setUp() {
        super.setUp()
        numberOfOutstandingTasks = nil
        HTTPManager.networkActivityHandler = {
            self.numberOfOutstandingTasks = $0
        }
    }
    
    override func tearDown() {
        HTTPManager.networkActivityHandler = nil
        super.tearDown()
    }
    
    func sanityCheck(_ file: StaticString = #file, line: UInt = #line) -> Bool {
        // Sanity check - we shouldn't have any outstanding tasks when beginning this test.
        // We need to spin the run loop once to ensure the block is invoked if it was enqueued.
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        guard numberOfOutstandingTasks == nil else {
            XCTFail("Test environment has outstanding tasks")
            return false
        }
        return true
    }
    
    func testActivityCount() {
        guard sanityCheck() else { return }
        
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .ok))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo"))
        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertEqual(numberOfOutstandingTasks, 0)
        
        var countDuringRequest: Int?
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            DispatchQueue.main.async {
                countDuringRequest = self.numberOfOutstandingTasks
                completionHandler(HTTPServer.Response(status: .ok))
            }
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo"))
        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertEqual(countDuringRequest, 1)
        
        countDuringRequest = nil
        let group = DispatchGroup()
        group.enter() // our notify block has to run first, but it can't run yet
        group.notify(queue: DispatchQueue.main) {
            countDuringRequest = self.numberOfOutstandingTasks
        }
        for _ in 0..<3 {
            group.enter()
            expectationForHTTPRequest(httpServer, path: "/foo", handler: { (request, completionHandler) in
                group.notify(queue: DispatchQueue.main) {
                    completionHandler(HTTPServer.Response(status: .ok))
                }
                group.leave()
            })
            expectationForRequestSuccess(HTTP.request(GET: "foo"))
        }
        group.leave()
        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertEqual(countDuringRequest, 3)
    }
    
    func testChangingBlock() {
        // Test what happens if we change the block with outstanding tasks
        guard sanityCheck() else { return }
        
        var values: [Int] = []
        let newHandler = { values.append($0) }
        
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            DispatchQueue.main.async {
                // change the block on the main queue to make it easier to reason about ordering of operations
                // the property itself is actually thread-safe
                HTTPManager.networkActivityHandler = newHandler
                // let the main queue drain before we call our completion handler
                DispatchQueue.main.async {
                    completionHandler(HTTPServer.Response(status: .ok))
                }
            }
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo"))
        waitForExpectations(timeout: 2, handler: nil)
        // the old block will have been invoked for the task
        XCTAssertEqual(numberOfOutstandingTasks, 1)
        XCTAssertEqual(values, [1, 0])
    }
    
    func testResumeAfterFinish() {
        guard sanityCheck() else { return }
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .ok))
        }
        let task = expectationForRequestSuccess(HTTP.request(GET: "foo"))
        waitForExpectations(timeout: 2, handler: nil)
        task.resume()
        // spin the runloop just in case
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        XCTAssertEqual(0, numberOfOutstandingTasks)
    }
    
    func testRetry() {
        // Make sure the counter behaves correctly across retries.
        // NB: We're not testing if the counter drops while it retries because we're not guaranteed
        // to see the drop, it depends on whether the main queue services the block before we increment
        // the counter again.
        guard sanityCheck() else { return }
        
        var values: [Int] = []
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            DispatchQueue.main.async {
                values.append(self.numberOfOutstandingTasks ?? -1)
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            DispatchQueue.main.async {
                values.append(self.numberOfOutstandingTasks ?? -1)
                completionHandler(HTTPServer.Response(status: .ok, text: "success"))
            }
        }
        let req = HTTP.request(GET: "foo")!
        req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
        expectationForRequestSuccess(req)
        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertEqual(values, [1, 1])
        XCTAssertEqual(numberOfOutstandingTasks, 0)
    }
}
