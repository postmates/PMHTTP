//
//  ObjCTestSupport.swift
//  PMHTTPTests
//
//  Created by Lily Ballard on 3/20/19.
//  Copyright © 2019 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Foundation
import PMHTTP

/// Helpers for Obj-C unit tests.
public class ObjCTestSupport: NSObject {
    @objc public static func createFailedResponseError(withStatusCode statusCode: Int, response: HTTPURLResponse, body: Data, bodyJson: [String: AnyObject]?) -> NSError {
        return HTTPManagerError.failedResponse(statusCode: statusCode, response: response, body: body, bodyJson: bodyJson.map({ try! JSON(ns: $0) })) as NSError
    }
    
    @objc public static func createUnauthorizedError(with auth: HTTPAuth?, response: HTTPURLResponse, body: Data, bodyJson: [String: AnyObject]?) -> NSError {
        return HTTPManagerError.unauthorized(auth: auth, response: response, body: body, bodyJson: bodyJson.map({ try! JSON(ns: $0) })) as NSError
    }
    
    @objc public static func createUnexpectedContentTypeError(withContentType contentType: String, response: HTTPURLResponse, body: Data) -> NSError {
        return HTTPManagerError.unexpectedContentType(contentType: contentType, response: response, body: body) as NSError
    }
    
    @objc public static func createUnexpectedNoContentError(with response: HTTPURLResponse) -> NSError {
        return HTTPManagerError.unexpectedNoContent(response: response) as NSError
    }
    
    @objc public static func createUnexpectedRedirectError(withStatusCode statusCode: Int, location: URL?, response: HTTPURLResponse, body: Data) -> NSError {
        return HTTPManagerError.unexpectedRedirect(statusCode: statusCode, location: location, response: response, body: body) as NSError
    }
}
