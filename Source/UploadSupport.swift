//
//  UploadSupport.swift
//  PMAPI
//
//  Created by Kevin Ballard on 1/5/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

import Foundation

internal enum UploadBody {
    case Data(NSData)
    case FormUrlEncoded([NSURLQueryItem])
    case MultipartMixed([NSURLQueryItem], [MultipartBodyPart])
    
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
        guard case .MultipartMixed(_, let bodies) = self else { return }
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
        
        /// Data for the headers, including the terminating empty line.
        lazy var headerData: NSData = {
            var headers: String = ""
            headers += "Content-Disposition: form-data;name=\"\(self.name)\""
            if let filename = self.filename {
                headers += ";filename=\"\(filename)\""
            }
            headers += "\r\n"
            headers += "Content-Type: \(self.mimeType ?? "text-plain;charset=utf-8")\r\n"
            headers += "\r\n"
            return headers.dataUsingEncoding(NSUTF8StringEncoding)!
        }()
        
        enum Content {
            case Data(NSData)
            case Text(String)
            
            /// Returns the length of the content, in bytes.
            func contentLength() -> Int64 {
                switch self {
                case .Data(let data): return Int64(data.length)
                case .Text(let str): return Int64(str.lengthOfBytesUsingEncoding(NSUTF8StringEncoding))
                }
            }
        }
        
        /// Returns the length of the content, in bytes.
        /// Does not include the boundary.
        mutating func contentLength() -> Int64 {
            return Int64(headerData.length) + content.contentLength()
        }
    }
    
    final class Deferred {
        init(_ block: APIManagerUploadMultipart -> Void) {
            self.block = block
        }
        
        /// Asynchronously triggers evaluation of the block, if not already evaluated.
        /// This MUST be invoked before calling `wait()`.
        func evaluate() {
            dispatch_barrier_async(queue) {
                guard self.value == nil else { return }
                let helper = APIManagerUploadMultipart()
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
                fatalError("APIManager error: invoked wait() on Deferred without invoking evaluate()")
            }
            return value_
        }
        
        private let queue = dispatch_queue_create("APIManager MultipartBodyPart Deferred queue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_UTILITY, 0))
        private var value: [Data]?
        private let block: APIManagerUploadMultipart -> Void
    }
    
    /// Returns the length of the body part, in bytes, or `nil` if no length is known.
    mutating func contentLength() -> Int64? {
        switch self {
        case .Known(var data):
            defer { self = .Known(data) }
            return data.contentLength()
        case .Pending:
            return nil
        }
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
