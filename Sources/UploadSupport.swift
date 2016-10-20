//
//  UploadSupport.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 1/5/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Foundation
import PMJSON

/// Implements application/x-www-form-urlencoded encoding.
///
/// See [the spec](https://www.w3.org/TR/html5/forms.html#application/x-www-form-urlencoded-encoding-algorithm) for details.
///
/// - Note: We don't actually translate spaces into `+` because, while HTML says that query strings
///   should be encoded using application/x-www-form-urlencoded (and therefore spaces should be `+`),
///   there's no actual guarantee that servers interpret query strings that way, but all servers are
///   guaranteed to interpret `%20` as a space.
internal enum FormURLEncoded {
    static func string(for queryItems: [URLQueryItem]) -> String {
        guard !queryItems.isEmpty else {
            return ""
        }
        // NB: don't use lazy here, or `joined(separator:)` will map all items twice.
        // Better to have one array allocation than unnecessarily re-encoding all strings.
        let encodedQueryItems = queryItems.map({ item -> String in
            let encodedName = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryKeyAllowedCharacters) ?? ""
            if let value = item.value {
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowedCharacters) ?? ""
                return "\(encodedName)=\(encodedValue)"
            } else {
                return encodedName
            }
        })
        return encodedQueryItems.joined(separator: "&")
    }
    
    static func data(for queryItems: [URLQueryItem]) -> Data {
        return string(for: queryItems).data(using: .utf8) ?? Data()
    }
}

internal enum UploadBody {
    case data(Data)
    case formUrlEncoded([URLQueryItem])
    case json(PMJSON.JSON)
    /// - Requires: The `boundary` must meet the rules for a valid multipart boundary
    ///   and must not contain any characters that require quoting.
    case multipartMixed(boundary: String, parameters: [URLQueryItem], bodyParts: [MultipartBodyPart])
    
    /// Calls `evaluate()` on every pending multipart body.
    internal func evaluatePending() {
        guard case .multipartMixed(_, _, let bodies) = self else { return }
        for case .pending(let deferred) in bodies {
            deferred.evaluate()
        }
    }
}

private extension CharacterSet {
    static let urlQueryKeyAllowedCharacters: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&=+")
        cs.makeImmutable()
        return cs
    }()
    
    static let urlQueryValueAllowedCharacters: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&+")
        cs.makeImmutable()
        return cs
    }()
    
    /// Ensures the wrapped character set is immutable.
    ///
    /// Mutable character sets are less efficient than immutable ones.
    private mutating func makeImmutable() {
        // The only way to ensure this right now is to bridge through Obj-C.
        // There's also no way to test if we're mutable or not due to the _SwiftNativeNS* wrapper.
        self = unsafeDowncast((self as NSCharacterSet).copy() as AnyObject, to: NSCharacterSet.self) as CharacterSet
    }
}

internal enum MultipartBodyPart {
    case known(Data)
    case pending(Deferred)
    
    struct Data {
        let mimeType: String?
        let name: String
        let filename: String?
        let content: Content
        
        init(_ content: Content, name: String, mimeType: String? = nil, filename: String? = nil) {
            self.content = content
            self.name = name
            self.mimeType = mimeType
            self.filename = filename
        }
        
        enum Content {
            case data(Foundation.Data)
            case text(String)
        }
    }
    
    final class Deferred {
        init(_ block: @escaping (HTTPManagerUploadMultipart) -> Void) {
            self.block = block
        }
        
        /// Asynchronously triggers evaluation of the block, if not already evaluated.
        /// This MUST be invoked before calling `wait()`.
        func evaluate() {
            queue.async(flags: .barrier) {
                guard self.value == nil else { return }
                autoreleasepool {
                    let helper = HTTPManagerUploadMultipart()
                    self.block(helper)
                    self.value = helper.multipartData
                }
            }
        }
        
        /// Waits for the block to finish evaluation and returns the `Data` values created as a result.
        /// `evaluate()` MUST be invoked at some point before calling `wait()`. Calling `wait()` without
        /// calling `evaluate()` first is a programmer error and will result in an assertion failure.
        @discardableResult func wait() -> [Data] {
            var value: [Data]?
            queue.sync {
                value = self.value
            }
            guard let value_ = value else {
                fatalError("HTTPManager internal error: invoked wait() on Deferred without invoking evaluate()")
            }
            return value_
        }
        
        /// Asynchronously executes a given block on an private concurrent queue with the evaluated `Data` values.
        /// `evaluate()` MUST be invoked at some point before calling `async()`. Calling `async()` without
        /// calling `evaluate()` first is a programmer error and will result in an assertion failure.
        func async(_ qosClass: DispatchQoS?, handler: @escaping ([Data]) -> Void) {
            let block: () -> () = {
                guard let value = self.value else {
                    fatalError("HTTPManager internal error: invoked async() on Deferred without invoking evaluate()")
                }
                autoreleasepool {
                    handler(value)
                }
            }
            if let qosClass = qosClass {
                queue.async(group: nil, qos: qosClass, flags: .enforceQoS, execute: block)
            } else {
                queue.async(execute: block)
            }
        }
        
        private let queue = DispatchQueue(label: "HTTPManager MultipartBodyPart Deferred queue", qos: .utility, attributes: .concurrent)
        private var value: [Data]?
        private let block: (HTTPManagerUploadMultipart) -> Void
    }
}

private struct Header {
    struct ContentType {
        static let Name: StaticString = "Content-Type"
        struct Value {
            static let TextPlain: StaticString = "text/plain;charset=utf-8"
        }
    }
    struct ContentDisposition {
        static let Name: StaticString = "Content-Disposition"
        static let Value: StaticString = "form-data"
        struct Param {
            static let Name: StaticString = "name"
            static let Filename: StaticString = "filename"
        }
    }
}
