//
//  MockingTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 4/11/16.
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

class MockingTests: PMHTTPTestCase {
    func testBasicMock() {
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("bar", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(response.MIMEType, "text/plain", "server response MIME type")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "bar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(response.MIMEType, "text/plain", "mock response MIME type")
            XCTAssertEqual(response.textEncodingName, "utf-8", "mock response text encoding")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockStatusCode() {
        HTTP.mockManager.addMock("foo", statusCode: 404, text: "Mock response")
        expectationForRequestFailure(HTTP.request(GET: "foo")) { (task, response, error) in
            if case let HTTPManagerError.FailedResponse(statusCode: statusCode, response: _, body: body, bodyJson: _) = error {
                XCTAssertEqual(statusCode, 404, "status code")
                XCTAssertEqual(String(data: body, encoding: NSUTF8StringEncoding), "Mock response", "body text")
            } else {
                XCTFail("Expected HTTPManagerErrror.FailedResponse, found \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testBasicMockWithURL() {
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("http://\(httpServer.address)/bar", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "bar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockWithEnvironmentPath() {
        HTTP.environment = HTTPManager.Environment(string: "http://\(httpServer.address)/api/v1")!
        expectationForHTTPRequest(httpServer, path: "/api/v1/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("bar", statusCode: 200, text: "Mock response")
        expectationForHTTPRequest(httpServer, path: "/bar") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "bar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "/bar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        expectationForHTTPRequest(httpServer, path: "/api/v1/bar") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("/bar", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "bar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "/bar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockParametersWithEnvironmentPath() {
        HTTP.environment = HTTPManager.Environment(string: "http://\(httpServer.address)/api/v1")!
        expectationForHTTPRequest(httpServer, path: "/api/v1/foo/123") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("bar/:id", statusCode: 200, text: "Mock response")
        expectationForHTTPRequest(httpServer, path: "/bar/123") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo/123")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "bar/123")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "/bar/123")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        expectationForHTTPRequest(httpServer, path: "/api/v1/bar/123") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("/bar/:id", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "bar/123")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "/bar/123")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockParametersWithEnvironmentPathWithToken() {
        HTTP.environment = HTTPManager.Environment(string: "http://\(httpServer.address)/api/:foo")!
        expectationForHTTPRequest(httpServer, path: "/api/bar/baz") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("baz", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "/api/bar/baz")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        HTTP.mockManager.addMock("baz/:id") { (request, parameters, completion) in
            // assert that parameters only has the key "id" and doesn't have "foo"
            XCTAssertEqual(parameters, ["id": "123"], "mock request parameters")
            let body = "Mock response".dataUsingEncoding(NSUTF8StringEncoding)!
            completion(response: NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: "HTTP/1.1", headerFields: nil)!, body: body)
        }
        expectationForRequestSuccess(HTTP.request(GET: "baz/123")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockColonComponent() {
        // Path components consisting of just a colon aren't counted as :components, but may trip up relative URL handling.
        // NB: We use NSURL instead of NSURLComponents for parsing request paths, so we can't just use a relative path ":/foo"
        // as NSURL parses that as something other than a path beginning with ":". But we can use an absolute URL instead.
        HTTP.mockManager.addMock(":/foo", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "http://\(httpServer.address)/:/foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(1, handler: nil)
    }
    
    func testMockScheme() {
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("https://\(httpServer.address)/foo", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "http://\(httpServer.address)/foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "https://\(httpServer.address)/foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockPercentEncoding() {
        // Normal paths
        expectationForHTTPRequest(httpServer, path: "/foo%2fbar") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("foo/bar", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "foo%2fbar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo/bar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(1, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        expectationForHTTPRequest(httpServer, path: "/foo/bar") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("foo%2fbar", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "foo/bar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo%2fbar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(1, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        // Paths with :parameters
        expectationForHTTPRequest(httpServer, path: "/foo%2fbar/123") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("foo/bar/:id", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "foo%2fbar/123")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo/bar/123")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(1, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        expectationForHTTPRequest(httpServer, path: "/foo%2fbar/123") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        HTTP.mockManager.addMock("foo/bar/:id", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "foo%2fbar/123")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo/bar/123")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(1, handler: nil)
    }
    
    func testMockRequest() {
        let req = HTTP.request(GET: "foo")
        req.mock(statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "mock response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        req.clearMock()
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockJSON() {
        HTTP.mockManager.addMock("foo", statusCode: 200, json: ["ok": true, "elts": [1,2,3,4,5]])
        expectationForRequestSuccess(HTTP.request(GET: "foo").parseAsJSON()) { (task, response, json) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(response.MIMEType, "application/json", "MIME type")
            XCTAssertEqual(json, ["ok": true, "elts": [1,2,3,4,5]], "body JSON")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockRequestJSON() {
        let req = HTTP.request(GET: "foo")
        req.mock(statusCode: 200, headers: ["Content-Type": "application/json"], text: "{ \"ok\": true, \"elts\": [1,2,3,4,5] }")
        expectationForRequestSuccess(req.parseAsJSON()) { (task, response, json) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(response.MIMEType, "application/json", "MIME type")
            XCTAssertEqual(json, ["ok": true, "elts": [1,2,3,4,5]], "body JSON")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockResponseHeaders() {
        HTTP.mockManager.addMock("foo", statusCode: 200, headers: ["X-Foo": "Bar"], text: "Mock 404")
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["X-Foo"] as? String, "Bar", "X-Foo header")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock 404", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockDelay() {
        // Ensure the response is always delayed by at least the given delay.
        // Give it up to 100ms longer than the delay for the actual response since we cannot rely on the precise timing
        // of asynchronous operations.
        HTTP.mockManager.addMock("foo", statusCode: 200, delay: 0.05)
        var start = CACurrentMediaTime()
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            let delay = CACurrentMediaTime() - start
            XCTAssert((0.05...0.15).contains(delay), "response delay: expected 50ms...150ms, found \(delay*1000)ms")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        HTTP.mockManager.addMock("foo", statusCode: 200, delay: 0)
        start = CACurrentMediaTime()
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            let delay = CACurrentMediaTime() - start
            XCTAssert((0...0.1).contains(delay), "response delay: expected 0ms...100ms, found \(delay*1000)ms")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        HTTP.mockManager.addMock("foo", statusCode: 200, delay: 0.15)
        start = CACurrentMediaTime()
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            let delay = CACurrentMediaTime() - start
            XCTAssert((0.15...0.25).contains(delay), "response delay: expected 150ms...250ms, found \(delay*1000)ms")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockRequestDelay() {
        // Ensure the response is always delayed by at least the given delay.
        // Give it up to 100ms longer than the delay for the actual response since we cannot rely on the precise timing
        // of asynchronous operations.
        let req = HTTP.request(GET: "foo")
        req.mock(statusCode: 200, delay: 0.05)
        var start = CACurrentMediaTime()
        expectationForRequestSuccess(req) { (task, response, value) in
            let delay = CACurrentMediaTime() - start
            XCTAssert((0.05...0.15).contains(delay), "response delay: expected 50ms...150ms, found \(delay*1000)ms")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        req.mock(statusCode: 200, delay: 0)
        start = CACurrentMediaTime()
        expectationForRequestSuccess(req) { (task, response, value) in
            let delay = CACurrentMediaTime() - start
            XCTAssert((0...0.1).contains(delay), "response delay: expected 0ms...100ms, found \(delay*1000)ms")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        req.mock(statusCode: 200, delay: 0.15)
        start = CACurrentMediaTime()
        expectationForRequestSuccess(req) { (task, response, value) in
            let delay = CACurrentMediaTime() - start
            XCTAssert((0.15...0.25).contains(delay), "response delay: expected 150ms...250ms, found \(delay*1000)ms")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMultipleMocks() {
        HTTP.mockManager.addMock("foo", statusCode: 200, text: "first mock")
        HTTP.mockManager.addMock("bar", statusCode: 200, text: "second mock")
        expectationForRequestSuccess(HTTP.request(GET: "bar")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "second mock", "body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "first mock", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testDuplicateMocks() {
        HTTP.mockManager.addMock("foo", statusCode: 200, text: "first mock")
        HTTP.mockManager.addMock("foo", statusCode: 200, text: "second mock")
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "second mock", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockRemoval() {
        let token = HTTP.mockManager.addMock("foo", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.removeMock(token)
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // Removing the token a second time affects nothing
        HTTP.mockManager.addMock("foo", statusCode: 200, text: "Mock response")
        HTTP.mockManager.removeMock(token)
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockSequence() {
        let seq = HTTPMockSequence()
        seq.addMock(200, text: "Mock response")
        seq.addMock(204)
        seq.addMock(200, json: ["foo": "bar"])
        HTTP.mockManager.addMock("foo", sequence: seq)
        
        let req = HTTP.request(GET: "foo")
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "status code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        expectationForRequestSuccess(req.parseAsJSON()) { (task, response, json) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(json, ["foo": "bar"], "body JSON")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        expectationForRequestFailure(req) { (task, response, error) in
            if case HTTPManagerError.FailedResponse(statusCode: let statusCode, response: _, body: _, bodyJson: _) = error {
                XCTAssertEqual(statusCode, 500, "status code")
            } else {
                XCTFail("Expected HTTPManagerError.FailedResponse, found \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockSequenceRepeatsLast() {
        let seq = HTTPMockSequence()
        seq.addMock(200, text: "Mock response")
        seq.addMock(204)
        seq.repeatsLastResponse = true
        HTTP.mockManager.addMock("foo", sequence: seq)
        
        let req = HTTP.request(GET: "foo")
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        for _ in 0..<4 {
            expectationForRequestSuccess(req) { (task, response, value) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "status code")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testMockHandler() {
        HTTP.mockManager.addMock("foo", state: 0) { (state, request, parameters, completion) in
            state += 1
            let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: "HTTP/1.1", headerFields: nil)!
            let body = "request \(state)".dataUsingEncoding(NSUTF8StringEncoding)!
            completion(response: response, body: body)
        }
        
        let req = HTTP.request(GET: "foo")
        for i in 1..<4 {
            expectationForRequestSuccess(req) { (task, response, value) in
                XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "request \(i)", "body text")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testMockParameters() {
        HTTP.mockManager.addMock("users/:uid") { (request, parameters, completion) in
            if let uid = parameters["uid"] {
                let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: "HTTP/1.1", headerFields: nil)!
                let body = "user \(uid)".dataUsingEncoding(NSUTF8StringEncoding)!
                completion(response: response, body: body)
            } else {
                let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 500, HTTPVersion: "HTTP/1.1", headerFields: nil)!
                completion(response: response, body: NSData())
            }
        }
        expectationForHTTPRequest(httpServer, path: "/users") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "users")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "server response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "server response body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "users/501")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "mock response status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "user 501", "mock response body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        HTTP.mockManager.addMock("posts/:id/:name") { (request, parameters, completion) in
            let id = parameters["id"].map(String.init(reflecting:)) ?? "nil"
            let name = parameters["name"].map(String.init(reflecting:)) ?? "nil"
            let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: "HTTP/1.1", headerFields: nil)!
            let body = "id \(id), name \(name)".dataUsingEncoding(NSUTF8StringEncoding)!
            completion(response: response, body: body)
        }
        expectationForHTTPRequest(httpServer, path: "/posts/123/foo/bar") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "posts/123/flux-capacitor")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "id \"123\", name \"flux-capacitor\"", "body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "posts/123/foo/bar")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        HTTP.mockManager.addMock(":foo", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "bar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        HTTP.mockManager.addMock("http://\(httpServer.address)/:foo", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "bar")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testInterceptURLs() {
        HTTP.mockManager.interceptUnhandledEnvironmentURLs = true
        HTTP.mockManager.addMock("foo", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        expectationForRequestFailure(HTTP.request(GET: "bar")) { (task, response, error) in
            if case let HTTPManagerError.FailedResponse(statusCode, _, _, _) = error {
                XCTAssertEqual(statusCode, 500, "status code")
            } else {
                XCTFail("expected HTTPManagerError.FailedResponse, found \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.reset()
        HTTP.mockManager.interceptUnhandledExternalURLs = true
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "body text")
        }
        expectationForRequestFailure(HTTP.request(GET: "http://www.apple.com")) { (task, response, error) in
            if case let HTTPManagerError.FailedResponse(statusCode, _, _, _) = error {
                XCTAssertEqual(statusCode, 500, "status code")
            } else {
                XCTFail("expected HTTPManagerError.FailedResponse, found \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockPartialURL() {
        HTTP.mockManager.interceptUnhandledExternalURLs = true
        HTTP.mockManager.interceptUnhandledEnvironmentURLs = true
        // httpServer.address includes port
        HTTP.mockManager.addMock("//\(httpServer.address)/foo", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "http://\(httpServer.address)/foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // httpServer.host does not
        HTTP.mockManager.removeAllMocks()
        HTTP.mockManager.addMock("//\(httpServer.host)/foo", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "http://\(httpServer.host)/foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // Check paths with :components
        HTTP.mockManager.removeAllMocks()
        HTTP.mockManager.addMock("//\(httpServer.host)/:foo", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "http://\(httpServer.host)/foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockPortMatching() {
        HTTP.mockManager.addMock("http://\(httpServer.host):9/foo", statusCode: 200, text: "Mock response")
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "body text")
        }
        expectationForRequestSuccess(HTTP.request(GET: "http://\(httpServer.host):9/foo")) { (task, response, value) in
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockParse() {
        do {
            let req = HTTP.request(GET: "foo").parseAsJSON()
            req.mock(value: ["ok": true, "elts": [1,2,3]])
            expectationForRequestSuccess(req) { (task, response, json) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "application/json", "Content-Type header")
                XCTAssertEqual(json, ["ok": true, "elts": [1,2,3]], "body JSON")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
            
            req.clearMock()
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "{\"ok\": true}"))
            }
            expectationForRequestSuccess(req) { (task, response, json) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "application/json", "Content-Type header")
                XCTAssertEqual(json, ["ok": true], "body JSON")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            let req = HTTP.request(GET: "foo").parseAsJSON()
            req.mock(headers: ["Content-Type": "text/plain"], value: ["foo": "bar"])
            expectationForRequestSuccess(req) { (task, response, json) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "text/plain", "Content-Type header")
                XCTAssertEqual(json, ["foo": "bar"], "body JSON")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            let req = HTTP.request(GET: "foo").parseWithHandler({ _ -> Int in
                XCTFail("Parse handler unexpectedly called")
                return 42
            })
            req.mock(value: 123)
            expectationForRequestSuccess(req, completion: { (task, response, value) in
                XCTAssertEqual(value, 123, "parsed body")
            })
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            let req = HTTP.request(GET: "foo")
            req.mock(statusCode: 500)
            let req_ = req.parseAsJSON()
            req_.mock(value: ["ok": true]) // this should override the network mock
            expectationForRequestSuccess(req_, completion: { (task, response, json) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
                XCTAssertEqual(json, ["ok": true], "body JSON")
            })
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testMockParseRequestDelay() {
        // Ensure the response is always delayed by at least the given delay.
        // Give it up to 100ms longer than the delay for the actual response since we cannot rely on the precise timing
        // of asynchronous operations.
        let req = HTTP.request(GET: "foo").parseAsJSON()
        req.mock(value: ["ok": true], delay: 0.05)
        var start = CACurrentMediaTime()
        expectationForRequestSuccess(req) { (task, response, value) in
            let delay = CACurrentMediaTime() - start
            XCTAssert((0.05...0.15).contains(delay), "response delay: expected 50ms...150ms, found \(delay*1000)ms")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        req.mock(value: ["ok": true], delay: 0)
        start = CACurrentMediaTime()
        expectationForRequestSuccess(req) { (task, response, value) in
            let delay = CACurrentMediaTime() - start
            XCTAssert((0...0.1).contains(delay), "response delay: expected 0ms...100ms, found \(delay*1000)ms")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        req.mock(value: ["ok": true], delay: 0.15)
        start = CACurrentMediaTime()
        expectationForRequestSuccess(req) { (task, response, value) in
            let delay = CACurrentMediaTime() - start
            XCTAssert((0.15...0.25).contains(delay), "response delay: expected 150ms...250ms, found \(delay*1000)ms")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMockRequestBody() {
        // NSData upload
        HTTP.mockManager.addMock("foo") { (request, parameters, completion) in
            XCTAssertEqual(String(data: HTTP.mockManager.dataFromRequest(request), encoding: NSUTF8StringEncoding), "Hello world", "request body")
            completion(response: NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: "HTTP/1.1", headerFields: nil)!, body: NSData())
        }
        expectationForRequestSuccess(HTTP.request(POST: "foo", contentType: "text/plain", data: "Hello world".dataUsingEncoding(NSUTF8StringEncoding)!))
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // JSON upload
        HTTP.mockManager.removeAllMocks()
        HTTP.mockManager.addMock("foo") { (request, parameters, completion) in
            do {
                let json = try JSON.decode(HTTP.mockManager.dataFromRequest(request))
                XCTAssertEqual(json, ["ok": true, "foo": "bar"], "request body json")
            } catch {
                XCTFail("error decoding JSON: \(error)")
            }
            completion(response: NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: "HTTP/1.1", headerFields: nil)!, body: NSData())
        }
        expectationForRequestSuccess(HTTP.request(POST: "foo", json: ["ok": true, "foo": "bar"]))
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // Multipart upload
        do {
            HTTP.mockManager.removeAllMocks()
            HTTP.mockManager.addMock("foo") { (request, parameters, completion) in
                let data = HTTP.mockManager.dataFromRequest(request)
                // we can't parse a multipart body right now, and HTTPServer doesn't expose its parser in a way we can use.
                // So we'll just make sure our two texts are in there and all the boundaries are there
                XCTAssertNotNil(data.rangeOfData("Hello world".dataUsingEncoding(NSUTF8StringEncoding)!, options: [], range: NSRange(0..<data.length)).toRange(), "range of first message")
                XCTAssertNotNil(data.rangeOfData("Goodbye world".dataUsingEncoding(NSUTF8StringEncoding)!, options: [], range: NSRange(0..<data.length)).toRange(), "range of second message")
                outer: if let boundary = request.valueForHTTPHeaderField("Content-Type").map(MediaType.init)?.params.find({ $0.0 == "boundary" })?.1 {
                    // We should find 2 regular boundaries and one terminator boundary
                    // The spec allows boundaries to be followed by LWS, but we don't do that so just search for --boundary\r\n
                    let boundaryData = "--\(boundary)\r\n".dataUsingEncoding(NSUTF8StringEncoding)!
                    let terminatorData = "--\(boundary)--".dataUsingEncoding(NSUTF8StringEncoding)!
                    var range = 0..<data.length
                    for i in 1...2 {
                        let found = data.rangeOfData(boundaryData, options: [], range: NSRange(range)).toRange()
                        XCTAssertNotNil(found, "range of boundary \(i)")
                        guard let found_ = found else { break outer }
                        range.startIndex = found_.endIndex
                    }
                    XCTAssertNotNil(data.rangeOfData(terminatorData, options: [], range: NSRange(range)).toRange(), "range of terminator boundary")
                }
                completion(response: NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: "HTTP/1.1", headerFields: nil)!, body: NSData())
            }
            let req = HTTP.request(POST: "foo")
            req.addMultipartText("Hello world", withName: "message")
            req.addMultipartData("Goodbye world".dataUsingEncoding(NSUTF8StringEncoding)!, withName: "data")
            expectationForRequestSuccess(req)
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testMockHTTPMethods() {
        // By default mocks match any HTTP method
        HTTP.mockManager.addMock("foo", statusCode: 200, text: "Mock response")
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        expectationForRequestSuccess(HTTP.request(POST: "foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        HTTP.mockManager.removeAllMocks()
        HTTP.mockManager.addMock("foo", httpMethod: "POST", statusCode: 200, text: "Mock response")
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .OK, text: "Server response"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Server response", "body text")
        }
        expectationForRequestSuccess(HTTP.request(POST: "foo")) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Mock response", "body text")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
}
