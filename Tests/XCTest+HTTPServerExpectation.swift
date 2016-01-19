//
//  XCTest+HTTPServerExpectation.swift
//  PMAPI
//
//  Created by Kevin Ballard on 1/8/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

import Foundation
import XCTest
@testable import PMAPI // for QueueConfined

extension XCTestCase {
    /// Installs a request handler on the HTTP server and returns an expectation that's fulfilled when the handler is invoked.
    /// The callback is automatically unregistered when the request is hit.
    /// The callback is executed on an arbitrary background queue.
    func expectationForHTTPRequest(server: HTTPServer, path: String, handler: (request: HTTPServer.Request, completionHandler: HTTPServer.Response -> Void) -> Void) -> XCTestExpectation {
        let expectation = self.expectationWithDescription("server request with path \(String(reflecting: path))")
        let lock = NSLock()
        lock.lock()
        var token: HTTPServer.CallbackToken?
        token = server.registerRequestCallbackForPath(path) { [weak self, weak server] request, completionHandler in
            lock.lock()
            let token_ = replace(&token, with: nil)
            lock.unlock()
            guard let token = token_ else {
                // two connections are invoking the callback simultaneously
                completionHandler(nil)
                return
            }
            server?.unregisterRequestCallback(token)
            
            handler(request: request, completionHandler: {
                completionHandler($0)
                self?.removeOutstandingHTTPRequestHandler(token: token)
                expectation.fulfill()
            })
        }
        addOutstandingHTTPRequestHandler(path: path, server: server, token: token!, expectation: expectation)
        lock.unlock()
        return expectation
    }
    
    /// Unregisters any outstanding HTTP request handlers registered with `expectationForHTTPRequest` and returns
    /// the paths. If there are no outstanding HTTP request handlers, returns `[]`.
    ///
    /// This method can only be called from the test thread.
    func clearOutstandingHTTPRequestHandlers() -> [String] {
        guard let confined = objc_getAssociatedObject(self, &kAssocContext) as? QueueConfined<OutstandingHandlersBox> else {
            return []
        }
        return confined.syncBarrier { box in
            let paths = box.value.map({ $0.path })
            for entry in box.value {
                entry.server.unregisterRequestCallback(entry.token)
                entry.expectation.fulfill()
            }
            box.value.removeAll()
            return paths
        }
    }
    
    private typealias OutstandingHandlersBox = Box<[(path: String, server: HTTPServer, token: HTTPServer.CallbackToken, expectation: XCTestExpectation)]>
    
    private var outstandingHTTPRequestHandlerConfined: QueueConfined<OutstandingHandlersBox>? {
        return objc_getAssociatedObject(self, &kAssocContext) as? QueueConfined<OutstandingHandlersBox>
    }
    
    private func addOutstandingHTTPRequestHandler(path path: String, server: HTTPServer, token: HTTPServer.CallbackToken, expectation: XCTestExpectation) {
        if let confined = objc_getAssociatedObject(self, &kAssocContext) as? QueueConfined<OutstandingHandlersBox> {
            confined.asyncBarrier { box in
                box.value.append((path: path, server: server, token: token, expectation: expectation))
            }
        } else {
            let confined = QueueConfined(label: "PMAPITests outstanding request handlers queue", value: Box([(path: path, server: server, token: token, expectation: expectation)]))
            objc_setAssociatedObject(self, &kAssocContext, confined, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    private func removeOutstandingHTTPRequestHandler(token token: HTTPServer.CallbackToken) {
        guard let confined = objc_getAssociatedObject(self, &kAssocContext) as? QueueConfined<OutstandingHandlersBox> else {
            return
        }
        confined.asyncBarrier { box in
            if let idx = box.value.indexOf({ $0.token === token }) {
                box.value.removeAtIndex(idx)
            }
        }
    }
}

private class Box<T> {
    var value: T
    
    init(_ value: T) {
        self.value = value
    }
}

private var kAssocContext: ()?

private func replace<T>(inout a: T, with b: T) -> T {
    var value = b
    swap(&a, &value)
    return value
}
