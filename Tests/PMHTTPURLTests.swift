//
//  PMHTTPURLTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 6/26/17.
//  Copyright © 2017 Postmates. All rights reserved.
//

import XCTest
import PMJSON
@testable import PMHTTP

// NB: We're not doing any actual network traffic in these tests because the normal tests already cover that.
// We're just making sure we create the correct request objects.

final class PMHTTPURLTests: XCTestCase {
    override func setUp() {
        super.setUp()
        HTTP.environment = nil
    }
    
    func testSimpleGET() {
        let url = URL(string: "http://apple.com/foo")!
        let req = HTTP.request(GET: url)
        XCTAssertEqual(req.url, url)
    }
    
    func testGETWithParams() {
        let req = HTTP.request(GET: URL(string: "http://apple.com/foo")!, parameters: ["bar": "baz"])
        XCTAssertEqual(req.url.absoluteString, "http://apple.com/foo?bar=baz")
    }
    
    func testRelativeURL() {
        HTTP.environment = HTTPManager.Environment(string: "http://example.com")
        let req = HTTP.request(GET: URL(string: "foo")!)
        XCTAssertEqual(req.url.absoluteString, "http://example.com/foo")
    }
    
    func testSimpleDELETE() {
        let url = URL(string: "http://apple.com/foo")!
        let req = HTTP.request(DELETE: url)
        XCTAssertEqual(req.url, url)
    }
    
    func testDELETEWithParams() {
        let req = HTTP.request(DELETE: URL(string: "http://apple.com/foo")!, parameters: ["bar": "baz"])
        XCTAssertEqual(req.url.absoluteString, "http://apple.com/foo?bar=baz")
    }
    
    func testSimplePOST() {
        let url = URL(string: "http://apple.com/foo")!
        let req = HTTP.request(POST: url)
        XCTAssertEqual(req.url, url)
    }
    
    func testPOSTWithParams() {
        let url = URL(string: "http://apple.com/foo")!
        let req = HTTP.request(POST: url, parameters: ["bar": "baz"])
        XCTAssertEqual(req.url, url)
        XCTAssertEqual(req.parameters, [URLQueryItem(name: "bar", value: "baz")])
    }
    
    func testPOSTWithData() {
        let url = URL(string: "http://apple.com/bar")!
        let req = HTTP.request(POST: url, data: Data())
        XCTAssertEqual(req.url, url)
    }
    
    func testPOSTWithJSON() {
        let url = URL(string: "http://apple.com/bar")!
        let req = HTTP.request(POST: url, json: [:])
        XCTAssertEqual(req.url, url)
    }
    
    func testSimplePUT() {
        let url = URL(string: "http://apple.com/foo")!
        let req = HTTP.request(PUT: url)
        XCTAssertEqual(req.url, url)
    }
    
    func testPUTWithParams() {
        let url = URL(string: "http://apple.com/foo")!
        let req = HTTP.request(PUT: url, parameters: ["bar": "baz"])
        XCTAssertEqual(req.url, url)
        XCTAssertEqual(req.parameters, [URLQueryItem(name: "bar", value: "baz")])
    }
    
    func testPUTWithData() {
        let url = URL(string: "http://apple.com/bar")!
        let req = HTTP.request(PUT: url, data: Data())
        XCTAssertEqual(req.url, url)
    }
    
    func testPUTWithJSON() {
        let url = URL(string: "http://apple.com/bar")!
        let req = HTTP.request(PUT: url, json: [:])
        XCTAssertEqual(req.url, url)
    }
    
    func testSimplePATCH() {
        let url = URL(string: "http://apple.com/foo")!
        let req = HTTP.request(PATCH: url)
        XCTAssertEqual(req.url, url)
    }
    
    func testPATCHWithParams() {
        let url = URL(string: "http://apple.com/foo")!
        let req = HTTP.request(PATCH: url, parameters: ["bar": "baz"])
        XCTAssertEqual(req.url, url)
        XCTAssertEqual(req.parameters, [URLQueryItem(name: "bar", value: "baz")])
    }
    
    func testPATCHWithData() {
        let url = URL(string: "http://apple.com/bar")!
        let req = HTTP.request(PATCH: url, data: Data())
        XCTAssertEqual(req.url, url)
    }
    
    func testPATCHWithJSON() {
        let url = URL(string: "http://apple.com/bar")!
        let req = HTTP.request(PATCH: url, json: [:])
        XCTAssertEqual(req.url, url)
    }
}
