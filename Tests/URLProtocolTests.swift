//
//  URLProtocolTests.swift
//  PMHTTPTests
//
//  Created by Kevin Ballard on 7/29/18.
//  Copyright © 2018 Kevin Ballard.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import XCTest
import PMHTTP

final class URLProtocolTests: PMHTTPTestCase {
    func testProperties() {
        let req = HTTP.request(GET: "http://example.com")!
        XCTAssertNil(URLProtocol.property(forKey: "foo", in: req))
        URLProtocol.setProperty("bar", forKey: "foo", in: req)
        XCTAssertEqual(URLProtocol.property(forKey: "foo", in: req) as? String, "bar")
        XCTAssertNil(URLProtocol.property(forKey: "foo2", in: req))
        URLProtocol.setProperty("baz", forKey: "qux", in: req)
        XCTAssertEqual(URLProtocol.property(forKey: "foo", in: req) as? String, "bar")
        XCTAssertEqual(URLProtocol.property(forKey: "qux", in: req) as? String, "baz")
        URLProtocol.removeProperty(forKey: "foo", in: req)
        XCTAssertNil(URLProtocol.property(forKey: "foo", in: req))
        XCTAssertEqual(URLProtocol.property(forKey: "qux", in: req) as? String, "baz")
    }
    
    func testPreparedURLRequest() {
        let req = HTTP.request(GET: "http://example.com")!
        XCTAssertNil(URLProtocol.property(forKey: "foo", in: req.preparedURLRequest))
        URLProtocol.setProperty("bar", forKey: "foo", in: req)
        XCTAssertEqual(URLProtocol.property(forKey: "foo", in: req.preparedURLRequest) as? String, "bar")
        URLProtocol.setProperty(42, forKey: "qux", in: req)
        XCTAssertEqual(URLProtocol.property(forKey: "foo", in: req) as? String, "bar")
        XCTAssertEqual(URLProtocol.property(forKey: "qux", in: req) as? Int, 42)
    }
    
    func testPreparedURLRequestWithCopy() {
        let req = HTTP.request(GET: "http://example.com")!
        URLProtocol.setProperty("bar", forKey: "foo", in: req)
        let req2 = req.copy() as! HTTPManagerRequest
        XCTAssertEqual(URLProtocol.property(forKey: "foo", in: req2) as? String, "bar")
    }
    
    func testPreparedURLRequestAfterParseBlockAdded() {
        let req = HTTP.request(GET: "http://example.com")!
        URLProtocol.setProperty("bar", forKey: "foo", in: req)
        let req2 = req.parseAsJSON()
        XCTAssertEqual(URLProtocol.property(forKey: "foo", in: req2) as? String, "bar")
    }
    
    func testNetworkRequest() {
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .ok))
        }
        let req = HTTP.request(GET: "foo")!
        URLProtocol.setProperty("bar", forKey: "foo", in: req)
        req.retryBehavior = nil
        expectationForRequestSuccess(req) { (task, response, value) in
            let networkTask = task.networkTask
            XCTAssertEqual(URLProtocol.property(forKey: "foo", in: networkTask.originalRequest!) as? String, "bar")
        }
        waitForExpectations(timeout: 1, handler: nil)
    }
    
    func testNetworkRequestAfterRetry() {
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .internalServerError))
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .ok))
        }
        let req = HTTP.request(GET: "foo")!
        URLProtocol.setProperty("bar", forKey: "foo", in: req)
        req.retryBehavior = HTTPManagerRetryBehavior(ignoringIdempotence: { (task, error, attempt, completion) in
            completion(attempt == 0)
        })
        expectationForRequestSuccess(req) { (task, response, value) in
            let networkTask = task.networkTask
            XCTAssertEqual(URLProtocol.property(forKey: "foo", in: networkTask.originalRequest!) as? String, "bar")
        }
        waitForExpectations(timeout: 1, handler: nil)
    }
}
