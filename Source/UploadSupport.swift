//
//  UploadSupport.swift
//  PostmatesNetworking
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

internal enum UploadBody {
    case Data(NSData)
    case FormUrlEncoded([NSURLQueryItem])
    case JSON(PMJSON.JSON)
    /// - Requires: The `boundary` must meet the rules for a valid multipart boundary
    ///   and must not contain any characters that require quoting.
    case MultipartMixed(boundary: String, parameters: [NSURLQueryItem], bodyParts: [MultipartBodyPart])
    
    static func dataRepresentationForQueryItems(queryItems: [NSURLQueryItem]) -> NSData {
        guard !queryItems.isEmpty else {
            return NSData()
        }
        let cs = NSCharacterSet.URLQueryKeyValueAllowedCharacterSet
        func encodeQueryItem(item: NSURLQueryItem) -> String {
            let encodedName = item.name.stringByAddingPercentEncodingWithAllowedCharacters(cs) ?? ""
            if let value = item.value {
                let encodedValue = value.stringByAddingPercentEncodingWithAllowedCharacters(cs) ?? ""
                return "\(encodedName)=\(encodedValue)"
            } else {
                return encodedName
            }
        }
        let encodedQueryItems = queryItems.map(encodeQueryItem)
        let encodedString = encodedQueryItems.joinWithSeparator("&")
        return encodedString.dataUsingEncoding(NSUTF8StringEncoding)!
    }
    
    /// Calls `evaluate()` on every pending multipart body.
    internal func evaluatePending() {
        guard case .MultipartMixed(_, _, let bodies) = self else { return }
        for case .Pending(let deferred) in bodies {
            deferred.evaluate()
        }
    }
}

extension NSCharacterSet {
    private static let URLQueryKeyValueAllowedCharacterSet: NSCharacterSet = {
        let cs: NSMutableCharacterSet = unsafeDowncast(NSCharacterSet.URLQueryAllowedCharacterSet().mutableCopy())
        cs.removeCharactersInString("&=")
        return unsafeDowncast(cs.copy())
    }()
}

internal enum MultipartBodyPart {
    case Known(Data)
    case Pending(Deferred)
    
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
            case Data(NSData)
            case Text(String)
        }
    }
    
    final class Deferred {
        init(_ block: HTTPManagerUploadMultipart -> Void) {
            self.block = block
        }
        
        /// Asynchronously triggers evaluation of the block, if not already evaluated.
        /// This MUST be invoked before calling `wait()`.
        func evaluate() {
            dispatch_barrier_async(queue) {
                guard self.value == nil else { return }
                let helper = HTTPManagerUploadMultipart()
                self.block(helper)
                self.value = helper.multipartData
            }
        }
        
        /// Waits for the block to finish evaluation and returns the `Data` values created as a result.
        /// `evaluate()` MUST be invoked at some point before calling `wait()`. Calling `wait()` without
        /// calling `evaluate()` first is a programmer error and will result in an assertion failure.
        func wait() -> [Data] {
            var value: [Data]?
            dispatch_sync(queue) {
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
        func async(qosClass: dispatch_qos_class_t?, handler: [Data] -> Void) {
            let block: dispatch_block_t = {
                guard let value = self.value else {
                    fatalError("HTTPManager internal error: invoked async() on Deferred without invoking evaluate()")
                }
                handler(value)
            }
            if let qosClass = qosClass {
                dispatch_async(queue, dispatch_block_create_with_qos_class(DISPATCH_BLOCK_ENFORCE_QOS_CLASS, qosClass, 0, block))
            } else {
                dispatch_async(queue, block)
            }
        }
        
        private let queue = dispatch_queue_create("HTTPManager MultipartBodyPart Deferred queue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_UTILITY, 0))
        private var value: [Data]?
        private let block: HTTPManagerUploadMultipart -> Void
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
