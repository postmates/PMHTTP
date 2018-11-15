//
//  URLProtocol.swift
//  PMHTTP
//
//  Created by Lily Ballard on 7/29/18.
//  Copyright © 2018 Lily Ballard.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import class Foundation.URLProtocol

public extension URLProtocol {
    /// Returns the property associated with the specified key in the specified request.
    ///
    /// This method is used to provide an interface for protocol implementors to customize
    /// protocol-specific information associated with `HTTPManagerRequest` objects. Any properties
    /// set by this interface will be applied to the underlying `URLRequest` object used to create
    /// the network task.
    ///
    /// - Parameter key: The key of the desired property.
    /// - Parameter request: The request whose properties are to be queried.
    /// - Returns: The property associated with `key`, or `nil` if no property has been stored for
    ///   `key`.
    @objc(propertyForKey:inHTTPManagerRequest:)
    static func property(forKey key: String, in request: HTTPManagerRequest) -> Any? {
        return request.urlProtocolProperties[key]
    }
    
    /// Sets the property associated with the specified key in the specified request.
    ///
    /// This method is used to provide an interface for protocol implementors to customize
    /// protocol-specific information associated with `HTTPManagerRequest` objects. Any properties
    /// set by this interface will be applied to the underlying `URLRequest` object used to create
    /// the network task.
    ///
    /// - Parameter value: The value to set for the specified property.
    /// - Parameter key: The key for the specified property.
    /// - Parameter request: The request for which to create the property.
    @objc(setProperty:forKey:inHTTPManagerRequest:)
    static func setProperty(_ value: Any, forKey key: String, in request: HTTPManagerRequest) {
        request.urlProtocolProperties[key] = value
    }
    
    /// Removes the property associated with the specified key in the specified request.
    ///
    /// This method is used to provide an interface for protocol implementors to customize
    /// protocol-specific information associated with `HTTPManagerRequest` objects. Any properties
    /// set by this interface will be applied to the underlying `URLRequest` object used to create
    /// the network task.
    ///
    /// - Parameter key: The key whose value should be removed.
    /// - Parameter request: The request from which to remove the property value.
    @objc(removePropertyForKey:inHTTPManagerRequest:)
    static func removeProperty(forKey key: String, in request: HTTPManagerRequest) {
        request.urlProtocolProperties[key] = nil
    }
}
