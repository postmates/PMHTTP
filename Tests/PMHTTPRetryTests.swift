//
//  PMHTTPRetryTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 4/1/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
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
            completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo")) { task, response, error in
            if let error = error as? URLError {
                XCTAssertEqual(error.code, URLError.networkConnectionLost, "error code")
            } else {
                XCTFail("expected URLError, got \(error)")
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testRetryOnceGET() {
        // Test the success case
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, text: "success"))
            }
            let req = HTTP.request(GET: "foo")!
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            expectationForRequestSuccess(req) { task, response, value in
                XCTAssert(response === task.networkTask.response)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(String(data: value, encoding: String.Encoding.utf8), "success")
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        // Test the failure case
        do {
            for _ in 0..<2 {
                expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                    completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
                }
            }
            let req = HTTP.request(GET: "foo")!
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            expectationForRequestFailure(req) { task, response, error in
                if let error = error as? URLError {
                    XCTAssertEqual(error.code, URLError.networkConnectionLost, "error code")
                } else {
                    XCTFail("expected URLError, got \(error)")
                }
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
    }
    
    func testRetryOncePOST() {
        // This won't retry because POST is not idempotent
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
        }
        let req = HTTP.request(POST: "foo")!
        req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
        expectationForRequestFailure(req) { task, response, error in
            if let error = error as? URLError {
                XCTAssertEqual(error.code, URLError.networkConnectionLost, "error code")
            } else {
                XCTFail("expected URLError, got \(error)")
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testRetryOnceGET500Error() {
        // This won't retry because a 500 Server Error is not something we consider to be transient.
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .internalServerError))
        }
        let req = HTTP.request(GET: "foo")!
        req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
        expectationForRequestFailure(req) { task, response, error in
            if case HTTPManagerError.failedResponse(500, _, _, _) = error {
                // expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testRetryOnceGET503Error() {
        // Check that we don't retry with retryNetworkFailure
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .serviceUnavailable))
            }
            let req = HTTP.request(GET: "foo")!
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            expectationForRequestFailure(req) { task, response, error in
                if case HTTPManagerError.failedResponse(503, _, _, _) = error {
                    // expected
                } else {
                    XCTFail("Unexpected error: \(error)")
                }
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        // And check the case where we do retry
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .serviceUnavailable))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, text: "success"))
            }
            let req = HTTP.request(GET: "foo")!
            req.retryBehavior = .retryNetworkFailureOrServiceUnavailable(withStrategy: .retryOnce)
            expectationForRequestSuccess(req) { task, response, value in
                XCTAssert(response === task.networkTask.response)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(String(data: value, encoding: String.Encoding.utf8), "success")
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
    }
    
    func testRetryOncePOST503ServiceUnavailable() {
        // We will retry a POST for a 503 because we know the request wasn't handled.
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .serviceUnavailable))
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .ok, text: "success"))
        }
        let req = HTTP.request(POST: "foo")!
        req.retryBehavior = .retryNetworkFailureOrServiceUnavailable(withStrategy: .retryOnce)
        expectationForRequestSuccess(req) { task, response, value in
            XCTAssert(response === task.networkTask.response)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(String(data: value, encoding: String.Encoding.utf8), "success")
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testRetryTwiceGET() {
        // We'll use a very low delay so the test runs quickly. Let's say 100ms
        
        // Test the success case.
        do {
            var firstRetryTime: TimeInterval = 0
            var secondRetryTime: TimeInterval = 0
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                firstRetryTime = CACurrentMediaTime()
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                secondRetryTime = CACurrentMediaTime()
                completionHandler(HTTPServer.Response(status: .ok, text: "success"))
            }
            let req = HTTP.request(GET: "foo")!
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryTwiceWithDelay(0.1))
            expectationForRequestSuccess(req) { task, response, value in
                XCTAssert(response === task.networkTask.response)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(String(data: value, encoding: String.Encoding.utf8), "success")
                let retryDelay_ms = Int((secondRetryTime - firstRetryTime) * 1000)
                // the delay should be >= 100ms but not too much larger. Let's pick 200ms as the upper bound.
                XCTAssert((100...200).contains(retryDelay_ms), "retry delay was \(retryDelay_ms), expected 100...200ms")
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        // And test the failure case too.
        do {
            var firstRetryTime: TimeInterval = 0
            var secondRetryTime: TimeInterval = 0
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                firstRetryTime = CACurrentMediaTime()
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                secondRetryTime = CACurrentMediaTime()
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            let req = HTTP.request(GET: "foo")!
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryTwiceWithDelay(0.1))
            expectationForRequestFailure(req) { task, response, error in
                if let error = error as? URLError {
                    XCTAssertEqual(error.code, URLError.networkConnectionLost, "error code")
                } else {
                    XCTFail("expected URLError, got \(error)")
                }
                let retryDelay_ms = Int((secondRetryTime - firstRetryTime) * 1000)
                // the delay should be >= 100ms but not too much larger. Let's pick 200ms as the upper bound.
                XCTAssert((100...200).contains(retryDelay_ms), "retry delay was \(retryDelay_ms), expected 100...200ms")
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
    }
    
    func testDefaultRetryBehavior() {
        HTTP.defaultRetryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
        
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .ok, text: "success"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { task, response, value in
            XCTAssert(response === task.networkTask.response)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(String(data: value, encoding: String.Encoding.utf8), "success")
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testRetryJSONParseError() {
        // JSON .unexpectedEOF errors are treated the same as networking errors.
        // GET requests will retry them.
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Type": "application/json"], body: "{ \"ok\": true"))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Type": "application/json"], body: "{ \"ok\": true }"))
            }
            let req = HTTP.request(GET: "foo").parseAsJSON()
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            expectationForRequestSuccess(req) { task, response, json in
                XCTAssert(response === task.networkTask.response)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(json, ["ok": true], "JSON body")
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        // POST requests won't.
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Type": "application/json"], body: "{ \"ok\": true"))
            }
            let req = HTTP.request(POST: "foo").parseAsJSON()
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            expectationForRequestFailure(req) { task, response, error in
                if let error = error as? JSONParserError {
                    XCTAssert(error.code == .unexpectedEOF, "JSON parser error; expected .unexpectedEOF, found \(error.code)")
                } else {
                    XCTFail("unexpected error \(error)")
                }
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
    }
    
    func testRetryKVO() {
        // On each retry attempt the state property will go from Processing back to Running
        // and the networkTask property will change.
        
        // Test the baseline first for success with no retry.
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok))
            }
            let task = expectationForRequestSuccess(HTTP.request(GET: "foo"), startAutomatically: false, completion: { _ in })
            let stateLog = KVOLog<NSNumber>(object: task, keyPath: "state")
            let taskLog = KVOLog<URLSessionTask>(object: task, keyPath: "networkTask")
            task.resume()
            waitForExpectations(timeout: 5) { error in
                guard error == nil else { return }
                let states = stateLog.log.map({ HTTPManagerTaskState(rawValue: $0!.uint8Value)! })
                XCTAssertEqual(states, [HTTPManagerTaskState.running, .processing, .completed], "task states")
                XCTAssertEqual(taskLog.log.map({ $0! }), [task.networkTask], "network task")
            }
        }
        
        // And the baseline for failure with no retry.
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            let task = expectationForRequestFailure(HTTP.request(GET: "foo"), startAutomatically: false, completion: { _ in })
            let stateLog = KVOLog<NSNumber>(object: task, keyPath: "state")
            let taskLog = KVOLog<URLSessionTask>(object: task, keyPath: "networkTask")
            task.resume()
            waitForExpectations(timeout: 5) { error in
                guard error == nil else { return }
                let states = stateLog.log.map({ HTTPManagerTaskState(rawValue: $0!.uint8Value)! })
                XCTAssertEqual(states, [HTTPManagerTaskState.running, .processing, .completed], "task states")
                XCTAssertEqual(taskLog.log.map({ $0! }), [task.networkTask], "network task")
            }
        }
        
        // Test one retry.
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok))
            }
            let req = HTTP.request(GET: "foo")!
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            let task = expectationForRequestSuccess(req, startAutomatically: false, completion: { _ in })
            let stateLog = KVOLog<NSNumber>(object: task, keyPath: "state")
            let taskLog = KVOLog<URLSessionTask>(object: task, keyPath: "networkTask")
            let initialNetworkTask = task.networkTask
            task.resume()
            waitForExpectations(timeout: 5) { error in
                guard error == nil else { return }
                let states = stateLog.log.map({ HTTPManagerTaskState(rawValue: $0!.uint8Value)! })
                XCTAssertEqual(states, [HTTPManagerTaskState.running, .processing, .running, .processing, .completed], "task states")
                XCTAssertEqual(taskLog.log.map({ $0! }), [initialNetworkTask, task.networkTask], "network task")
            }
        }
        
        // Test two retries.
        do {
            for _ in 0..<2 {
                expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                    completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
                }
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok))
            }
            let req = HTTP.request(GET: "foo")!
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryTwiceWithDelay(0.05))
            let task = expectationForRequestSuccess(req, startAutomatically: false, completion: { _ in })
            let stateLog = KVOLog<NSNumber>(object: task, keyPath: "state")
            let taskLog = KVOLog<URLSessionTask>(object: task, keyPath: "networkTask")
            let initialNetworkTask = task.networkTask
            task.resume()
            waitForExpectations(timeout: 5) { error in
                guard error == nil else { return }
                let states = stateLog.log.map({ HTTPManagerTaskState(rawValue: $0!.uint8Value)! })
                XCTAssertEqual(states, [HTTPManagerTaskState.running, .processing, .running, .processing, .running, .processing, .completed], "task states")
                let tasks = taskLog.log.map({ $0! })
                XCTAssertEqual(tasks.count, 3, "network task count")
                XCTAssertEqual(tasks.first, initialNetworkTask, "first network task")
                XCTAssertEqual(tasks.last, task.networkTask, "last network task")
            }
        }
    }
    
    func testRetryNetworkPriority() {
        // Retrying tasks should preserve the network task priority that the previous task had.
        
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, text: "success"))
            }
            let req = HTTP.request(GET: "foo")!
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            let task = expectationForRequestSuccess(req, startAutomatically: false) { task, response, value in
                XCTAssert(response === task.networkTask.response)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(String(data: value, encoding: String.Encoding.utf8), "success")
            }
            let networkTask = task.networkTask
            XCTAssertNotEqual(networkTask.priority, 0.3, "original network task priority")
            networkTask.priority = 0.3
            task.resume()
            waitForExpectations(timeout: 5) { error in
                guard error == nil else { return }
                XCTAssert(networkTask !== task.networkTask, "network task didn't change")
                XCTAssertEqual(task.networkTask.priority, 0.3, "network task priority")
            }
        }
        
        // Also test user-initiated tasks to ensure they don't reset their priority
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, headers: ["Content-Length": "64", "Connection": "close"]))
            }
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .ok, text: "success"))
            }
            let req = HTTP.request(GET: "foo")!
            req.userInitiated = true
            req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
            let task = expectationForRequestSuccess(req, startAutomatically: false) { task, response, value in
                XCTAssert(response === task.networkTask.response)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(String(data: value, encoding: String.Encoding.utf8), "success")
            }
            let networkTask = task.networkTask
            XCTAssertNotEqual(networkTask.priority, 0.3, "original network task priority")
            networkTask.priority = 0.3
            task.resume()
            waitForExpectations(timeout: 5) { error in
                guard error == nil else { return }
                XCTAssert(networkTask !== task.networkTask, "network task didn't change")
                XCTAssertEqual(task.networkTask.priority, 0.3, "network task priority")
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
    var _queue: DispatchQueue = DispatchQueue(label: "KVOLog")
    
    var log: [T?] {
        var log: [T?] = []
        _queue.sync {
            log = self._log
        }
        return log
    }
    
    init(object: NSObject, keyPath: String) {
        _object = object
        _keyPath = keyPath
        super.init()
        // FIXME: Use ObjectIdentifier.address or whatever it's called once it's available
        object.addObserver(self, forKeyPath: keyPath, options: [.initial, .new], context: Unmanaged.passUnretained(_context).toOpaque())
    }
    
    deinit {
        unregister()
    }
    
    func unregister() {
        guard _observing else { return }
        // FIXME: Use ObjectIdentifier.address or whatever it's called once it's available
        _object.removeObserver(self, forKeyPath: _keyPath, context: Unmanaged.passUnretained(_context).toOpaque())
        _observing = false
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        // FIXME: Use ObjectIdentifier.address or whatever it's called once it's available
        guard context == Unmanaged.passUnretained(_context).toOpaque() else {
            return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
        let newValue: T?
        switch change?[.newKey] {
        case is NSNull, nil: newValue = nil
        case let value?: newValue = (value as! T)
        }
        _queue.async { [weak self] in
            self?._log.append(newValue)
        }
    }
}
