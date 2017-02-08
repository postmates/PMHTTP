//
//  AuthTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 2/7/17.
//  Copyright © 2017 Postmates. All rights reserved.
//

import XCTest
import PMHTTP

final class AuthTests: PMHTTPTestCase {
    func testNoAuth() {
        expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
            XCTAssertNil(request.headers["Authorization"], "request authorization header")
            completionHandler(HTTPServer.Response(status: .ok))
        }
        let req = HTTP.request(GET: "foo")!
        XCTAssertNil(req.auth, "request object auth")
        expectationForRequestSuccess(req) { _ in }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testBasicAuth() {
        func basicAuthentication(user: String, password: String) -> String {
            let data = "\(user):\(password)".data(using: String.Encoding.utf8)!
            let encoded = data.base64EncodedString(options: [])
            return "Basic \(encoded)"
        }
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.headers["Authorization"], basicAuthentication(user: "alice", password: "secure"), "request authorization header")
                completionHandler(HTTPServer.Response(status: .ok))
            }
            HTTP.defaultAuth = HTTPBasicAuth(username: "alice", password: "secure")
            let req = HTTP.request(GET: "foo")!
            HTTP.defaultAuth = nil
            if let credential = (req.auth as? HTTPBasicAuth)?.credential {
                XCTAssertEqual(credential.user, "alice", "request object credential user")
                XCTAssertEqual(credential.password, "secure", "request object credential password")
            } else {
                XCTFail("expected HTTPBasicAuth, found \(req.auth) - request object auth")
            }
            expectationForRequestSuccess(req) { _ in }
            waitForExpectations(timeout: 5, handler: nil)
        }
        do {
            expectationForHTTPRequest(httpServer, path: "/foo") { request, completionHandler in
                XCTAssertEqual(request.headers["Authorization"], basicAuthentication(user: "alice", password: "secure"), "request authorization header")
                completionHandler(HTTPServer.Response(status: .unauthorized, headers: ["Content-Type": "application/json"], body: "{ \"error\": \"unauthorized\" }"))
            }
            let req = HTTP.request(GET: "foo")!
            req.auth = HTTPBasicAuth(username: "alice", password: "secure")
            expectationForRequestFailure(req) { task, response, error in
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401, "response status code")
                if case let HTTPManagerError.unauthorized(auth, response_, _, json) = error {
                    XCTAssert(response === response_, "error response")
                    if let credential = (auth as? HTTPBasicAuth)?.credential {
                        XCTAssertEqual(credential.user, "alice", "error credential user")
                        XCTAssertEqual(credential.password, "secure", "error credential password")
                    } else {
                        XCTFail("expected HTTPBasicAuth, found \(auth) - error auth")
                    }
                    XCTAssertEqual(json, ["error": "unauthorized"], "error body json")
                } else {
                    XCTFail("expected HTTPManagerError.unauthorized, found \(error)")
                }
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        do {
            let req = HTTP.request(GET: "http://apple.com/foo")!
            XCTAssertNil(req.auth, "request object auth")
        }
    }
    
    func testRetryAuthInteraction() {
        // 401 Unauthorized can trigger retry behavior if there's no auth, but can't if there is auth
        let alwaysRetryOnce = HTTPManagerRetryBehavior(ignoringIdempotence: { (task, error, attempt, retry) in
            retry(attempt == 0)
        })
        
        // no auth; retry expected
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            XCTAssertNil(request.headers["Authorization"], "request authorization header")
            completionHandler(HTTPServer.Response(status: .unauthorized))
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            XCTAssertNil(request.headers["Authorization"], "request authorization header")
            completionHandler(HTTPServer.Response(status: .ok))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo").with({ $0.retryBehavior = alwaysRetryOnce }))
        waitForExpectations(timeout: 5, handler: nil)
        
        // auth; no retry expected (NB: HTTPBasicAuth never retries)
        let basicAuth = HTTPBasicAuth(username: "anne", password: "bob")
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            XCTAssertNotNil(request.headers["Authorization"], "request authorization header")
            completionHandler(HTTPServer.Response(status: .unauthorized))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo").with({ $0.retryBehavior = alwaysRetryOnce; $0.auth = basicAuth })) { (task, response, error) in
            if case HTTPManagerError.unauthorized(let auth, _, _, _) = error {
                XCTAssert(auth === basicAuth, "expected \(basicAuth), found \(auth) - response auth")
            } else {
                XCTFail("expected HTTPManagerError.unauthorized, found \(error) - response error")
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testOpaqueToken() {
        class Auth: HTTPAuth {
            private class Token {}
            let token = Token()
            let expectation: XCTestExpectation
            init(expectation: XCTestExpectation) {
                self.expectation = expectation
            }
            func headers(for request: URLRequest) -> [String : String] {
                return [:]
            }
            func opaqueToken(for request: URLRequest) -> Any? {
                return token
            }
            func handleUnauthorized(_ response: HTTPURLResponse, body: Data, for task: HTTPManagerTask, token: Any?, completion: @escaping (Bool) -> Void) {
                XCTAssert((token as? Token) === self.token, "expected token, got \(token) - handleUnauthorized")
                completion(false)
                expectation.fulfill()
            }
        }
        
        let auth = Auth(expectation: expectation(description: "handleUnauthorized"))
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .unauthorized))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo").with({ $0.auth = auth })) { (task, response, error) in
            if case HTTPManagerError.unauthorized = error {} else {
                XCTFail("expected HTTPManagerError.unauthorized, found \(error) - response error")
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testAuthRetryOnce() {
        // The auth object is only allowed to retry a given task once.
        class Auth: HTTPAuth {
            // NB: This is safe to access without synchronization because the instance of this class
            // is only used with a single request, so therefore there can't be concurrent access.
            var attempts: Int = 0
            let expectation: XCTestExpectation
            init(expectation: XCTestExpectation) {
                self.expectation = expectation
            }
            func headers(for request: URLRequest) -> [String : String] {
                return [:]
            }
            func handleUnauthorized(_ response: HTTPURLResponse, body: Data, for task: HTTPManagerTask, token: Any?, completion: @escaping (Bool) -> Void) {
                XCTAssertEqual(attempts, 0)
                attempts += 1
                completion(true)
                if attempts == 1 {
                    expectation.fulfill()
                }
            }
        }
        
        let auth = Auth(expectation: expectation(description: "handleUnauthorized"))
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .unauthorized))
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .unauthorized))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo").with({ $0.auth = auth })) { (task, response, error) in
            if case HTTPManagerError.unauthorized = error {} else {
                XCTFail("expected HTTPManagerError.unauthorized, found \(error) - response error")
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testAuthAsyncCompletion() {
        class Auth: HTTPAuth {
            let retry: Bool
            init(retry: Bool) {
                self.retry = retry
            }
            func headers(for request: URLRequest) -> [String : String] {
                return [:]
            }
            func handleUnauthorized(_ response: HTTPURLResponse, body: Data, for task: HTTPManagerTask, token: Any?, completion: @escaping (Bool) -> Void) {
                DispatchQueue.global().async { [retry] in
                    completion(retry)
                }
            }
        }
        
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .unauthorized))
        }
        expectationForRequestFailure(HTTP.request(GET: "foo").with({ $0.auth = Auth(retry: false) })) { (task, response, error) in
            if case HTTPManagerError.unauthorized = error {} else {
                XCTFail("expected HTTPManagerError.unauthorized, found \(error) - response error")
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
        
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .unauthorized))
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            completionHandler(HTTPServer.Response(status: .ok))
        }
        expectationForRequestSuccess(HTTP.request(GET: "foo").with({ $0.auth = Auth(retry: true) }))
        waitForExpectations(timeout: 5, handler: nil)
    }
}
