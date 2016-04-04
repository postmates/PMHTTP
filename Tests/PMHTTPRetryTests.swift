//
//  PMHTTPRetryTests.swift
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 4/1/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

import XCTest
import PMJSON
@testable import PMHTTP

final class PMHTTPRetryTests: PMHTTPTestCase {
    func testTruncatedResponseNoRetry() {
        // Test the baseline behvaior of a truncated response with no retry.
        // A truncated response in this case is a response that declares a Content-Length
        // but does not actually provide a body.
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo")) { task, response, error in
            // FIXME(Swift 3): Swift 3 will likely turn NSURL errors into a proper enum
            let error = error as NSError
            XCTAssertEqual(error.domain, NSURLErrorDomain, "error domain")
            XCTAssertEqual(error.code, NSURLErrorNetworkConnectionLost, "error code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testRetryOnceGET() {
        // Test the success case
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, text: "success"))
            }
            let req = HTTP.request(GET: "foo")
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            expectationForRequestSuccess(req) { task, response, value in
                XCTAssert(response === task.networkTask.response)
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "success")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // Test the failure case
        do {
            for _ in 0..<2 {
                expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                    completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
                }
            }
            let req = HTTP.request(GET: "foo")
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            expectationForRequestFailure(req) { task, response, error in
                // FIXME(Swift 3): Swift 3 will likely turn NSURL errors into a proper enum
                let error = error as NSError
                XCTAssertEqual(error.domain, NSURLErrorDomain, "error domain")
                XCTAssertEqual(error.code, NSURLErrorNetworkConnectionLost, "error code")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testRetryOncePOST() {
        // This won't retry because POST is not idempotent
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
        }
        let req = HTTP.request(POST: "foo")
        req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
        expectationForRequestFailure(req) { task, response, error in
            // FIXME(Swift 3): Swift 3 will likely turn NSURL errors into a proper enum
            let error = error as NSError
            XCTAssertEqual(error.domain, NSURLErrorDomain, "error domain")
            XCTAssertEqual(error.code, NSURLErrorNetworkConnectionLost, "error code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testRetryOnceGET500Error() {
        // This won't retry because a 500 Server Error is not something we consider to be transient.
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .InternalServerError))
        }
        let req = HTTP.request(GET: "foo")
        req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
        expectationForRequestFailure(req) { task, response, error in
            if case HTTPManagerError.FailedResponse(500, _, _, _) = error {
                // expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testRetryOnceGET503Error() {
        // Check that we don't retry with retryNetworkFailure
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ServiceUnavailable))
            }
            let req = HTTP.request(GET: "foo")
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            expectationForRequestFailure(req) { task, response, error in
                if case HTTPManagerError.FailedResponse(503, _, _, _) = error {
                    // expected
                } else {
                    XCTFail("Unexpected error: \(error)")
                }
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // And check the case where we do retry
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ServiceUnavailable))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, text: "success"))
            }
            let req = HTTP.request(GET: "foo")
            req.retryBehavior = .retryNetworkFailureOrServiceUnavailable(withStrategy: .retryOnce)
            expectationForRequestSuccess(req) { task, response, value in
                XCTAssert(response === task.networkTask.response)
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "success")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testRetryOncePOST503ServiceUnavailable() {
        // We will retry a POST for a 503 because we know the request wasn't handled.
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .ServiceUnavailable))
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .OK, text: "success"))
        }
        let req = HTTP.request(POST: "foo")
        req.retryBehavior = .retryNetworkFailureOrServiceUnavailable(withStrategy: .retryOnce)
        expectationForRequestSuccess(req) { task, response, value in
            XCTAssert(response === task.networkTask.response)
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "success")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testRetryTwiceGET() {
        // We'll use a very low delay so the test runs quickly. Let's say 100ms
        
        // Test the success case.
        do {
            var firstRetryTime: NSTimeInterval = 0
            var secondRetryTime: NSTimeInterval = 0
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                firstRetryTime = CACurrentMediaTime()
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                secondRetryTime = CACurrentMediaTime()
                completionHandler(HTTPServer.Response(status: .OK, text: "success"))
            }
            let req = HTTP.request(GET: "foo")
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryTwiceWithDelay(0.1))
            expectationForRequestSuccess(req) { task, response, value in
                XCTAssert(response === task.networkTask.response)
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "success")
                let retryDelay_ms = Int((secondRetryTime - firstRetryTime) * 1000)
                // the delay should be >= 100ms but not too much larger. Let's pick 150ms as the upper bound.
                XCTAssert((100...150).contains(retryDelay_ms), "retry delay was \(retryDelay_ms), expected 100...150ms")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // And test the failure case too.
        do {
            var firstRetryTime: NSTimeInterval = 0
            var secondRetryTime: NSTimeInterval = 0
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                firstRetryTime = CACurrentMediaTime()
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                secondRetryTime = CACurrentMediaTime()
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            let req = HTTP.request(GET: "foo")
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryTwiceWithDelay(0.1))
            expectationForRequestFailure(req) { task, response, error in
                // FIXME(Swift 3): Swift 3 will likely turn NSURL errors into a proper enum
                let error = error as NSError
                XCTAssertEqual(error.domain, NSURLErrorDomain, "error domain")
                XCTAssertEqual(error.code, NSURLErrorNetworkConnectionLost, "error code")
                let retryDelay_ms = Int((secondRetryTime - firstRetryTime) * 1000)
                // the delay should be >= 100ms but not too much larger. Let's pick 150ms as the upper bound.
                XCTAssert((100...150).contains(retryDelay_ms), "retry delay was \(retryDelay_ms), expected 100...150ms")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testDefaultRetryBehavior() {
        HTTP.defaultRetryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
        
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .OK, text: "success"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { task, response, value in
            XCTAssert(response === task.networkTask.response)
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "success")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testRetryJSONParseError() {
        // JSON .UnexpectedEOF errors are treated the same as networking errors.
        // GET requests will retry them.
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "{ \"ok\": true"))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "{ \"ok\": true }"))
            }
            let req = HTTP.request(GET: "foo").parseAsJSON()
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            expectationForRequestSuccess(req) { task, response, json in
                XCTAssert(response === task.networkTask.response)
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(json, ["ok": true], "JSON body")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // POST requests won't.
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "{ \"ok\": true"))
            }
            let req = HTTP.request(POST: "foo").parseAsJSON()
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            expectationForRequestFailure(req) { task, response, error in
                if let error = error as? JSONParserError {
                    XCTAssert(error.code == .UnexpectedEOF, "JSON parser error; expected .UnexpectedEOF, found \(error.code)")
                } else {
                    XCTFail("unexpected error \(error)")
                }
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testRetryKVO() {
        // On each retry attempt the state property will go from Processing back to Running
        // and the networkTask property will change.
        
        // Test the baseline first for success with no retry.
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK))
            }
            let task = expectationForRequestSuccess(HTTP.request(GET: "foo"), startAutomatically: false, completion: { _ in })
            let stateLog = KVOLog<NSNumber>(object: task, keyPath: "state")
            let taskLog = KVOLog<NSURLSessionTask>(object: task, keyPath: "networkTask")
            task.resume()
            waitForExpectationsWithTimeout(5) { error in
                guard error == nil else { return }
                let states = stateLog.log.map({ HTTPManagerTaskState(rawValue: $0!.unsignedCharValue)! })
                XCTAssertEqual(states, [HTTPManagerTaskState.Running, .Processing, .Completed], "task states")
                XCTAssertEqual(taskLog.log.map({ $0! }), [task.networkTask], "network task")
            }
        }
        
        // And the baseline for failure with no retry.
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            let task = expectationForRequestFailure(HTTP.request(GET: "foo"), startAutomatically: false, completion: { _ in })
            let stateLog = KVOLog<NSNumber>(object: task, keyPath: "state")
            let taskLog = KVOLog<NSURLSessionTask>(object: task, keyPath: "networkTask")
            task.resume()
            waitForExpectationsWithTimeout(5) { error in
                guard error == nil else { return }
                let states = stateLog.log.map({ HTTPManagerTaskState(rawValue: $0!.unsignedCharValue)! })
                XCTAssertEqual(states, [HTTPManagerTaskState.Running, .Processing, .Completed], "task states")
                XCTAssertEqual(taskLog.log.map({ $0! }), [task.networkTask], "network task")
            }
        }
        
        // Test one retry.
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK))
            }
            let req = HTTP.request(GET: "foo")
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            let task = expectationForRequestSuccess(req, startAutomatically: false, completion: { _ in })
            let stateLog = KVOLog<NSNumber>(object: task, keyPath: "state")
            let taskLog = KVOLog<NSURLSessionTask>(object: task, keyPath: "networkTask")
            let initialNetworkTask = task.networkTask
            task.resume()
            waitForExpectationsWithTimeout(5) { error in
                guard error == nil else { return }
                let states = stateLog.log.map({ HTTPManagerTaskState(rawValue: $0!.unsignedCharValue)! })
                XCTAssertEqual(states, [HTTPManagerTaskState.Running, .Processing, .Running, .Processing, .Completed], "task states")
                XCTAssertEqual(taskLog.log.map({ $0! }), [initialNetworkTask, task.networkTask], "network task")
            }
        }
        
        // Test two retries.
        do {
            for _ in 0..<2 {
                expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                    completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
                }
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK))
            }
            let req = HTTP.request(GET: "foo")
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryTwiceWithDelay(0.05))
            let task = expectationForRequestSuccess(req, startAutomatically: false, completion: { _ in })
            let stateLog = KVOLog<NSNumber>(object: task, keyPath: "state")
            let taskLog = KVOLog<NSURLSessionTask>(object: task, keyPath: "networkTask")
            let initialNetworkTask = task.networkTask
            task.resume()
            waitForExpectationsWithTimeout(5) { error in
                guard error == nil else { return }
                let states = stateLog.log.map({ HTTPManagerTaskState(rawValue: $0!.unsignedCharValue)! })
                XCTAssertEqual(states, [HTTPManagerTaskState.Running, .Processing, .Running, .Processing, .Running, .Processing, .Completed], "task states")
                let tasks = taskLog.log.map({ $0! })
                XCTAssertEqual(tasks.count, 3, "network task count")
                XCTAssertEqual(tasks.first, initialNetworkTask, "first network task")
                XCTAssertEqual(tasks.last, task.networkTask, "last network task")
            }
        }
    }
}

