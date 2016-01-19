//
//  APIObjectiveC.swift
//  PMAPI
//
//  Created by Kevin Ballard on 12/31/15.
//  Copyright © 2015 Postmates. All rights reserved.
//

// obj-c helpers
extension APIManager {
    /// The default `APIManager` instance.
    @objc(defaultManager) public static var __objc_defaultManager: APIManager {
        return API
    }
}

extension APIManagerRequest {
    /// Additional HTTP header fields to pass in the request. Default is `[:]`.
    ///
    /// If not specified, the request will fill in `Accept` and `Accept-Language`
    /// automatically when performing the request.
    ///
    /// - Note: If `self.credential` is non-`nil`, the `Authorization` header will be
    /// ignored. `Content-Type` and `Content-Length` are always ignored.
    @objc(headerFields) public var __objc_headerFields: [String: String] {
        return headerFields.dictionary
    }
    
    /// Adds an HTTP header to the list of header fields.
    ///
    /// - Parameter value: The value for the header field.
    /// - Parameter field: The name of the header field. Header fields are case-insensitive.
    ///
    /// If a value was previously set for the specified *field*, the supplied *value* is appended
    /// to the existing value using the appropriate field delimiter.
    @objc(addValue:forHeaderField:) public func __objc_addValue(value: String, forHeaderField field: String) {
        headerFields.addValue(value, forHeaderField: field)
    }
    
    /// Sets a specified HTTP header field.
    ///
    /// - Parameter value: The value for the header field.
    /// - Parameter field: The name of the header field. Header fields are case-insensitive.
    @objc(setValue:forHeaderField:) public func __objc_setValue(value: String, forHeaderField field: String) {
        headerFields[field] = value
    }
    
    /// Returns a specified HTTP header field, if set.
    ///
    /// - Parameter field: The name of the header field. Header fields are case-insensitive.
    /// - Returns: The value for the header field, or `nil` if no value was set.
    @objc(valueForHeaderField:) public func __objc_valueForHeaderField(field: String) -> String? {
        return headerFields[field]
    }
}
