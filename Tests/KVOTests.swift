//
//  KVOTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 7/5/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

import XCTest
import PMHTTP

class KVOTests: PMHTTPTestCase {
    func testAccessNetworkTaskOnAssocDealloc() {
        // This tests that we can access the networkTask when associated objects are cleared on the
        // HTTPManagerTask. This mimics the trick some KVO libraries use to automatically deregister
        // KVO when an object is deallocated. We're not actually performing KVO here, just ensuring
        // that it's safe to use one of these libraries with a KVO keypath of "networkTask.something".
        autoreleasepool {
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .OK))
            }
            let task = expectationForRequestSuccess(HTTP.request(GET: "foo"))
            let networkTask = task.networkTask
            waitForExpectationsWithTimeout(5, handler: nil)
            let expectation = expectationWithDescription("objc association")
            objc_setAssociatedObject(task, &assocKey, DeinitAction({ [unowned(unsafe) task] in
                XCTAssert(networkTask === task.networkTask)
                expectation.fulfill()
            }), objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testKVOOnAutomaticRetry() {
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Length": "64", "Connection": "close"]))
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK))
        }
        let req = HTTP.request(GET: "foo")
        req.retryBehavior = .retryNetworkFailure(withStrategy: .retryOnce)
        let task = expectationForRequestSuccess(req, startAutomatically: false)
        let networkTask = task.networkTask
        keyValueObservingExpectationForObject(task, keyPath: "networkTask") { (object, change) -> Bool in
            return object !== networkTask
        }
        task.resume()
        waitForExpectationsWithTimeout(5, handler: nil)
    }
}

private var kvoContext: () = ()
private var assocKey: () = ()

private class DeinitAction: NSObject {
    init(_ handler: () -> Void) {
        _handler = handler
    }
    
    private let _handler: () -> Void
    
    deinit {
        _handler()
    }
}