private class KVOLog<T: AnyObject>: NSObject {
    var _observing: Bool = true
    let _object: NSObject
    let _keyPath: String
    let _context = NSObject()
    var _log: [T?] = []
    var _queue: dispatch_queue_t = dispatch_queue_create("KVOLog", DISPATCH_QUEUE_SERIAL)
    
    var log: [T?] {
        var log: [T?] = []
        dispatch_sync(_queue) {
            log = self._log
        }
        return log
    }
    
    init(object: NSObject, keyPath: String) {
        _object = object
        _keyPath = keyPath
        super.init()
        object.addObserver(self, forKeyPath: keyPath, options: [.Initial, .New], context: UnsafeMutablePointer(unsafeAddressOf(_context)))
    }
    
    deinit {
        unregister()
    }
    
    func unregister() {
        guard _observing else { return }
        _object.removeObserver(self, forKeyPath: _keyPath, context: UnsafeMutablePointer(unsafeAddressOf(_context)))
        _observing = false
    }
    
    private override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        guard context == UnsafeMutablePointer(unsafeAddressOf(_context)) else {
            return super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
        let newValue: T?
        switch change?[NSKeyValueChangeNewKey] {
        case is NSNull, nil: newValue = nil
        case let value?: newValue = (value as! T)
        }
        dispatch_async(_queue) { [weak self] in
            self?._log.append(newValue)
        }
    }
}
