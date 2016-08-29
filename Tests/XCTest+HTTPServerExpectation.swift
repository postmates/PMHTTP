//
//  XCTest+HTTPServerExpectation.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 1/8/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Foundation
import XCTest
@testable import PMHTTP // for QueueConfined

extension XCTestCase {
    /// Installs a request handler on the HTTP server and returns an expectation that's fulfilled when the handler is invoked.
    /// The callback is automatically unregistered when the request is hit.
    /// The callback is executed on an arbitrary background queue.
    @discardableResult
    func expectationForHTTPRequest(_ server: HTTPServer, path: String, handler: @escaping (_ request: HTTPServer.Request, _ completionHandler: @escaping (HTTPServer.Response) -> Void) -> Void) -> XCTestExpectation {
        let expectation = self.expectation(description: "server request with path \(String(reflecting: path))")
        let lock = NSLock()
        lock.lock()
        var token: HTTPServer.CallbackToken?
        token = server.registerRequestCallback(for: path) { [weak self, weak server, weak expectation] request, completionHandler in
            lock.lock()
            let token_ = replace(&token, with: nil)
            lock.unlock()
            guard let token = token_ else {
                // two connections are invoking the callback simultaneously
                completionHandler(nil)
                return
            }
            server?.unregisterRequestCallback(token)
            
            handler(request, {
                completionHandler($0)
                DispatchQueue.main.async {
                    self?.removeOutstandingHTTPRequestHandler(token: token)
                    expectation?.fulfill()
                }
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
    @discardableResult
    func clearOutstandingHTTPRequestHandlers() -> [String] {
        guard let confined = objc_getAssociatedObject(self, &kAssocContext) as? QueueConfined<OutstandingHandlersBox> else {
            return []
        }
        return confined.syncBarrier { box in
            let paths = box.value.map({ $0.path })
            for entry in box.value {
                entry.server.unregisterRequestCallback(entry.token)
                DispatchQueue.main.async { [expectation=entry.expectation] in
                    expectation.value?.fulfill()
                }
            }
            box.value.removeAll()
            return paths
        }
    }
    
    private typealias OutstandingHandlersBox = Box<[(path: String, server: HTTPServer, token: HTTPServer.CallbackToken, expectation: Weak<XCTestExpectation>)]>
    
    private var outstandingHTTPRequestHandlerConfined: QueueConfined<OutstandingHandlersBox>? {
        return objc_getAssociatedObject(self, &kAssocContext) as? QueueConfined<OutstandingHandlersBox>
    }
    
    private func addOutstandingHTTPRequestHandler(path: String, server: HTTPServer, token: HTTPServer.CallbackToken, expectation: XCTestExpectation) {
        if let confined = objc_getAssociatedObject(self, &kAssocContext) as? QueueConfined<OutstandingHandlersBox> {
            confined.asyncBarrier { box in
                box.value.append((path: path, server: server, token: token, expectation: Weak(expectation)))
            }
        } else {
            let confined = QueueConfined(label: "PMHTTPTests outstanding request handlers queue", value: Box([(path: path, server: server, token: token, expectation: Weak(expectation))]))
            objc_setAssociatedObject(self, &kAssocContext, confined, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    private func removeOutstandingHTTPRequestHandler(token: HTTPServer.CallbackToken) {
        guard let confined = objc_getAssociatedObject(self, &kAssocContext) as? QueueConfined<OutstandingHandlersBox> else {
            return
        }
        confined.asyncBarrier { box in
            if let idx = box.value.index(where: { $0.token === token }) {
                box.value.remove(at: idx)
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

private struct Weak<T: AnyObject> {
    weak var value: T?
    
    init(_ value: T) {
        self.value = value
    }
}

private var kAssocContext: ()?

private func replace<T>(_ a: inout T, with b: T) -> T {
    var value = b
    swap(&a, &value)
    return value
}
