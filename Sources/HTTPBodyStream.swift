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
import PMHTTP.Private

internal final class HTTPBody {
    /// Returns an `NSInputStream` that produces a multipart/mixed HTTP body.
    /// - Note: Any `.pending` body part must be evaluated before calling this
    ///   method, and should be waited on to guarantee the value is ready.
    class func createMultipartMixedStream(_ boundary: String, parameters: [URLQueryItem], bodyParts: [MultipartBodyPart]) -> InputStream {
        let body = HTTPBody(boundary: boundary, parameters: parameters, bodyParts: bodyParts)
        return _PMHTTPManagerBodyStream(handler: { (buffer, maxLength) -> Int in
            return body.readIntoBuffer(buffer, maxLength)
        })
    }
    
    private let boundary: String
    private var queryItemGenerator: Array<URLQueryItem>.Iterator?
    private var bodyPartGenerator: Array<MultipartBodyPart>.Iterator
    private var deferredPartGenerator: Array<MultipartBodyPart.Data>.Iterator?
    private var state: State = .initial
    
    private enum State {
        case initial
        /// Header includes the boundary and all header fields and the empty line
        /// terminator. The body part data should be able to be concatenated on the
        /// header in order to form a complete valid body part.
        case header(String.UTF8View, Content)
        case data(Content)
        case terminator(String.UTF8View)
        case eof
    }
    
    private enum Content {
        case data(Data, offset: Int)
        case text(String.UTF8View)
    }
    
    private init(boundary: String, parameters: [URLQueryItem], bodyParts: [MultipartBodyPart]) {
        self.boundary = boundary
        queryItemGenerator = parameters.makeIterator()
        bodyPartGenerator = bodyParts.makeIterator()
        advanceState()
    }
    
    private func readIntoBuffer(_ bufferPtr: UnsafeMutablePointer<UInt8>, _ bufferLength: Int) -> Int {
        var buffer = UnsafeMutableBufferPointer(start: bufferPtr, count: bufferLength)
        func copyUTF8(_ buffer: inout UnsafeMutableBufferPointer<UInt8>, utf8: String.UTF8View) -> String.UTF8View.Index? {
            var count = 0
            var ptr = buffer.baseAddress!
            defer { buffer = UnsafeMutableBufferPointer(start: ptr, count: buffer.count - count) }
            for idx in utf8.indices {
                if count == buffer.count {
                    return idx
                }
                ptr.initialize(to: utf8[idx])
                ptr += 1
                count += 1
            }
            return nil
        }
        loop: while !buffer.isEmpty {
            switch state {
            case let .header(utf8, content):
                if let idx = copyUTF8(&buffer, utf8: utf8) {
                    state = .header(utf8.suffix(from: idx), content)
                } else {
                    advanceState()
                }
            case let .data(.data(data, offset)):
                let count = min(buffer.count, data.count - offset)
                guard count > 0 else {
                    // we shouldn't hit this
                    break loop
                }
                let end = offset + count
                data.copyBytes(to: buffer.baseAddress!, from: offset..<end)
                buffer = UnsafeMutableBufferPointer(start: buffer.baseAddress! + count, count: buffer.count - count)
                if end >= data.count {
                    advanceState()
                } else {
                    state = .data(.data(data, offset: end))
                }
            case .data(.text(let utf8)):
                if let idx = copyUTF8(&buffer, utf8: utf8) {
                    state = .data(.text(utf8.suffix(from: idx)))
                } else {
                    advanceState()
                }
            case .terminator(let utf8):
                if let idx = copyUTF8(&buffer, utf8: utf8) {
                    state = .terminator(utf8.suffix(from: idx))
                } else {
                    advanceState()
                }
            case .eof:
                break loop
            case .initial:
                fatalError("HTTPManager internal error: unreachable state .Initial in streamRead()")
            }
        }
        return buffer.baseAddress! - bufferPtr
    }
    
