//
//  ImageTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 1/17/17.
//  Copyright © 2017 Postmates. All rights reserved.
//

import XCTest
import PMHTTP

#if os(iOS) || os(watchOS) || os(tvOS)
    class ImageTests: PMHTTPTestCase {
        lazy var sampleImage: UIImage = {
            let size = CGSize(width: 50, height: 100)
            UIGraphicsBeginImageContext(size)
            defer { UIGraphicsEndImageContext() }
            UIColor.blue.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            return UIGraphicsGetImageFromCurrentImageContext()!
        }()
        
        func testGETImage() {
            guard let imageData = UIImageJPEGRepresentation(sampleImage, 0.9) else {
                return XCTFail("Could not get JPEG data for sample image")
            }
            expectationForHTTPRequest(httpServer, path: "image") { (request, completion) in
                completion(HTTPServer.Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: imageData))
            }
            expectationForRequestSuccess(HTTP.request(GET: "image").parseAsImage()) { [sampleImage] (task, response, image) in
                // We can't really compare the two images directly, but we can make sure the size is correct
                XCTAssertEqual(image.size, sampleImage.size, "image size")
                XCTAssertEqual(image.scale, 1, "image scale")
            }
            waitForExpectations(timeout: 5, handler: nil)
            
            // With scale
            expectationForHTTPRequest(httpServer, path: "image") { (request, completion) in
                completion(HTTPServer.Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: imageData))
            }
            expectationForRequestSuccess(HTTP.request(GET: "image").parseAsImage(scale: 2)) { (task, response, image) in
                XCTAssertEqual(image.scale, 2, "image scale")
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        func testGETImageNoContent() {
            expectationForHTTPRequest(httpServer, path: "image") { (request, completion) in
                completion(HTTPServer.Response(status: .noContent))
            }
            expectationForRequestFailure(HTTP.request(GET: "image").parseAsImage()) { (task, response, error) in
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204, "response status code")
                switch error {
                case HTTPManagerError.unexpectedNoContent: break
                default: XCTFail("expected error .unexpectedNoContent, found \(error)")
                }
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        func testGETImageBadDecode() {
            expectationForHTTPRequest(httpServer, path: "image") { (request, completion) in
                completion(HTTPServer.Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: Data([1,2,3])))
            }
            expectationForRequestFailure(HTTP.request(GET: "image").parseAsImage()) { (task, response, error) in
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "response status code")
                switch error {
                case HTTPManagerImageError.cannotDecode: break
                default: XCTFail("expected error .cannotDecode, found \(error)")
                }
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        func testGETImageBadMIMEType() {
            expectationForHTTPRequest(httpServer, path: "image") { (request, completion) in
                completion(HTTPServer.Response(status: .ok, headers: ["Content-Type": "application/json"], text: "{ \"ok\": true }"))
            }
            expectationForRequestFailure(HTTP.request(GET: "image").parseAsImage()) { (task, response, error) in
                switch error {
                case HTTPManagerError.unexpectedContentType: break
                default: XCTFail("expected error .unexpectedContentType: found \(error)")
                }
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        func testPOSTImage() {
            guard let imageData = UIImageJPEGRepresentation(sampleImage, 0.9) else {
                return XCTFail("Could not get JPEG data for sample image")
            }
            expectationForHTTPRequest(httpServer, path: "image") { (request, completion) in
                completion(HTTPServer.Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: imageData))
            }
            expectationForRequestSuccess(HTTP.request(POST: "image").parseAsImage()) { [sampleImage] (task, response, image) in
                guard let image = image else {
                    return XCTFail("expected image, got nil")
                }
                // We can't really compare the two images directly, but we can make sure the size is correct
                XCTAssertEqual(image.size, sampleImage.size, "image size")
                XCTAssertEqual(image.scale, 1, "image scale")
            }
            waitForExpectations(timeout: 5, handler: nil)
            
            // With scale
            expectationForHTTPRequest(httpServer, path: "image") { (request, completion) in
                completion(HTTPServer.Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: imageData))
            }
            expectationForRequestSuccess(HTTP.request(POST: "image").parseAsImage(scale: 2)) { (task, response, image) in
                guard let image = image else {
                    return XCTFail("expected image, got nil")
                }
                XCTAssertEqual(image.scale, 2, "image scale")
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        func testPOSTImageNoContent() {
            expectationForHTTPRequest(httpServer, path: "image") { (request, completion) in
                completion(HTTPServer.Response(status: .noContent))
            }
            expectationForRequestSuccess(HTTP.request(POST: "image").parseAsImage()) { (task, response, image) in
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204, "response status code")
                XCTAssertNil(image, "image")
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        func testPOSTImageBadDecode() {
            expectationForHTTPRequest(httpServer, path: "image") { (request, completion) in
                completion(HTTPServer.Response(status: .ok, headers: ["Content-Type": "image/jpeg"], body: Data([1,2,3])))
            }
            expectationForRequestFailure(HTTP.request(POST: "image").parseAsImage()) { (task, response, error) in
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "response status code")
                switch error {
                case HTTPManagerImageError.cannotDecode: break
                default: XCTFail("expected error .cannotDecode, found \(error)")
                }
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
        
        func testPOSTImageBadMIMEType() {
            expectationForHTTPRequest(httpServer, path: "image") { (request, completion) in
                completion(HTTPServer.Response(status: .ok, headers: ["Content-Type": "application/json"], text: "{ \"ok\": true }"))
            }
            expectationForRequestFailure(HTTP.request(POST: "image").parseAsImage()) { (task, response, error) in
                switch error {
                case HTTPManagerError.unexpectedContentType: break
                default: XCTFail("expected error .unexpectedContentType: found \(error)")
                }
            }
            waitForExpectations(timeout: 5, handler: nil)
        }
    }
#endif
