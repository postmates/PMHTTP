//
//  HTTPBodyStream.swift
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

import Foundation
import PMJSON

internal final class HTTPBody {
    /// Returns an `NSInputStream` that produces a multipart/mixed HTTP body.
    /// - Note: Any `.Pending` body part must be evaluated before calling this
    ///   method, and should be waited on to guarantee the value is ready. If
    ///   the body part isn't waited on, the returned stream will have an
    ///   incorrect value for `CFReadStreamHasBytesAvailable(_:)`.
    /// - Bug: Actual streaming support has been disabled, this method creates
    ///   an `NSData` in memory and then creates an `NSInputStream` from it.
    class func createMultipartMixedStream(boundary: String, parameters: [NSURLQueryItem], bodyParts: [MultipartBodyPart]) -> NSInputStream {
        var bodyData = NSMutableData()
        var first = true
        func prefix() -> String {
            if first {
                first = false
                return ""
            } else {
                return "\r\n"
            }
        }
        for queryItem in parameters {
            let header = prefix()
                + "--\(boundary)\r\n"
                + "Content-Disposition: form-data; name=\"\(quotedString(queryItem.name))\"\r\n"
                + "Content-Type: text/plain; charset=utf-8\r\n"
                + "\r\n"
            bodyData.appendData(header.dataUsingEncoding(NSUTF8StringEncoding)!)
            if let value = queryItem.value where !value.isEmpty {
                bodyData.appendData(value.dataUsingEncoding(NSUTF8StringEncoding)!)
            }
        }
        var bodyPartGenerator = bodyParts.generate()
        var deferredPartGenerator: Array<MultipartBodyPart.Data>.Generator?
        loop: while true {
            let data: MultipartBodyPart.Data
            if let data_ = deferredPartGenerator?.next() {
                data = data_
            } else {
                deferredPartGenerator = nil
                switch bodyPartGenerator.next() {
                case .Known(let data_)?:
                    data = data_
                case .Pending(let deferred)?:
                    var gen = deferred.wait().generate()
                    if let data_ = gen.next() {
                        data = data_
                        deferredPartGenerator = gen
                    } else {
                        continue loop
                    }
                case nil:
                    break loop
                }
            }
            let filename = data.filename.map({ "; filename=\"\(quotedString($0))\"" }) ?? ""
            let mimeType: String
            let content: NSData
            switch data.content {
            case .Data(let data_):
                content = data_
                mimeType = data.mimeType ?? "application/octet-stream"
            case .Text(let text):
                content = text.dataUsingEncoding(NSUTF8StringEncoding)!
                mimeType = data.mimeType ?? "text/plain; charset=utf-8"
            }
            let header = prefix()
                + "--\(boundary)\r\n"
                + "Content-Disposition: form-data; name=\"\(quotedString(data.name))\"\(filename)\r\n"
                + "Content-Type: \(mimeType)\r\n"
                + "\r\n"
            bodyData.appendData(header.dataUsingEncoding(NSUTF8StringEncoding)!)
            bodyData.appendData(content)
        }
        bodyData.appendData("\(prefix())--\(boundary)--\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        return NSInputStream(data: bodyData)
    }
}

/// Returns a string with quotes and line breaks escaped.
/// - Note: The returned string is *not* surrounded by quotes.
private func quotedString(str: String) -> String {
    // WebKit quotes by using percent escapes.
    // NB: Using UTF-16 here because that's the fastest encoding for String.
    // If we find a character that needs escaping, we switch to working with unicode scalars
    // as that's a collection that's actually mutable (unlike UTF16View).
    if let idx = str.utf16.indexOf({ (c: UTF16.CodeUnit) in c == 0xD || c == 0xA || c == 0x22 /* " */ }) {
        // idx lies on a unicode scalar boundary
        let start = idx.samePositionIn(str.unicodeScalars)!
        var result = String(str.unicodeScalars.prefixUpTo(start))
        for c in str.unicodeScalars.suffixFrom(start) {
            switch c {
            case "\r": result.appendContentsOf("%0D")
            case "\n": result.appendContentsOf("%0A")
            case "\"": result.appendContentsOf("%22")
            default: result.append(c)
            }
        }
        return result
    } else {
        return str
    }
}