    /// Sets `state` to the appropriate state for the next part.
    /// Once the `state` hits `.eof` it stays there.
    private func advanceState() {
        switch state {
        case .header(_, let content):
            state = .data(content)
            // Make sure the content isn't empty. If it is, advance again.
            switch content {
            case let .data(data, offset) where data.count <= offset: return advanceState()
            case .text(let utf8) where utf8.isEmpty: return advanceState()
            default: break
            }
        case .initial, .data:
            let prefix: String
            if case .initial = state {
                prefix = "" // no CRLF before the first boundary
            } else {
                prefix = "\r\n"
            }
            if let queryItem = queryItemGenerator?.next() {
                // Parameters are always text/plain.
                // We could probably get away with not specifying Content-Type and allowing the server to infer it,
                // since it should normally infer it as UTF-8, but it's safer to be explicit.
                let header = prefix
                    + "--\(boundary)\r\n"
                    + "Content-Disposition: form-data; name=\"\(quotedString(queryItem.name))\"\r\n"
                    + "Content-Type: text/plain; charset=utf-8\r\n"
                    + "\r\n"
                state = .header(header.utf8, .text((queryItem.value ?? "").utf8))
            } else {
                queryItemGenerator = nil
                loop: while true {
                    let data: MultipartBodyPart.Data
                    if let data_ = deferredPartGenerator?.next() {
                        data = data_
                    } else {
                        deferredPartGenerator = nil
                        switch bodyPartGenerator.next() {
                        case .known(let data_)?:
                            data = data_
                        case .pending(let deferred)?:
                            var gen = deferred.wait().makeIterator()
                            if let data_ = gen.next() {
                                data = data_
                                deferredPartGenerator = gen
                            } else {
                                continue loop
                            }
                        case nil:
                            state = .terminator("\(prefix)--\(boundary)--\r\n".utf8)
                            break loop
                        }
                    }
                    let filename = data.filename.map({ "; filename=\"\(quotedString($0))\"" }) ?? ""
                    let mimeType: String
                    let content: Content
                    switch data.content {
                    case .data(let data_):
                        content = .data(data_, offset: 0)
                        mimeType = data.mimeType ?? "application/octet-stream"
                    case .text(let text):
                        content = .text(text.utf8)
                        mimeType = data.mimeType ?? "text/plain; charset=utf-8"
                    }
                    let header = prefix
                        + "--\(boundary)\r\n"
                        + "Content-Disposition: form-data; name=\"\(quotedString(data.name))\"\(filename)\r\n"
                        + "Content-Type: \(mimeType)\r\n"
                        + "\r\n"
                    state = .header(header.utf8, content)
                    break
                }
            }
        case .terminator:
            state = .eof
        case .eof:
            break
        }
    }
    
    #if enableDebugLogging
    func log(msg: String) {
        let ptr = unsafeBitCast(unsafeAddressOf(self), UInt.self)
        NSLog("<HTTPBody: 0x%@> %@", String(ptr, radix: 16), msg)
    }
    #else
    @inline(__always) func log(_: @autoclosure () -> String) {}
    #endif
}

/// Returns a string with quotes and line breaks escaped.
/// - Note: The returned string is *not* surrounded by quotes.
private func quotedString(_ str: String) -> String {
    // WebKit quotes by using percent escapes.
    // NB: Using UTF-16 here because that's the fastest encoding for String.
    // If we find a character that needs escaping, we switch to working with unicode scalars
    // as that's a collection that's actually mutable (unlike UTF16View).
    if let idx = str.utf16.index(where: { (c: UTF16.CodeUnit) in c == 0xD || c == 0xA || c == 0x22 /* " */ }) {
        // idx lies on a unicode scalar boundary
        let start = idx.samePosition(in: str.unicodeScalars)!
        var result = String(str.unicodeScalars.prefix(upTo: start))
        for c in str.unicodeScalars.suffix(from: start) {
            switch c {
            case "\r": result.append("%0D")
            case "\n": result.append("%0A")
            case "\"": result.append("%22")
            default: result.unicodeScalars.append(c)
            }
        }
        return result
    } else {
        return str
    }
}
