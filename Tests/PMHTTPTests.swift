//
//  PMHTTPTests.swift
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 12/9/15.
//  Copyright © 2015 Postmates.
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

final class PMHTTPTests: PMHTTPTestCase {
    func testSimpleGET() {
        let address = httpServer.address
        let req = HTTP.request(GET: "foo")
        XCTAssertEqual(req.url.absoluteString, "http://\(address)/foo")
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            XCTAssertEqual(request.method, HTTPServer.Method.GET)
            XCTAssertEqual(request.headers["Host"], address)
            completionHandler(HTTPServer.Response(status: .OK, text: "Hello world"))
        }
        expectationForRequestSuccess(req) { task, response, value in
            XCTAssertEqual(task.networkTask.originalRequest?.URL?.absoluteString, "http://\(address)/foo")
            XCTAssert(response === task.networkTask.response)
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "Hello world")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testSimpleGETFailure() {
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .BadRequest, text: "bar"))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo")) { task, response, error in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 400, "response status code")
            if case let HTTPManagerError.FailedResponse(statusCode, response_, body, json) = error {
                XCTAssert(response === response_, "error response")
                XCTAssertEqual(statusCode, 400, "error status code")
                XCTAssertEqual(String(data: body, encoding: NSUTF8StringEncoding) ?? "(not utf8)", "bar", "error body")
                XCTAssertNil(json, "error json")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testGetWithAbsoluteURL() {
        let newServer = try! HTTPServer()
        defer {
            newServer.invalidate()
        }
        let req = HTTP.request(GET: "http://\(newServer.address)/foo")
        XCTAssertEqual(req.url.absoluteString, "http://\(newServer.address)/foo")
        let serverExpectation = expectationForHTTPRequest(newServer, path: "/foo") { [address=newServer.address] request, completionHandler in
            XCTAssertEqual(request.headers["Host"], address)
            completionHandler(HTTPServer.Response(status: .OK, text: "new server"))
        }
        httpServer.registerRequestCallback { request, completionHandler in
            XCTFail("Unexpected request to registered environment: \(request)")
            completionHandler(HTTPServer.Response(status: .NotFound))
            // fulfill the server expectation since it won't be hit
            serverExpectation.fulfill()
        }
        expectationForRequestSuccess(req) { task, response, value in
            XCTAssertEqual(task.networkTask.originalRequest?.URL?.absoluteString, "http://\(newServer.address)/foo")
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "new server")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testCancel() {
        do {
            // Cancel before we dispatch the request.
            // Server should never see anything
            let task = expectationForRequestCanceled(HTTP.request(GET: "foo"), startAutomatically: false)
            task.cancel()
            task.resume()
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            // Cancel before the server returns
            let requestSema = dispatch_semaphore_create(0)
            let resultSema = dispatch_semaphore_create(0)
            expectationForHTTPRequest(httpServer, path: "/foo", handler: { (request, completionHandler) in
                dispatch_semaphore_signal(requestSema)
                XCTAssert(dispatch_semaphore_wait(resultSema, dispatch_time(DISPATCH_TIME_NOW, 2 * Int64(NSEC_PER_SEC))) == 0, "timeout on dispatch semaphore")
                completionHandler(HTTPServer.Response(status: .OK))
            })
            let task = expectationForRequestCanceled(HTTP.request(GET: "foo"))
            XCTAssert(dispatch_semaphore_wait(requestSema, dispatch_time(DISPATCH_TIME_NOW, 2 * Int64(NSEC_PER_SEC))) == 0, "timeout on dispatch semaphore")
            task.cancel()
            dispatch_semaphore_signal(resultSema)
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            // Cancel during processing
            let requestSema = dispatch_semaphore_create(0)
            let resultSema = dispatch_semaphore_create(0)
            expectationForHTTPRequest(httpServer, path: "/foo", handler: { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .OK))
            })
            let req = HTTP.request(GET: "foo")
                .parseWithHandler({ (response, data) -> Int in
                    dispatch_semaphore_signal(requestSema)
                    XCTAssert(dispatch_semaphore_wait(resultSema, dispatch_time(DISPATCH_TIME_NOW, 2 * Int64(NSEC_PER_SEC))) == 0, "timeout on dispatch semaphore")
                    return 42
                })
            let task = expectationForRequestCanceled(req)
            XCTAssert(dispatch_semaphore_wait(requestSema, dispatch_time(DISPATCH_TIME_NOW, 2 * Int64(NSEC_PER_SEC))) == 0, "timeout on dispatch semaphore")
            task.cancel()
            dispatch_semaphore_signal(resultSema)
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            // Cancel after processing is done, before completion block fires.
            // This one won't cancel as it will already be in the completed state.
            // To avoid timing issues, we'll use a KVO expectation to actually wait until
            // the task is in the Completed state before we cancel it.
            let queue = NSOperationQueue()
            queue.suspended = true
            expectationForHTTPRequest(httpServer, path: "/foo", handler: { (request, completionHandler) in
                completionHandler(HTTPServer.Response(status: .OK))
            })
            let task = expectationForRequestSuccess(HTTP.request(GET: "foo"))
            keyValueObservingExpectationForObject(task, keyPath: "state", handler: { (object, change) -> Bool in
                let task = object as! HTTPManagerTask
                if task.state == .Completed {
                    queue.suspended = false
                    return true
                } else {
                    return false
                }
            })
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testIdempotence() {
        XCTAssertTrue(HTTP.request(GET: "foo").idempotent, "GET request")
        XCTAssertTrue(HTTP.request(PUT: "foo").idempotent, "PUT request")
        XCTAssertTrue(HTTP.request(DELETE: "foo").idempotent, "DELETE request")
        XCTAssertFalse(HTTP.request(POST: "foo").idempotent, "POST request")
        XCTAssertFalse(HTTP.request(PATCH: "foo").idempotent, "PATCH request")
        
        XCTAssertTrue(HTTP.request(GET: "foo").parseAsJSON().idempotent, "GET request")
        XCTAssertTrue(HTTP.request(PUT: "foo").parseAsJSON().idempotent, "PUT request")
        XCTAssertTrue(HTTP.request(DELETE: "foo").parseAsJSON().idempotent, "DELETE request")
        XCTAssertFalse(HTTP.request(POST: "foo").parseAsJSON().idempotent, "POST request")
        XCTAssertFalse(HTTP.request(PATCH: "foo").parseAsJSON().idempotent, "PATCH request")
        
        XCTAssertFalse(HTTP.request(GET: "foo").with({ $0.idempotent = false }).idempotent, "GET request")
        XCTAssertTrue(HTTP.request(POST: "foo").with({ $0.idempotent = true }).idempotent, "POST request")
        
        do {
            let task = expectationForRequestCanceled(HTTP.request(GET: "foo"), startAutomatically: false)
            task.cancel()
            task.resume()
            XCTAssertTrue(task.idempotent, "idempotent GET request")
        }
        do {
            let task = expectationForRequestCanceled(HTTP.request(GET: "foo").with({ $0.idempotent = false }))
            task.cancel()
            task.resume()
            XCTAssertFalse(task.idempotent, "non-idempotent GET request")
        }
        do {
            let task = expectationForRequestCanceled(HTTP.request(POST: "foo"), startAutomatically: false)
            task.cancel()
            task.resume()
            XCTAssertFalse(task.idempotent, "non-idempotent POST request")
        }
        do {
            let task = expectationForRequestCanceled(HTTP.request(POST: "foo").with({ $0.idempotent = true }))
            task.cancel()
            task.resume()
            XCTAssertTrue(task.idempotent, "idempotent POST request")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testParameters() {
        let queryItems = [NSURLQueryItem(name: "foo", value: "bar"), NSURLQueryItem(name: "baz", value: "wat")]
        var parameters: [String: String] = [:]
        for item in queryItems {
            parameters[item.name] = item.value
        }
        func sortedQueryItems(queryItems: [NSURLQueryItem]) -> [NSURLQueryItem] {
            return queryItems.sort({ $0.name < $1.name })
        }
        
        for method in [HTTPManagerRequest.Method.GET, .DELETE] {
            do {
                let request: HTTPManagerNetworkRequest
                switch method {
                case .GET: request = HTTP.request(GET: "foo", parameters: queryItems)
                case .DELETE: request = HTTP.request(DELETE: "foo", parameters: queryItems)
                default: fatalError()
                }
                expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                    XCTAssertEqual(request.method, HTTPServer.Method(method), "request method")
                    XCTAssertEqual(request.urlComponents.queryItems ?? [], queryItems, "url query (\(method))")
                    completionHandler(HTTPServer.Response(status: .OK, text: "ok"))
                }
                expectationForRequestSuccess(request) { (task, response, value) in
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code (\(method))")
                    XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "ok", "response body (\(method))")
                }
                waitForExpectationsWithTimeout(5, handler: nil)
            }
            
            // try again using the dictionary form for the request
            do {
                let request: HTTPManagerNetworkRequest
                switch method {
                case .GET: request = HTTP.request(GET: "foo", parameters: parameters)
                case .DELETE: request = HTTP.request(DELETE: "foo", parameters: parameters)
                default: fatalError()
                }
                expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                    XCTAssertEqual(request.method, HTTPServer.Method(method), "request method")
                    // sort the query items because the dictionary form is not order-preserving
                    XCTAssertEqual(sortedQueryItems(request.urlComponents.queryItems ?? []), sortedQueryItems(queryItems), "url query (\(method))")
                    completionHandler(HTTPServer.Response(status: .OK, text: "ok"))
                }
                expectationForRequestSuccess(request) { (task, response, value) in
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code (\(method))")
                    XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "ok", "response body (\(method))")
                }
                waitForExpectationsWithTimeout(5, handler: nil)
            }
        }
        
        func setupServer(method: HTTPManagerRequest.Method) {
            expectationForHTTPRequest(httpServer, path: "/submit") { request, completionHandler in
                XCTAssertEqual(request.method, HTTPServer.Method(method), "request method")
                guard request.headers["Content-Type"] == "application/x-www-form-urlencoded" else {
                    XCTFail("Unexpected content type: \(String(reflecting: request.headers["Content-Type"])) (\(method))")
                    return completionHandler(HTTPServer.Response(status: .UnsupportedMediaType))
                }
                guard let bodyText = request.body.flatMap({String(data: $0, encoding: NSUTF8StringEncoding)}) else {
                    XCTFail("Missing request body, or body not utf-8 (\(method))")
                    return completionHandler(HTTPServer.Response(status: .BadRequest))
                }
                let comps = NSURLComponents()
                comps.percentEncodedQuery = bodyText
                // sort the query items because the dictionary form is not order-preserving
                XCTAssertEqual(sortedQueryItems(comps.queryItems ?? []), sortedQueryItems(queryItems), "form data (\(method))")
                completionHandler(HTTPServer.Response(status: .OK, text: "ok"))
            }
        }
        for method in [HTTPManagerRequest.Method.POST, .PUT, .PATCH] {
            do {
                let request: HTTPManagerActionRequest
                switch method {
                case .POST: request = HTTP.request(POST: "submit", parameters: queryItems)
                case .PUT: request = HTTP.request(PUT: "submit", parameters: queryItems)
                case .PATCH: request = HTTP.request(PATCH: "submit", parameters: queryItems)
                default: fatalError()
                }
                setupServer(method)
                expectationForRequestSuccess(request) { task, response, value in
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
                    XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "ok", "response body")
                }
                waitForExpectationsWithTimeout(5, handler: nil)
            }
            // try again using the dictionary form for the request
            do {
                let request: HTTPManagerActionRequest
                switch method {
                case .POST: request = HTTP.request(POST: "submit", parameters: parameters)
                case .PUT: request = HTTP.request(PUT: "submit", parameters: parameters)
                case .PATCH: request = HTTP.request(PATCH: "submit", parameters: parameters)
                default: fatalError()
                }
                setupServer(method)
                expectationForRequestSuccess(request) { task, response, value in
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code (\(method))")
                    XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "ok", "response body (\(method))")
                }
                waitForExpectationsWithTimeout(5, handler: nil)
            }
            // check the data/JSON versions
            do {
                let data = "Hello".dataUsingEncoding(NSUTF8StringEncoding)!
                let json: JSON = ["ok": true]
                let (dataRequest, jsonRequest): (HTTPManagerActionRequest, HTTPManagerActionRequest)
                switch method {
                case .POST:
                    dataRequest = HTTP.request(POST: "data", data: data)
                    jsonRequest = HTTP.request(POST: "json", json: json)
                case .PUT:
                    dataRequest = HTTP.request(PUT: "data", data: data)
                    jsonRequest = HTTP.request(PUT: "json", json: json)
                case .PATCH:
                    dataRequest = HTTP.request(PATCH: "data", data: data)
                    jsonRequest = HTTP.request(PATCH: "json", json: json)
                default: fatalError()
                }
                dataRequest.parameters = queryItems
                jsonRequest.parameters = queryItems
                expectationForHTTPRequest(httpServer, path: "/data") { (request, completionHandler) in
                    XCTAssertEqual(request.method, HTTPServer.Method(method), "request method")
                    XCTAssertEqual(request.urlComponents.queryItems ?? [], queryItems, "request url query (\(method))")
                    XCTAssertEqual(request.body, data, "request body (\(method))")
                    completionHandler(HTTPServer.Response(status: .OK, text: "ok"))
                }
                expectationForHTTPRequest(httpServer, path: "/json") { (request, completionHandler) in
                    XCTAssertEqual(request.method, HTTPServer.Method(method), "request method")
                    XCTAssertEqual(request.urlComponents.queryItems ?? [], queryItems, "request url query (\(method))")
                    do {
                        let requestJson = try JSON.decode(request.body ?? NSData())
                        XCTAssertEqual(requestJson, json, "request json body (\(method))")
                    } catch {
                        XCTFail("error decoding JSON: \(error)")
                    }
                    completionHandler(HTTPServer.Response(status: .OK, text: "ok"))
                }
                expectationForRequestSuccess(dataRequest) { (task, response, value) in
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code (\(method))")
                    XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "ok", "response body (\(method))")
                }
                expectationForRequestSuccess(jsonRequest) { (task, response, value) in
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code (\(method))")
                    XCTAssertEqual(String(data: value, encoding: NSUTF8StringEncoding), "ok", "response body (\(method))")
                }
                waitForExpectationsWithTimeout(5, handler: nil)
            }
        }
    }
    
    func testParse() {
        // parseAsJSON
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            XCTAssertEqual(request.method, HTTPServer.Method.GET)
            XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header")
            completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "{ \"array\": [1, 2, 3], \"ok\": true }"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo").parseAsJSON()) { task, response, value in
            if let response = response as? NSHTTPURLResponse {
                XCTAssertEqual(response.statusCode, 200, "response status code")
                XCTAssertEqual(response.allHeaderFields["Content-Type"] as? String, "application/json", "response Content-Type header")
            } else {
                XCTFail("Non–HTTP Response found: \(response)")
            }
            XCTAssertEqual(response.MIMEType, "application/json", "response MIME type")
            XCTAssertEqual(value, ["array": [1,2,3], "ok": true])
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // parseAsJSONWithHandler
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.method, HTTPServer.Method.GET, "request method")
                XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header")
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "{ \"array\": [1, 2, 3], \"ok\": true }"))
            }
            let req = HTTP.request(GET: "foo").parseAsJSONWithHandler({ response, json -> Int in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "application/json", "response content type")
                XCTAssertEqual(response.MIMEType, "application/json", "response MIME type")
                let ok = json["ok"]?.bool
                XCTAssertEqual(ok, true, "response json 'ok' value")
                return try Int(json.getArray("array") { try $0.reduce(0, combine: { try $0 + $1.getInt64() }) })
            })
            expectationForRequestSuccess(req) { task, response, value in
                if let response = response as? NSHTTPURLResponse {
                    XCTAssertEqual(response.statusCode, 200, "response status code")
                    XCTAssertEqual(response.allHeaderFields["Content-Type"] as? String, "application/json", "response Content-Type header")
                } else {
                    XCTFail("Non–HTTP Response found: \(response)")
                }
                XCTAssertEqual(response.MIMEType, "application/json", "response MIME type")
                XCTAssertEqual(value, 6, "response body value")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // parseWithHandler
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.method, HTTPServer.Method.GET, "request method")
                completionHandler(HTTPServer.Response(status: .OK, text: "foobar"))
            }
            struct InvalidUTF8Error: ErrorType {}
            let req = HTTP.request(GET: "foo").parseWithHandler({ response, data -> String in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "text/plain", "response Content-Type header")
                XCTAssertEqual(response.MIMEType, "text/plain", "response MIME type")
                guard let str = String(data: data, encoding: NSUTF8StringEncoding) else {
                    throw InvalidUTF8Error()
                }
                return String(str.characters.lazy.reverse())
            })
            expectationForRequestSuccess(req) { task, response, value in
                if let response = response as? NSHTTPURLResponse {
                    XCTAssertEqual(response.statusCode, 200, "response status code")
                    XCTAssertEqual(response.allHeaderFields["Content-Type"] as? String, "text/plain", "response Content-Type header")
                } else {
                    XCTFail("Non–HTTP Response found: \(response)")
                }
                XCTAssertEqual(response.MIMEType, "text/plain", "response MIME type")
                XCTAssertEqual(value, "raboof", "response body value")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // parseAsJSON, no Content-Type in response
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            XCTAssertEqual(request.method, HTTPServer.Method.GET)
            XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header")
            completionHandler(HTTPServer.Response(status: .OK, body: "{ \"array\": [1, 2, 3], \"ok\": true }"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo").parseAsJSON()) { task, response, value in
            if let response = response as? NSHTTPURLResponse {
                XCTAssertEqual(response.statusCode, 200, "response status code")
                let contentType = response.allHeaderFields["Content-Type"]
                XCTAssertNil(contentType, "response Content-Type header")
            } else {
                XCTFail("Non–HTTP Response found: \(response)")
            }
            XCTAssertEqual(value, ["array": [1,2,3], "ok": true])
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // parse for */*
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.method, HTTPServer.Method.GET)
                XCTAssertEqual(request.headers["Accept"], "*/*", "request accept header")
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "text/plain"], body: "{ \"array\": [1, 2, 3], \"ok\": true }"))
            }
            let req = HTTP.request(GET: "foo").parseAsJSON()
            req.expectedContentTypes = ["*/*"]
            expectationForRequestSuccess(req) { task, response, value in
                if let response = response as? NSHTTPURLResponse {
                    XCTAssertEqual(response.statusCode, 200, "response status code")
                    XCTAssertEqual(response.allHeaderFields["Content-Type"] as? String, "text/plain", "response Content-Type header")
                } else {
                    XCTFail("Non–HTTP Response found: \(response)")
                }
                XCTAssertEqual(response.MIMEType, "text/plain", "response MIME type")
                XCTAssertEqual(value, ["array": [1,2,3], "ok": true], "response json value")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // parse for text/*, both success and failure
        do {
            let data = "Hello world".dataUsingEncoding(NSUTF8StringEncoding)!
            for _ in 0..<2 {
                expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                    XCTAssertEqual(request.headers["Accept"], "text/*", "request accept header")
                    let contentType = request.headers["X-ResultContentType"] ?? "text/plain"
                    completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": contentType], body: data))
                }
            }
            let req = HTTP.request(GET: "foo").parseWithHandler { response, data -> Int in
                return data.length
            }
            req.expectedContentTypes = ["text/*"]
            expectationForRequestSuccess(req) { task, response, value in
                if let response = response as? NSHTTPURLResponse {
                    XCTAssertEqual(response.statusCode, 200, "response status code")
                    XCTAssertEqual(response.allHeaderFields["Content-Type"] as? String, "text/plain", "response Content-Type header")
                } else {
                    XCTFail("Non–HTTP Response found: \(response)")
                }
                XCTAssertEqual(response.MIMEType, "text/plain", "response MIME type")
                XCTAssertEqual(value, 11, "response parsed value")
            }
            req.headerFields["X-ResultContentType"] = "application/json"
            expectationForRequestFailure(req) { task, response, error in
                if let response = response as? NSHTTPURLResponse {
                    XCTAssertEqual(response.statusCode, 200, "response status code")
                    XCTAssertEqual(response.allHeaderFields["Content-Type"] as? String, "application/json", "response Content-Type header")
                } else {
                    XCTFail("Non–HTTP Response found: \(response)")
                }
                XCTAssertEqual(response?.MIMEType, "application/json", "response MIME type")
                if case let HTTPManagerError.UnexpectedContentType(contentType, response_, body) = error {
                    XCTAssert(response === response_, "error response")
                    XCTAssertEqual(contentType, "application/json", "error content type")
                    XCTAssertEqual(body, data, "error body")
                } else {
                    XCTFail("expected HTTPManagerError.UnexpectedContentType; found \(error)")
                }
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testMultipleExpectedContentTypes() {
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.headers["Accept"], "application/json, text/plain;q=0.9, text/html;q=0.8, */*;q=0.7", "request accept header")
                completionHandler(HTTPServer.Response(status: .OK, text: "{ \"ok\": true }"))
            }
            let req = HTTP.request(GET: "foo").parseAsJSON()
            XCTAssertEqual(req.expectedContentTypes, ["application/json"], "request expected content types")
            req.expectedContentTypes += ["text/plain", "text/html", "*/*"]
            expectationForRequestSuccess(req) { task, response, json in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "text/plain", "response content type header")
                XCTAssertEqual(response.MIMEType, "text/plain", "response MIME type")
                XCTAssertEqual(json, ["ok": true], "response body json value")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.headers["Accept"], "text/plain;q=0.5, text/html;level=1;q=0.9, text/html;level=2;q=0.2, application/json;q=0.8", "request accept header")
                completionHandler(HTTPServer.Response(status: .OK, text: "{ \"ok\": true }"))
            }
            let req = HTTP.request(GET: "foo").parseAsJSON()
            req.expectedContentTypes = ["text/plain;q=0.5", "text/html;level=1", "text/html;level=2;q=0.2", "application/json"]
            expectationForRequestSuccess(req) { task, response, json in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "text/plain", "response content type header")
                XCTAssertEqual(response.MIMEType, "text/plain", "response MIME type")
                XCTAssertEqual(json, ["ok": true], "response body json value")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testUnexpectedNoContent() {
        for _ in 0..<3 {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.method, HTTPServer.Method.GET, "request method")
                completionHandler(HTTPServer.Response(status: .NoContent))
            }
        }
        expectationForRequestFailure(HTTP.request(GET: "foo").parseAsJSON()) { task, response, error in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code")
            switch error {
            case HTTPManagerError.UnexpectedNoContent: break
            default: XCTFail("expected error .UnexpectedNoContent, found \(error)")
            }
        }
        expectationForRequestFailure(HTTP.request(GET: "foo").parseAsJSONWithHandler({ _ in 42 })) { task, response, error in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code")
            switch error {
            case HTTPManagerError.UnexpectedNoContent: break
            default: XCTFail("expected error .UnexpectedNoContent, found \(error)")
            }
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo").parseWithHandler({ _ in 42 })) { task, response, value in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code")
            XCTAssertEqual(value, 42, "response body parse value")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testUnexpectedContentType() {
        // no content type
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            XCTAssertEqual(request.method, HTTPServer.Method.GET, "request method")
            XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header")
            completionHandler(HTTPServer.Response(status: .OK, body: "{ \"ok\": true }"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo").parseAsJSON()) { task, response, json in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "response status code")
            let header = (response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String
            XCTAssertNil(header, "response content type header")
            // don't test MIMEType, NSURLSession may return a non-nil value despite the server not specifying a content type
            XCTAssertEqual(json, ["ok": true], "response body json value")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // wrong type - json parse
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.method, HTTPServer.Method.GET, "request method")
                XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header")
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "text/html"], body: "{ \"ok\": true }"))
            }
            let req = HTTP.request(GET: "foo").parseAsJSON()
            XCTAssertEqual(req.expectedContentTypes, ["application/json"], "request expected content types")
            expectationForRequestFailure(req) { task, response, error in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "response status code")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "text/html", "response content type header")
                XCTAssertEqual(response?.MIMEType, "text/html", "response MIME type")
                switch error {
                case let HTTPManagerError.UnexpectedContentType(contentType, response_, body):
                    XCTAssert(response === response_, "error response")
                    XCTAssertEqual(contentType, "text/html", "error content type")
                    if let str = String(data: body, encoding: NSUTF8StringEncoding) {
                        XCTAssertEqual(str, "{ \"ok\": true }", "error body")
                    } else {
                        XCTFail("error body was not a utf-8 string: \(body)")
                    }
                default: XCTFail("expected error .UnexpectedContentType, found \(error)")
                }
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // wrong type - manual parse
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.method, HTTPServer.Method.GET, "request method")
                XCTAssertEqual(request.headers["Accept"], "text/plain", "request accept header")
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "text/html"], body: "Hello world"))
            }
            let req = HTTP.request(GET: "foo").parseWithHandler({ _ -> Int in
                XCTFail("parse handler unexpectedly called")
                return 42
            })
            XCTAssertEqual(req.expectedContentTypes, [], "request expected content types")
            req.expectedContentTypes = ["text/plain"]
            expectationForRequestFailure(req) { task, response, error in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "response status code")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "text/html", "response content type header")
                XCTAssertEqual(response?.MIMEType, "text/html", "response MIME type")
                switch error {
                case let HTTPManagerError.UnexpectedContentType(contentType, response_, body):
                    XCTAssert(response === response_, "error response")
                    XCTAssertEqual(contentType, "text/html", "error content type")
                    if let str = String(data: body, encoding: NSUTF8StringEncoding) {
                        XCTAssertEqual(str, "Hello world", "error body")
                    } else {
                        XCTFail("error body was not a utf-8 string: \(body)")
                    }
                default: XCTFail("expected error .UnexpectedContentType, found \(error)")
                }
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // wrong type - 204 No Content, GET request, JSON parse
        // this should return .UnexpectedNoContent instead of .UnexpectedContentType
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            XCTAssertEqual(request.method, HTTPServer.Method.GET, "request method")
            XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header")
            completionHandler(HTTPServer.Response(status: .NoContent, headers: ["Content-Type": "text/html"]))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo").parseAsJSON()) { task, response, error in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code")
            XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "text/html", "response content type header")
            XCTAssertEqual(response?.MIMEType, "text/html", "response MIME type")
            switch error {
            case HTTPManagerError.UnexpectedNoContent: break
            default: XCTFail("expected error .UnexpectedNoContent, found \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // wrong type - 204 No Content, GET request, custom parse
        // this succeeds because Content-Type is ignored for 204 No Content
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.method, HTTPServer.Method.GET, "request method")
                XCTAssertEqual(request.headers["Accept"], "text/plain", "request accept header")
                completionHandler(HTTPServer.Response(status: .NoContent, headers: ["Content-Type": "text/html"]))
            }
            let req = HTTP.request(GET: "foo").parseWithHandler({ response, data -> Int in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "text/html", "response content type header")
                XCTAssertEqual(response.MIMEType, "text/html", "response MIME type")
                return 42
            })
            req.expectedContentTypes = ["text/plain"]
            expectationForRequestSuccess(req) { task, response, value in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "text/html", "response content type header")
                XCTAssertEqual(response.MIMEType, "text/html", "response MIME type")
                XCTAssertEqual(value, 42, "response body parse value")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // wrong type - 204 No Content, DELETE request, JSON parse
        // this succeeds because Content-Type is ignored for 204 No Content
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            XCTAssertEqual(request.method, HTTPServer.Method.DELETE, "request method")
            XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header")
            completionHandler(HTTPServer.Response(status: .NoContent, headers: ["Content-Type": "text/html"]))
        }
        expectationForRequestSuccess(HTTP.request(DELETE: "foo").parseAsJSON()) { task, response, value in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code")
            XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, "text/html", "response content type header")
            XCTAssertEqual(response.MIMEType, "text/html", "response MIME type")
            XCTAssertNil(value, "response body json value")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testInvalidJSONParse() {
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "[1, 2"))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo").parseAsJSON()) { task, response, error in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "response status code")
            XCTAssertEqual(response?.MIMEType, "application/json", "response MIME type")
            // we only care that it's a JSON error, not specifically what the error is
            XCTAssert(error is JSONParserError, "expected JSONParserError, found \(error)")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "[1, 2"))
            }
            struct CantBeThrownError: ErrorType {}
            let req = HTTP.request(GET: "foo").parseAsJSONWithHandler({ (response, json) -> Int in
                throw CantBeThrownError()
            })
            expectationForRequestFailure(req) { task, response, error in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "response status code")
                XCTAssertEqual(response?.MIMEType, "application/json", "response MIME type")
                // we only care that it's a JSON error, not specifically what the error is
                XCTAssert(error is JSONParserError, "expected JSONParserError, found \(error)")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testJSONErrors() {
        // Error with JSON response
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .BadRequest, headers: ["Content-Type": "application/json"], body: "{ \"error\": \"You sent a bad request\" }"))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo")) { task, response, error in
            XCTAssertEqual(response?.MIMEType, "application/json", "response MIME type")
            if case let HTTPManagerError.FailedResponse(_, _, _, json) = error {
                XCTAssertEqual(json, ["error": "You sent a bad request"], "error body json")
            } else {
                XCTFail("expected HTTPManagerError.FailedResponse, found \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // Error with declared JSON type but invalid JSON body
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .BadRequest, headers: ["Content-Type": "application/json"], body: "{ error: \"You sent a bad request\" }"))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo")) { task, response, error in
            XCTAssertEqual(response?.MIMEType, "application/json", "response MIME type")
            if case let HTTPManagerError.FailedResponse(_, _, _, json) = error {
                XCTAssertNil(json, "error body json")
            } else {
                XCTFail("expected HTTPManagerError.FailedResponse, found \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // Error with no declared Content-Type and valid JSON body
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .BadRequest, body: "{ \"error\": \"You sent a bad request\" }"))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo")) { task, response, error in
            // NSURLResponse.MIMEType will typically report something like text/plain in this case, but it's not guaranteed what it reports.
            // Just assume it won't ever auto-detect JSON.
            XCTAssertNotEqual(response?.MIMEType, "application/json", "response MIME type")
            if case let HTTPManagerError.FailedResponse(_, _, _, json) = error {
                XCTAssertNil(json, "error body json")
            } else {
                XCTFail("expected HTTPManagerError.FailedResponse, found \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        // Error with explicitly-declared non-JSON Content-Type and valid JSON body
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .BadRequest, headers: ["Content-Type": "text/html"], body: "{ \"error\": \"You sent a bad request\" }"))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo")) { task, response, error in
            XCTAssertEqual(response?.MIMEType, "text/html", "response MIME type")
            if case let HTTPManagerError.FailedResponse(_, _, _, json) = error {
                XCTAssertNil(json, "error body json")
            } else {
                XCTFail("expected HTTPManagerError.FailedResponse, found \(error)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testObjCJSONErrors() {
        // test to make sure that converting JSON errors into ObjC strips nulls from the JSON
        do {
            let data = "{ \"ok\": false, \"title\": null, \"elts\": [null, 1, null, 2] }".dataUsingEncoding(NSUTF8StringEncoding)!
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .BadRequest, headers: ["Content-Type": "application/json"], body: data))
            }
            expectationForRequestFailure(HTTP.request(GET: "foo")) { task, response, error in
                XCTAssertEqual(response?.MIMEType, "application/json", "response MIME type")
                if case let error as HTTPManagerError = error, case let HTTPManagerError.FailedResponse(statusCode, response_, body, json) = error {
                    // check the Swift error first
                    XCTAssert(response === response_, "error response")
                    XCTAssertEqual(statusCode, 400, "error status code")
                    XCTAssertEqual(body, data, "error body data")
                    XCTAssertEqual(json, ["ok": false, "title": nil, "elts": [nil, 1, nil, 2]], "error body json")
                    // Now check the converted version
                    let nserror = error.toNSError()
                    XCTAssertEqual(nserror.domain, PMHTTPErrorDomain, "NSError domain")
                    XCTAssertEqual(nserror.code, PMHTTPError.FailedResponse.rawValue, "NSError code")
                    XCTAssert(nserror.userInfo[PMHTTPURLResponseErrorKey] === response_, "NSError response")
                    XCTAssertEqual(nserror.userInfo[PMHTTPStatusCodeErrorKey] as? Int, 400, "NSError status code")
                    XCTAssertEqual(nserror.userInfo[PMHTTPBodyDataErrorKey] as? NSData, data, "NSError body data")
                    XCTAssertEqual(nserror.userInfo[PMHTTPBodyJSONErrorKey] as? NSDictionary, ["ok": false, "elts": [1, 2]], "NSError body json")
                    // And back again
                    let bridged = HTTPManagerError(nserror)
                    switch bridged {
                    case let HTTPManagerError.FailedResponse(statusCode_, response_, body_, json_)?:
                        XCTAssert(response === response_, "bridged error response")
                        XCTAssertEqual(statusCode_, statusCode, "bridged error status code")
                        XCTAssertEqual(body_, body, "bridged error body data")
                        // bridging will strip nulls, and pass numbers through NSNumber, so lets do that here too
                        if let jsonNoNull = (json?.nsNoNull).flatMap({try? JSON(ns: $0)}) {
                            XCTAssertEqual(json_, jsonNoNull, "bridged error body json")
                        } else {
                            XCTFail("Couldn't round-trip JSON payload through nsNoNull")
                        }
                    default:
                        XCTFail("bridged error expected HTTPManagerError.FailedResponse, found \(bridged)")
                    }
                } else {
                    XCTFail("expected HTTPManagerError.FailedResponse, found \(error)")
                }
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        // test to make sure that the JSON value is always a dictionary
        do {
            let data = "[1, 2, 3]".dataUsingEncoding(NSUTF8StringEncoding)
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .BadRequest, headers: ["Content-Type": "application/json"], body: data))
            }
            expectationForRequestFailure(HTTP.request(GET: "foo")) { task, response, error in
                XCTAssertEqual(response?.MIMEType, "application/json", "response MIME type")
                if case let error as HTTPManagerError = error, case let HTTPManagerError.FailedResponse(statusCode, response_, body, json) = error {
                    // check the Swift error first
                    XCTAssert(response === response_, "error response")
                    XCTAssertEqual(statusCode, 400, "error status code")
                    XCTAssertEqual(body, data, "error body data")
                    XCTAssertEqual(json, [1, 2, 3], "error body json")
                    // Now check the converted version
                    let nserror = error.toNSError()
                    XCTAssertEqual(nserror.domain, PMHTTPErrorDomain, "NSError domain")
                    XCTAssertEqual(nserror.code, PMHTTPError.FailedResponse.rawValue, "NSError code")
                    XCTAssert(nserror.userInfo[PMHTTPURLResponseErrorKey] === response_, "NSError response")
                    XCTAssertEqual(nserror.userInfo[PMHTTPStatusCodeErrorKey] as? Int, 400, "NSError status code")
                    XCTAssertEqual(nserror.userInfo[PMHTTPBodyDataErrorKey] as? NSData, data, "NSError body data")
                    XCTAssertNil(nserror.userInfo[PMHTTPBodyJSONErrorKey], "NSError body json")
                    // And back again
                    let bridged = HTTPManagerError(nserror)
                    switch bridged {
                    case let HTTPManagerError.FailedResponse(statusCode_, response_, body_, json_)?:
                        XCTAssert(response === response_, "bridged error response")
                        XCTAssertEqual(statusCode_, statusCode, "bridged error status code")
                        XCTAssertEqual(body_, body, "bridged error body data")
                        XCTAssertNil(json_, "bridged error body json")
                    default:
                        XCTFail("bridged error expected HTTPManagerError.FailedResponse, found \(bridged)")
                    }
                } else {
                    XCTFail("expected HTTPManagerError.FailedResponse, found \(error)")
                }
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testEnvironmentWithPath() {
        HTTP.environment = HTTPManager.Environment(string: "http://\(httpServer.address)/api/v1")!
        expectationForHTTPRequest(httpServer, path: "/api/v1/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .OK))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo")) { [address=httpServer.address] (task, response, value) -> Void in
            XCTAssertEqual(response.URL?.absoluteString, "http://\(address)/api/v1/foo", "response url does not match")
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code is not OK")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testEnvironmentURLs() {
        XCTAssertEqual(HTTPManager.Environment(string: "http://apple.com")?.baseURL.absoluteString, "http://apple.com")
        XCTAssertEqual(HTTPManager.Environment(string: "http://apple.com/")?.baseURL.absoluteString, "http://apple.com/")
        XCTAssertEqual(HTTPManager.Environment(string: "http://apple.com/foo")?.baseURL.absoluteString, "http://apple.com/foo/")
        XCTAssertEqual(HTTPManager.Environment(string: "http://apple.com/foo/")?.baseURL.absoluteString, "http://apple.com/foo/")
        XCTAssertEqual(HTTPManager.Environment(string: "http://apple.com/foo?bar=baz")?.baseURL.absoluteString, "http://apple.com/foo/")
        XCTAssertEqual(HTTPManager.Environment(string: "http://apple.com/foo#bar")?.baseURL.absoluteString, "http://apple.com/foo/")
        
        XCTAssertEqual(HTTPManager.Environment(baseURL: NSURL(string: "http://apple.com/foo")!)?.baseURL.absoluteString, "http://apple.com/foo/")
        XCTAssertEqual(HTTPManager.Environment(baseURL: NSURL(string: "foo", relativeToURL: NSURL(string: "http://apple.com"))!)?.baseURL.absoluteString, "http://apple.com/foo/")
    }
    
    func testRequestPaths() {
        var skipRemainingTests = false
        func runTest(requestPath: String, urlPath: String, serverPath: String? = nil, file: StaticString = #file, line: UInt = #line) {
            if skipRemainingTests { return }
            expectationForHTTPRequest(httpServer, path: serverPath ?? urlPath) { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK))
            }
            let request = HTTP.request(GET: requestPath)
            XCTAssertEqual(request.url.absoluteString, "http://\(httpServer.address)\(urlPath)", "request url does not match", file: file, line: line)
            expectationForRequestSuccess(request) { [address=httpServer.address] task, response, value in
                XCTAssertEqual(response.URL?.absoluteString, "http://\(address)\(serverPath ?? urlPath)", "response url does not match", file: file, line: line)
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code is not OK", file: file, line: line)
            }
            waitForExpectationsWithTimeout(5, file: file, line: line) { [httpServer] error in
                if error != nil {
                    // if we timed out here, we'll probably time out on the rest of them too
                    skipRemainingTests = true
                    httpServer.reset()
                }
            }
        }
        runTest("/foo", urlPath: "/foo")
        runTest("foo", urlPath: "/foo")
        runTest("foo/", urlPath: "/foo/")
        runTest("/", urlPath: "/")
        runTest("", urlPath: "", serverPath: "/")
        runTest("/foo/bar", urlPath: "/foo/bar")
        runTest("foo/bar", urlPath: "/foo/bar")
        
        HTTP.environment = HTTPManager.Environment(string: "http://\(httpServer.address)/")!
        runTest("/foo", urlPath: "/foo")
        runTest("foo", urlPath: "/foo")
        runTest("foo/", urlPath: "/foo/")
        runTest("/", urlPath: "/")
        runTest("", urlPath: "/")
        
        HTTP.environment = HTTPManager.Environment(string: "http://\(httpServer.address)/api/v1/")!
        runTest("/foo", urlPath: "/foo")
        runTest("foo", urlPath: "/api/v1/foo")
        runTest("foo/", urlPath: "/api/v1/foo/")
        runTest("/", urlPath: "/")
        runTest("", urlPath: "/api/v1/")
    }
    
    func testChangingEnvironment() {
        // fire off one request, change the environment, fire a second, and make sure they both complete
        let group = dispatch_group_create()
        dispatch_group_enter(group)
        expectationForHTTPRequest(httpServer, path: "/one") { request, completionHandler in
            // wait until we know we've fired off the second request before letting the first one finish
            dispatch_group_notify(group, dispatch_get_global_queue(0,0)) {
                completionHandler(HTTPServer.Response(status: .OK))
            }
        }
        expectationForHTTPRequest(httpServer, path: "/foo/two") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .OK))
        }
        expectationForRequestSuccess(HTTP.request(GET: "one")) { [address=httpServer.address] task, response, value in
            XCTAssertEqual(response.URL?.absoluteString, "http://\(address)/one")
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200)
        }
        HTTP.environment = HTTPManager.Environment(string: "http://\(httpServer.address)/foo")!
        expectationForRequestSuccess(HTTP.request(GET: "two")) { [address=httpServer.address] task, response, value in
            XCTAssertEqual(response.URL?.absoluteString, "http://\(address)/foo/two")
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200)
        }
        dispatch_group_leave(group)
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testHeaders() {
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            XCTAssertEqual(request.headers["X-Foo"], "bar", "X-Foo header")
            completionHandler(HTTPServer.Response(status: .OK, headers: ["X-Baz": "qux"]))
        }
        let req = HTTP.request(GET: "foo")
        req.headerFields["X-Foo"] = "bar"
        expectationForRequestSuccess(req) { task, response, data in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["X-Baz"] as? String, "qux", "X-Baz header")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testActions() {
        for method in [HTTPManagerRequest.Method.POST, .PUT, .PATCH, .DELETE] {
            let request: HTTPManagerActionRequest
            switch method {
            case .POST: request = HTTP.request(POST: "foo")
            case .PUT: request = HTTP.request(PUT: "foo")
            case .PATCH: request = HTTP.request(PATCH: "foo")
            case .DELETE: request = HTTP.request(DELETE: "foo")
            default: fatalError("unreachable")
            }
            
            // 200 OK
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.method, HTTPServer.Method(method), "request method (\(method))")
                XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header (\(method))")
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "{ \"ok\": true }"))
            }
            expectationForRequestSuccess(request.parseAsJSON()) { task, response, json in
                XCTAssertEqual(task.networkTask.currentRequest?.HTTPMethod, String(method), "current request method (\(method))")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "response status code (\(method))")
                XCTAssertEqual(json, ["ok": true], "response body json (\(method))")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
            
            do {
                expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                    XCTAssertEqual(request.method, HTTPServer.Method(String(method)), "request method (\(method))")
                    XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header (\(method))")
                    completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "{ \"ary\": [1,2,3] }"))
                }
                let req = request.parseAsJSONWithHandler({ result -> Int in
                    return Int(try result.getJSON().getArray("ary", { try $0.reduce(0, combine: { try $0 + $1.getInt64() }) }))
                })
                expectationForRequestSuccess(req) { task, response, value in
                    XCTAssertEqual(task.networkTask.currentRequest?.HTTPMethod, String(method), "current request method (\(method))")
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "response status code (\(method))")
                    XCTAssertEqual(value, 6, "response body value (\(method))")
                }
                waitForExpectationsWithTimeout(5, handler: nil)
            }
            
            do {
                expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                    XCTAssertEqual(request.method, HTTPServer.Method(String(method)), "request method (\(method))")
                    completionHandler(HTTPServer.Response(status: .OK, text: "foobar"))
                }
                struct DecodeError: ErrorType {}
                let req = request.parseWithHandler({ response, data -> String in
                    guard let str = String(data: data, encoding: NSUTF8StringEncoding) else {
                        throw DecodeError()
                    }
                    return str
                })
                expectationForRequestSuccess(req) { task, response, str in
                    XCTAssertEqual(task.networkTask.currentRequest?.HTTPMethod, String(method), "current request method (\(method))")
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "response status code (\(method))")
                    XCTAssertEqual(str, "foobar", "response body string (\(method))")
                }
                waitForExpectationsWithTimeout(5, handler: nil)
            }
            
            // 204 No Content
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.method, HTTPServer.Method(String(method)), "request method (\(method))")
                XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header (\(method))")
                completionHandler(HTTPServer.Response(status: .NoContent))
            }
            expectationForRequestSuccess(request.parseAsJSON()) { task, response, json in
                XCTAssertEqual(task.networkTask.currentRequest?.HTTPMethod, String(method), "current request method (\(method))")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code (\(method))")
                XCTAssertNil(json, "response body json (\(method))")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
            
            do {
                expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                    XCTAssertEqual(request.method, HTTPServer.Method(String(method)), "request method (\(method))")
                    XCTAssertEqual(request.headers["Accept"], "application/json", "request accept header (\(method))")
                    completionHandler(HTTPServer.Response(status: .NoContent))
                }
                let req = request.parseAsJSONWithHandler({ result -> Int in
                    XCTAssertEqual((result.response as? NSHTTPURLResponse)?.statusCode, 204, "parse handler response status code (\(method))")
                    XCTAssertNil(result.json, "parse handler json value (\(method))")
                    return 42
                })
                expectationForRequestSuccess(req) { task, response, value in
                    XCTAssertEqual(task.networkTask.currentRequest?.HTTPMethod, String(method), "current request method (\(method))")
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code (\(method))")
                    XCTAssertEqual(value, 42, "response body parsed value (\(method))")
                }
                waitForExpectationsWithTimeout(5, handler: nil)
            }
            
            do {
                expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                    XCTAssertEqual(request.method, HTTPServer.Method(String(method)), "request method (\(method))")
                    completionHandler(HTTPServer.Response(status: .NoContent))
                }
                let req = request.parseWithHandler({ response, data -> String? in
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code (\(method))")
                    XCTAssertEqual(0, data.length, "response data length (\(method))")
                    return "foo"
                })
                expectationForRequestSuccess(req) { task, response, value in
                    XCTAssertEqual(task.networkTask.currentRequest?.HTTPMethod, String(method), "current request method (\(method))")
                    XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 204, "response status code (\(method))")
                    XCTAssertEqual(value, "foo", "response body parsed value (\(method))")
                }
                waitForExpectationsWithTimeout(5, handler: nil)
            }
        }
    }
    
    func testRedirections() {
        let address = httpServer.address
        
        func addEchoRequestHandlers(requestMethod: HTTPServer.Method, status: HTTPServer.Status, redirectMethod: HTTPServer.Method? = nil, file: StaticString = #file, line: UInt = #line) {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.method, requestMethod, "request method", file: file, line: line)
                completionHandler(HTTPServer.Response(status: status, headers: ["Location": "http://\(address)/bar"]))
            }
            expectationForHTTPRequest(httpServer, path: "/bar") { request, completionHandler in
                XCTAssertEqual(request.method, redirectMethod ?? requestMethod, "redirect method", file: file, line: line)
                completionHandler(HTTPServer.Response(status: .OK, body: request.body))
            }
        }
        func addSuccessHandler(request: HTTPManagerNetworkRequest, redirectMethod: HTTPManagerRequest.Method? = nil, body: String = "", file: StaticString = #file, line: UInt = #line) {
            expectationForRequestSuccess(request) { task, response, data in
                XCTAssertEqual(task.networkTask.originalRequest?.URL?.absoluteString, "http://\(address)/foo", "original request url", file: file, line: line)
                XCTAssertEqual(task.networkTask.originalRequest?.HTTPMethod, String(request.requestMethod), "original request HTTP method", file: file, line: line)
                XCTAssertEqual(task.networkTask.currentRequest?.URL?.absoluteString, "http://\(address)/bar", "current request url", file: file, line: line)
                XCTAssertEqual(task.networkTask.currentRequest?.HTTPMethod, String(redirectMethod ?? request.requestMethod), "current request HTTP method", file: file, line: line)
                XCTAssertEqual(response.URL?.absoluteString, "http://\(address)/bar", "response url", file: file, line: line)
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code", file: file, line: line)
                if let str = String(data: data, encoding: NSUTF8StringEncoding) {
                    XCTAssertEqual(str, body, "body data", file: file, line: line)
                } else {
                    XCTFail("could not interpret body data as utf-8: \(data)", file: file, line: line)
                }
            }
        }

        
        func runTest(status: HTTPServer.Status, preserveMethodOnRedirect: Bool, file: StaticString = #file, line: UInt = #line) {
            // GET
            addEchoRequestHandlers(.GET, status: status, file: file, line: line)
            addSuccessHandler(HTTP.request(GET: "foo"), file: file, line: line)
            waitForExpectationsWithTimeout(5, file: file, line: line, handler: nil)
            HTTP.sessionConfiguration.URLCache?.removeAllCachedResponses()
            
            // POST
            addEchoRequestHandlers(.POST, status: status, redirectMethod: preserveMethodOnRedirect ? .POST : .GET, file: file, line: line)
            addSuccessHandler(HTTP.request(POST: "foo", parameters: ["baz": "qux"]), redirectMethod: preserveMethodOnRedirect ? .POST : .GET, body: preserveMethodOnRedirect ? "baz=qux" : "", file: file, line: line)
            waitForExpectationsWithTimeout(5, file: file, line: line, handler: nil)
            HTTP.sessionConfiguration.URLCache?.removeAllCachedResponses()
            
            // JSON parsing
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: status, headers: ["Location": "http://\(address)/bar"]))
            }
            expectationForHTTPRequest(httpServer, path: "/bar") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "{\"foo\": \"bar\", \"baz\": true, \"ary\": [1,2,3]}"))
            }
            expectationForRequestSuccess(HTTP.request(GET: "foo").parseAsJSON()) { task, response, json in
                XCTAssertEqual(json, ["foo": "bar", "baz": true, "ary": [1,2,3]], "json response", file: file, line: line)
            }
            waitForExpectationsWithTimeout(5, file: file, line: line, handler: nil)
            HTTP.sessionConfiguration.URLCache?.removeAllCachedResponses()
        }
        
        // test basic redirections
        // NB: Experimentally, NSURLSession treats 301 Moved Permanently like a 303 See Other and turns POST into GET.
        // The RFC says this is erroneous behavior, but I guess NSURLSession can't change it without potentially breaking apps.
        runTest(.MovedPermanently, preserveMethodOnRedirect: false)
        // NB: In theory, clients shouldn't change the request method for 302 Found, but most of them change to GET.
        // NSURLSession is one of these clients.
        runTest(.Found, preserveMethodOnRedirect: false)
        runTest(.SeeOther, preserveMethodOnRedirect: false)
        runTest(.TemporaryRedirect, preserveMethodOnRedirect: true)
        
        // test requests with disabled redirections
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .MovedPermanently, headers: ["Location": "http://\(address)/bar"]))
            }
            let token = httpServer.registerRequestCallbackForPath("/bar") { request, completionHandler in
                XCTFail("Unexpected request for path /bar")
                completionHandler(HTTPServer.Response(status: .NotFound))
            }
            let req = HTTP.request(GET: "foo")
            req.shouldFollowRedirects = false
            expectationForRequestSuccess(req) { task, response, data in
                XCTAssertEqual(task.networkTask.originalRequest?.URL?.absoluteString, "http://\(address)/foo", "original request url")
                XCTAssertEqual(task.networkTask.currentRequest?.URL?.absoluteString, "http://\(address)/foo", "current request url")
                XCTAssertEqual(response.URL?.absoluteString, "http://\(address)/foo", "response url")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 301, "status code")
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Location"] as? String, "http://\(address)/bar", "Location header")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
            httpServer.unregisterRequestCallback(token)
            HTTP.sessionConfiguration.URLCache?.removeAllCachedResponses()
        }
        
        func addFailureExpectation(request: HTTPManagerParseRequest<JSON>, file: StaticString = #file, line: UInt = #line) {
            expectationForRequestFailure(request) { task, response, error in
                XCTAssertEqual(task.networkTask.originalRequest?.URL?.absoluteString, "http://\(address)/foo", "original request url", file: file, line: line)
                XCTAssertEqual(task.networkTask.currentRequest?.URL?.absoluteString, "http://\(address)/foo", "current request url", file: file, line: line)
                XCTAssertEqual(response?.URL?.absoluteString, "http://\(address)/foo", "response url", file: file, line: line)
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 301, "status code", file: file, line: line)
                XCTAssertEqual((response as? NSHTTPURLResponse)?.allHeaderFields["Location"] as? String, "http://\(address)/bar", "Location header", file: file, line: line)
                if case let HTTPManagerError.UnexpectedRedirect(statusCode, location, response_, body) = error {
                    XCTAssert(response === response_, "error response")
                    XCTAssertEqual(statusCode, 301, "error status code", file: file, line: line)
                    XCTAssertEqual(location?.absoluteString, "http://\(address)/bar", "error location", file: file, line: line)
                    if let str = String(data: body, encoding: NSUTF8StringEncoding) {
                        XCTAssertEqual(str, "moved", "error body", file: file, line: line)
                    } else {
                        XCTFail("error body was not utf-8: \(body)", file: file, line: line)
                    }
                } else {
                    XCTFail("Unexpected error type: \(error)", file: file, line: line)
                }
            }
        }
        
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .MovedPermanently, headers: ["Location": "http://\(address)/bar"], text: "moved"))
            }
            let token = httpServer.registerRequestCallbackForPath("/bar") { request, completionHandler in
                XCTFail("Unexpected request for path /bar")
                completionHandler(HTTPServer.Response(status: .NotFound))
            }
            let req = HTTP.request(GET: "foo")
            req.shouldFollowRedirects = false
            addFailureExpectation(req.parseAsJSON())
            waitForExpectationsWithTimeout(5, handler: nil)
            httpServer.unregisterRequestCallback(token)
            HTTP.sessionConfiguration.URLCache?.removeAllCachedResponses()
        }
        
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .MovedPermanently, headers: ["Location": "http://\(address)/bar"], text: "moved"))
            }
            let token = httpServer.registerRequestCallbackForPath("/bar") { request, completionHandler in
                XCTFail("Unexpected request for path /bar")
                completionHandler(HTTPServer.Response(status: .NotFound))
            }
            let req = HTTP.request(GET: "foo").parseAsJSON()
            req.shouldFollowRedirects = false
            addFailureExpectation(req)
            waitForExpectationsWithTimeout(5, handler: nil)
            httpServer.unregisterRequestCallback(token)
            HTTP.sessionConfiguration.URLCache?.removeAllCachedResponses()
        }
    }
    
    func testNoEnvironment() {
        HTTP.environment = nil
        expectationForRequestFailure(HTTP.request(GET: "foo")) { task, response, error in
            XCTAssert(task.networkTask.error === error as NSError, "network task error")
            XCTAssertEqual((error as NSError).domain, NSURLErrorDomain, "error domain")
            XCTAssertEqual((error as NSError).code, NSURLErrorUnsupportedURL, "error code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
        
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            completionHandler(HTTPServer.Response(status: .OK, text: "Hello world"))
        }
        expectationForRequestSuccess(HTTP.request(GET: "http://\(httpServer.address)/foo")) { [address=httpServer.address] task, response, data in
            XCTAssertEqual(response.URL?.absoluteString, "http://\(address)/foo", "response URL")
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "response status code")
            if let str = String(data: data, encoding: NSUTF8StringEncoding) {
                XCTAssertEqual(str, "Hello world", "response body")
            } else {
                XCTFail("could not interpret body data as utf-8: \(data)")
            }
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testCachePolicy() {
        XCTAssertNil(HTTP.request(GET: "foo").cachePolicy, "GET request cache policy")
        XCTAssertEqual(HTTP.request(POST: "foo").cachePolicy, .ReloadIgnoringLocalCacheData, "POST request cache policy")
        XCTAssertEqual(HTTP.request(PUT: "foo").cachePolicy, .ReloadIgnoringLocalCacheData, "PUT request cache policy")
        XCTAssertEqual(HTTP.request(PATCH: "foo").cachePolicy, .ReloadIgnoringLocalCacheData, "PATCH request cache policy")
        XCTAssertEqual(HTTP.request(DELETE: "foo").cachePolicy, .ReloadIgnoringLocalCacheData, "DELETE request cache policy")
    }
    
    func testCacheStoragePolicy() {
        guard let cache = HTTP.sessionConfiguration.URLCache else {
            XCTFail("No cache configured on the session")
            return
        }
        // no caching headers
        do {
            cache.removeAllCachedResponses()
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, text: "Hello world"))
            }
            let req = HTTP.request(GET: "foo")
            XCTAssert(req.defaultResponseCacheStoragePolicy == .Allowed, "request cache storage policy")
            expectationForRequestSuccess(req) { _ in }
            waitForExpectationsWithTimeout(5, handler: nil)
            if let response = cache.cachedResponseForRequest(req.preparedURLRequest) {
                XCTAssert(response.storagePolicy == .Allowed, "cached response storage policy")
            } else {
                XCTFail("couldn't find cached response")
            }
        }
        do {
            cache.removeAllCachedResponses()
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, text: "Hello world"))
            }
            let req = HTTP.request(GET: "foo")
            req.defaultResponseCacheStoragePolicy = .AllowedInMemoryOnly
            expectationForRequestSuccess(req) { _ in }
            waitForExpectationsWithTimeout(5, handler: nil)
            if let response = cache.cachedResponseForRequest(req.preparedURLRequest) {
                XCTAssert(response.storagePolicy == .AllowedInMemoryOnly, "cached response storage policy")
            } else {
                XCTFail("couldn't find cached response")
            }
        }
        do {
            cache.removeAllCachedResponses()
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, text: "Hello world"))
            }
            let req = HTTP.request(GET: "foo")
            req.defaultResponseCacheStoragePolicy = .NotAllowed
            expectationForRequestSuccess(req) { _ in }
            waitForExpectationsWithTimeout(5, handler: nil)
            XCTAssert(cache.cachedResponseForRequest(req.preparedURLRequest) == nil, "cached response")
        }
        // caching headers
        for policy in [NSURLCacheStoragePolicy.Allowed, .AllowedInMemoryOnly, .NotAllowed] {
            cache.removeAllCachedResponses()
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                completionHandler(HTTPServer.Response(status: .OK, headers: ["Cache-Control": "max-age=60"], text: "Hello world"))
            }
            let req = HTTP.request(GET: "foo")
            req.defaultResponseCacheStoragePolicy = policy
            expectationForRequestSuccess(req) { _ in }
            waitForExpectationsWithTimeout(5, handler: nil)
            if let response = cache.cachedResponseForRequest(req.preparedURLRequest) {
                XCTAssert(response.storagePolicy == .Allowed, "cached response storage policy")
            } else {
                XCTFail("couldn't find cached response")
            }
        }
        // parse requests
        do {
            let req = HTTP.request(GET: "foo")
            XCTAssert(req.defaultResponseCacheStoragePolicy == .Allowed, "request cache storage policy")
            XCTAssert(req.parseAsJSON().defaultResponseCacheStoragePolicy == .NotAllowed, "json parse request cache storage policy")
            XCTAssert(req.parseAsJSONWithHandler({ $1 }).defaultResponseCacheStoragePolicy == .NotAllowed, "json with handler parse request cache storage policy")
        }
        do {
            let req = HTTP.request(DELETE: "foo")
            XCTAssert(req.defaultResponseCacheStoragePolicy == .Allowed, "request cache storage policy")
            XCTAssert(req.parseAsJSON().defaultResponseCacheStoragePolicy == .NotAllowed, "json parse request cache storage policy")
            XCTAssert(req.parseAsJSONWithHandler({ $0.json }).defaultResponseCacheStoragePolicy == .NotAllowed, "json with handler parse request cache storage policy")
        }
    }
    
    func testEnvironmentIsPrefixOf() {
        func check(envStr: String, isPrefixOfURL urlString: String, withBaseURL baseURLString: String? = nil, toBe expected: Bool, file: StaticString = #file, line: UInt = #line) {
            guard let env = HTTPManager.Environment(string: envStr) else {
                return XCTFail("Could not create HTTPManager.Environment", file: file, line: line)
            }
            let baseURL: NSURL?
            if let baseURLString = baseURLString {
                guard let baseURL_ = NSURL(string: baseURLString) else {
                    return XCTFail("Could not parse base URL string", file: file, line: line)
                }
                baseURL = baseURL_
            } else {
                baseURL = nil
            }
            guard let url = NSURL(string: urlString, relativeToURL: baseURL) else {
                return XCTFail("Could not parse URL string", file: file, line: line)
            }
            let result = env.isPrefixOf(url) == expected
            XCTAssert(result, "expected (\(env.baseURL)).isPrefixOf(\(url)) to be \(expected), but was \(result)", file: file, line: line)
        }
        check("http://ipa.postmates.com", isPrefixOfURL: "http://ipa.postmates.com", toBe: true)
        check("http://ipa.postmates.com", isPrefixOfURL: "http://ipa.postmates.com/", toBe: true)
        check("http://ipa.postmates.com", isPrefixOfURL: "http://ipa.postmates.com/foo", toBe: true)
        check("http://ipa.postmates.com", isPrefixOfURL: "foo", withBaseURL: "http://ipa.postmates.com", toBe: true)
        check("http://ipa.postmates.com", isPrefixOfURL: "https://ipa.postmates.com/foo", toBe: false)
        check("https://ipa.postmates.com/api/v1/", isPrefixOfURL: "https://ipa.postmates.com/api/v1/foo", toBe: true)
        check("https://ipa.postmates.com/api/v1/", isPrefixOfURL: "foo", withBaseURL: "https://ipa.postmates.com/api/v1/", toBe: true)
        check("https://ipa.postmates.com/api/v1/", isPrefixOfURL: "https://ipa.postmates.com/foo", toBe: false)
        check("https://ipa.postmates.com/api/v1/", isPrefixOfURL: "/foo", withBaseURL: "https://ipa.postmates.com/api/v1/", toBe: false)
        check("https://ipa.postmates.com/api/v1/", isPrefixOfURL: "../foo", withBaseURL: "https://ipa.postmates.com/api/v1/", toBe: false)
        check("https://ipa.postmates.com/api/v1/", isPrefixOfURL: "../v1/foo", withBaseURL: "https://ipa.postmates.com/api/v1/", toBe: true)
        check("https://ipa.postmates.com/api/v1/", isPrefixOfURL: "https://ipa.postmates.com:443/api/v1/", toBe: true)
        check("https://ipa.postmates.com:443/api/v1/", isPrefixOfURL: "https://ipa.postmates.com/api/v1/", toBe: true)
        check("https://ipa.postmates.com/api/v1/", isPrefixOfURL: "https://ipa.postmates.com:80/api/v1/", toBe: false)
    }
    
    func testCredentials() {
        func basicAuthentication(user user: String, password: String) -> String {
            let data = "\(user):\(password)".dataUsingEncoding(NSUTF8StringEncoding)!
            let encoded = data.base64EncodedStringWithOptions([])
            return "Basic \(encoded)"
        }
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertNil(request.headers["Authorization"], "request authorization header")
                completionHandler(HTTPServer.Response(status: .OK))
            }
            let req = HTTP.request(GET: "foo")
            XCTAssertNil(req.credential, "request object credential")
            expectationForRequestSuccess(req) { _ in }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.headers["Authorization"], basicAuthentication(user: "alice", password: "secure"), "request authorization header")
                completionHandler(HTTPServer.Response(status: .OK))
            }
            HTTP.defaultCredential = NSURLCredential(user: "alice", password: "secure", persistence: .None)
            let req = HTTP.request(GET: "foo")
            HTTP.defaultCredential = nil
            XCTAssertEqual(req.credential?.user, "alice", "request object credential user")
            XCTAssertEqual(req.credential?.password, "secure", "request object credential password")
            expectationForRequestSuccess(req) { _ in }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.headers["Authorization"], basicAuthentication(user: "alice", password: "secure"), "request authorization header")
                completionHandler(HTTPServer.Response(status: .Unauthorized, headers: ["Content-Type": "application/json"], body: "{ \"error\": \"unauthorized\" }"))
            }
            let req = HTTP.request(GET: "foo")
            req.credential = NSURLCredential(user: "alice", password: "secure", persistence: .None)
            expectationForRequestFailure(req) { task, response, error in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 401, "response status code")
                if case let HTTPManagerError.Unauthorized(credential, response_, _, json) = error {
                    XCTAssert(response === response_, "error response")
                    XCTAssertEqual(credential?.user, "alice", "error credential user")
                    XCTAssertEqual(credential?.password, "secure", "error credential password")
                    XCTAssertEqual(json, ["error": "unauthorized"], "error body json")
                } else {
                    XCTFail("expected HTTPManagerError.Unauthorized, found \(error)")
                }
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        do {
            let req = HTTP.request(GET: "http://apple.com/foo")
            XCTAssertNil(req.credential, "request object credential")
        }
    }
    
    func testDataUpload() {
        do {
            let bodyData = "<?xml version=\"1.0\"?><root><node>wat</node></root>".dataUsingEncoding(NSUTF8StringEncoding)!
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                XCTAssertEqual(request.headers["Content-Type"], "text/xml", "request content-type header")
                XCTAssertEqual(request.body, bodyData, "request body")
                completionHandler(HTTPServer.Response(status: .OK))
            }
            let request = HTTP.request(POST: "foo", contentType: "text/xml", data: bodyData)
            XCTAssertEqual(request.preparedURLRequest.HTTPBody, bodyData, "request body data")
            expectationForRequestSuccess(request) { (task, response, value) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            let bodyData = "foobar".dataUsingEncoding(NSUTF8StringEncoding)!
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                XCTAssertEqual(request.headers["Content-Type"], "application/octet-stream", "request content-type header")
                XCTAssertEqual(request.body, bodyData, "request body")
                completionHandler(HTTPServer.Response(status: .OK))
            }
            expectationForRequestSuccess(HTTP.request(PUT: "foo", data: bodyData)) { (task, response, value) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testJSONUpload() {
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            XCTAssertEqual(request.headers["Content-Type"], "application/json", "request content-type header")
            do {
                let json = try request.body.map({try JSON.decode($0)})
                XCTAssertEqual(json, ["name": "stuff", "elts": [1,2,3], "ok": true, "error": nil], "request json body")
            } catch {
                if let body = request.body, str = String(data: body, encoding: NSUTF8StringEncoding) {
                    XCTFail("couldn't decode JSON body: \(String(reflecting: str))")
                } else {
                    XCTFail("couldn't decode JSON body: \(request.body.map({"\($0.length) bytes"}) ?? "nil")")
                }
            }
            completionHandler(HTTPServer.Response(status: .OK, headers: ["Content-Type": "application/json"], body: "{\"ok\": true, \"msg\": \"upload complete\"}"))
        }
        let json: JSON = ["name": "stuff", "elts": [1,2,3], "ok": true, "error": nil]
        let request = HTTP.request(POST: "foo", json: json)
        XCTAssertEqual(request.preparedURLRequest.HTTPBody, JSON.encodeAsData(json, pretty: false), "request json data")
        expectationForRequestSuccess(request.parseAsJSON()) { task, response, json in
            XCTAssertEqual(response.MIMEType, "application/json", "response MIME type")
            XCTAssertEqual(json, ["ok": true, "msg": "upload complete"], "response body json")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
}
