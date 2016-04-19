//
//  MultipartTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 4/14/16.
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

class MultipartTests: PMHTTPTestCase {
    func testOneTextPart() {
        HTTPServer.enableDebugLogging = true
        defer { HTTPServer.enableDebugLogging = false }
        let req = HTTP.request(POST: "foo")
        req.addMultipartText("Hello world", withName: "message")
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            defer { completionHandler(HTTPServer.Response(status: .OK)) }
            let multipartBody: HTTPServer.MultipartBody
            do {
                multipartBody = try request.parseMultipartBody()
            } catch {
                return XCTFail("no multipart body; error: \(error)")
            }
            XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
            guard let bodyPart = multipartBody.parts.first else {
                return XCTFail("no multipart body parts")
            }
            XCTAssertEqual(multipartBody.parts.count, 1, "multipart body part count")
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"message\""), "multipart body part 0 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 0 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Hello world", "multipart body part 0 content")
        }
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testOneDataPart() {
        do {
            let req = HTTP.request(POST: "foo")
            req.addMultipartData("Hello world".dataUsingEncoding(NSUTF8StringEncoding)!, withName: "greeting")
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                defer { completionHandler(HTTPServer.Response(status: .OK)) }
                let multipartBody: HTTPServer.MultipartBody
                do {
                    multipartBody = try request.parseMultipartBody()
                } catch {
                    return XCTFail("no multipart body; error: \(error)")
                }
                XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
                guard let bodyPart = multipartBody.parts.first else {
                    return XCTFail("no multipart body parts")
                }
                XCTAssertEqual(multipartBody.parts.count, 1, "multipart body part count")
                XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"greeting\""), "multipart body part 0 Content-Disposition")
                XCTAssertEqual(bodyPart.contentType, MediaType("application/octet-stream"), "multipart body part 0 Content-Type")
                XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Hello world", "multipart body part 0 content")
            }
            expectationForRequestSuccess(req) { (task, response, value) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            let req = HTTP.request(POST: "foo")
            req.addMultipartData("Hello world".dataUsingEncoding(NSUTF8StringEncoding)!, withName: "hi", mimeType: "text/x-foo")
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                defer { completionHandler(HTTPServer.Response(status: .OK)) }
                let multipartBody: HTTPServer.MultipartBody
                do {
                    multipartBody = try request.parseMultipartBody()
                } catch {
                    return XCTFail("no multipart body; error: \(error)")
                }
                XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
                guard let bodyPart = multipartBody.parts.first else {
                    return XCTFail("no multipart body parts")
                }
                XCTAssertEqual(multipartBody.parts.count, 1, "multipart body part count")
                XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"hi\""), "multipart body part 0 Content-Disposition")
                XCTAssertEqual(bodyPart.contentType, MediaType("text/x-foo"), "multipart body part 0 Content-Type")
                XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Hello world", "multipart body part 0 content")
            }
            expectationForRequestSuccess(req) { (task, response, value) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            let req = HTTP.request(POST: "foo")
            req.addMultipartData("Goodbye world".dataUsingEncoding(NSUTF8StringEncoding)!, withName: "file", filename: "message.txt")
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                defer { completionHandler(HTTPServer.Response(status: .OK)) }
                let multipartBody: HTTPServer.MultipartBody
                do {
                    multipartBody = try request.parseMultipartBody()
                } catch {
                    return XCTFail("no multipart body; error: \(error)")
                }
                XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
                guard let bodyPart = multipartBody.parts.first else {
                    return XCTFail("no multipart body parts")
                }
                XCTAssertEqual(multipartBody.parts.count, 1, "multipart body part count")
                XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"file\"; filename=\"message.txt\""), "multipart body part 0 Content-Disposition")
                XCTAssertEqual(bodyPart.contentType, MediaType("application/octet-stream"), "multipart body part 0 Content-Type")
                XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Goodbye world", "multipart body part 0 content")
            }
            expectationForRequestSuccess(req) { (task, response, value) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
        
        do {
            let req = HTTP.request(POST: "foo")
            req.addMultipartData("What's up, world?".dataUsingEncoding(NSUTF8StringEncoding)!, withName: "file", mimeType: "text/x-bar", filename: "message.txt")
            expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
                defer { completionHandler(HTTPServer.Response(status: .OK)) }
                let multipartBody: HTTPServer.MultipartBody
                do {
                    multipartBody = try request.parseMultipartBody()
                } catch {
                    return XCTFail("no multipart body; error: \(error)")
                }
                XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
                guard let bodyPart = multipartBody.parts.first else {
                    return XCTFail("no multipart body parts")
                }
                XCTAssertEqual(multipartBody.parts.count, 1, "multipart body part count")
                XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"file\"; filename=\"message.txt\""), "multipart body part 0 Content-Disposition")
                XCTAssertEqual(bodyPart.contentType, MediaType("text/x-bar"), "multipart body part 0 Content-Type")
                XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "What's up, world?", "multipart body part 0 content")
            }
            expectationForRequestSuccess(req) { (task, response, value) in
                XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
            }
            waitForExpectationsWithTimeout(5, handler: nil)
        }
    }
    
    func testMultipleBodyParts() {
        let req = HTTP.request(POST: "foo")
        req.addMultipartText("The first part", withName: "preamble")
        req.addMultipartData("The second part".dataUsingEncoding(NSUTF8StringEncoding)!, withName: "middle")
        req.addMultipartText("The last part", withName: "postlude")
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            defer { completionHandler(HTTPServer.Response(status: .OK)) }
            let multipartBody: HTTPServer.MultipartBody
            do {
                multipartBody = try request.parseMultipartBody()
            } catch {
                return XCTFail("no multipart body; error: \(error)")
            }
            XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
            guard multipartBody.parts.count == 3 else {
                return XCTFail("expected 3 multipart body parts, found \(multipartBody.parts.count)")
            }
            var bodyPart = multipartBody.parts[0]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"preamble\""), "multipart body part 0 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 0 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "The first part", "multipart body part 0 content")
            bodyPart = multipartBody.parts[1]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"middle\""), "multipart body part 1 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("application/octet-stream"), "multipart body part 1 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "The second part", "multipart body part 1 content")
            bodyPart = multipartBody.parts[2]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"postlude\""), "multipart body part 2 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 2 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "The last part", "multipart body part 2 content")
        }
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testParametersAndBodyParts() {
        // NB: Use NSURLQueryItem for parameters so we know what the order is.
        let req = HTTP.request(POST: "foo", parameters: [NSURLQueryItem(name: "message", value: "Hello world"), NSURLQueryItem(name: "foo", value: "bar")])
        req.addMultipartText("Who put the bomp in the bomp, ba bomp, ba bomp?", withName: "question")
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            defer { completionHandler(HTTPServer.Response(status: .OK)) }
            let multipartBody: HTTPServer.MultipartBody
            do {
                multipartBody = try request.parseMultipartBody()
            } catch {
                return XCTFail("no multipart body; error: \(error)")
            }
            XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
            guard multipartBody.parts.count == 3 else {
                return XCTFail("expected 3 multipart body parts, found \(multipartBody.parts.count)")
            }
            var bodyPart = multipartBody.parts[0]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"message\""), "multipart body part 0 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 0 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Hello world", "multipart body part 0 content")
            bodyPart = multipartBody.parts[1]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"foo\""), "multipart body part 1 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 1 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "bar", "multipart body part 1 content")
            bodyPart = multipartBody.parts[2]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"question\""), "multipart body part 2 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 2 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Who put the bomp in the bomp, ba bomp, ba bomp?", "multipart body part 2 content")
        }
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testDeferredNoBodyParts() {
        let req = HTTP.request(POST: "foo")
        req.addMultipartBodyWithBlock { upload in
            // add nothing
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            defer { completionHandler(HTTPServer.Response(status: .OK)) }
            let multipartBody: HTTPServer.MultipartBody
            do {
                multipartBody = try request.parseMultipartBody()
            } catch {
                return XCTFail("no multipart body; error: \(error)")
            }
            XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
            guard multipartBody.parts.count == 0 else {
                return XCTFail("expected 0 multipart body parts, found \(multipartBody.parts.count)")
            }
        }
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testDeferredBodyParts() {
        let req = HTTP.request(POST: "foo")
        req.addMultipartBodyWithBlock { upload in
            upload.addMultipartText("Hello world", withName: "message")
            upload.addMultipartData("One".dataUsingEncoding(NSUTF8StringEncoding)!, withName: "one")
            upload.addMultipartData("Two".dataUsingEncoding(NSUTF8StringEncoding)!, withName: "two", mimeType: "text/plain", filename: "file.txt")
        }
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            defer { completionHandler(HTTPServer.Response(status: .OK)) }
            let multipartBody: HTTPServer.MultipartBody
            do {
                multipartBody = try request.parseMultipartBody()
            } catch {
                return XCTFail("no multipart body; error: \(error)")
            }
            XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
            guard multipartBody.parts.count == 3 else {
                return XCTFail("expected 3 multipart body parts, found \(multipartBody.parts.count)")
            }
            var bodyPart = multipartBody.parts[0]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"message\""), "multipart body part 0 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 0 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Hello world", "multipart body part 0 content")
            bodyPart = multipartBody.parts[1]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"one\""), "multipart body part 1 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("application/octet-stream"), "multipart body part 1 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "One", "multipart body part 1 content")
            bodyPart = multipartBody.parts[2]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"two\"; filename=\"file.txt\""), "multipart body part 2 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain"), "multipart body part 2 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Two", "multipart body part 2 content")
        }
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testMixedEagerAndDeferredBodyParts() {
        let req = HTTP.request(POST: "foo")
        req.addMultipartText("Hello world", withName: "first")
        req.addMultipartBodyWithBlock { upload in
            upload.addMultipartText("Lazy data", withName: "second")
            upload.addMultipartText("Pretend this is useful data", withName: "third")
        }
        req.addMultipartText("The end of all things", withName: "fourth")
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            defer { completionHandler(HTTPServer.Response(status: .OK)) }
            let multipartBody: HTTPServer.MultipartBody
            do {
                multipartBody = try request.parseMultipartBody()
            } catch {
                return XCTFail("no multipart body; error: \(error)")
            }
            XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
            guard multipartBody.parts.count == 4 else {
                return XCTFail("expected 4 multipart body parts, found \(multipartBody.parts.count)")
            }
            var bodyPart = multipartBody.parts[0]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"first\""), "multipart body part 0 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 0 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Hello world", "multipart body part 0 content")
            bodyPart = multipartBody.parts[1]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"second\""), "multipart body part 1 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 1 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Lazy data", "multipart body part 1 content")
            bodyPart = multipartBody.parts[2]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"third\""), "multipart body part 2 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 2 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Pretend this is useful data", "multipart body part 2 content")
            bodyPart = multipartBody.parts[3]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"fourth\""), "multipart body part 3 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 3 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "The end of all things", "multipart body part 3 content")
        }
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testEmptyBodyPart() {
        let req = HTTP.request(POST: "foo")
        req.addMultipartText("", withName: "")
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            defer { completionHandler(HTTPServer.Response(status: .OK)) }
            let multipartBody: HTTPServer.MultipartBody
            do {
                multipartBody = try request.parseMultipartBody()
            } catch {
                return XCTFail("no multipart body; error: \(error)")
            }
            XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
            guard let bodyPart = multipartBody.parts.first else {
                return XCTFail("no multipart body parts")
            }
            XCTAssertEqual(multipartBody.parts.count, 1, "multipart body part count")
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"\""), "multipart body part 0 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 0 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "", "multipart body part 0 content")
        }
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
    
    func testHugeBodyPart() {
        // Let's shove 4MB of data across the wire (note: HTTPServer only allows 5MB total).
        let data = NSMutableData(length: 4 * 1024 * 1024)!
        // Fill it with something other than all zeroes.
        let bytes = UnsafeMutablePointer<UInt8>(data.mutableBytes)
        for i in 0..<data.length {
            // Pick some prime number just to make sure our repeating pattern doesn't ever line up with anything
            bytes[i] = UInt8(truncatingBitPattern: i % 23)
        }
        let req = HTTP.request(POST: "foo")
        req.addMultipartText("Hello world", withName: "message")
        req.addMultipartData(data, withName: "binary")
        expectationForHTTPRequest(httpServer, path: "/foo") { (request, completionHandler) in
            defer { completionHandler(HTTPServer.Response(status: .OK)) }
            let multipartBody: HTTPServer.MultipartBody
            do {
                multipartBody = try request.parseMultipartBody()
            } catch {
                return XCTFail("no multipart body; error: \(error)")
            }
            XCTAssertEqual(multipartBody.contentType, "multipart/form-data", "multipart content type")
            guard multipartBody.parts.count == 2 else {
                return XCTFail("expected 2 multipart body parts, found \(multipartBody.parts.count)")
            }
            var bodyPart = multipartBody.parts[0]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"message\""), "multipart body part 0 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("text/plain; charset=utf-8"), "multipart body part 0 Content-Type")
            XCTAssertEqual(String(data: bodyPart.body, encoding: NSUTF8StringEncoding), "Hello world", "multipart body part 0 content")
            bodyPart = multipartBody.parts[1]
            XCTAssertEqual(bodyPart.contentDisposition, HTTPServer.ContentDisposition("form-data; name=\"binary\""), "multipart body part 1 Content-Disposition")
            XCTAssertEqual(bodyPart.contentType, MediaType("application/octet-stream"), "multipart body part 1 Content-Type")
            XCTAssertEqual(bodyPart.body, data, "multipart body part 1 content")
        }
        expectationForRequestSuccess(req) { (task, response, value) in
            XCTAssertEqual((response as? NSHTTPURLResponse)?.statusCode, 200, "status code")
        }
        waitForExpectationsWithTimeout(5, handler: nil)
    }
}
