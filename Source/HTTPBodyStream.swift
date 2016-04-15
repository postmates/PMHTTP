//
//  HTTPBodyStream.swift
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 4/14/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

import Foundation
import PMJSON
import PMHTTPPrivate

internal final class HTTPBody {
    /// Returns an `NSInputStream` that produces a multipart/mixed HTTP body.
    /// - Note: Any `.Pending` body part must be evaluated before calling this
    ///   method, and should be waited on to guarantee the value is ready. If
    ///   the body part isn't waited on, the returned stream will have an
    ///   incorrect value for `CFReadStreamHasBytesAvailable(_:)`.
    class func createMultipartMixedStream(boundary: String, parameters: [NSURLQueryItem], bodyParts: [MultipartBodyPart]) -> NSInputStream {
        let body = HTTPBody(boundary: boundary, parameters: parameters, bodyParts: bodyParts)
        var callbacks = CFReadStreamCallBacks()
        callbacks.version = 2
        callbacks.create = { (stream, info) in
            // Bump the retain count and return the new value.
            let body = Unmanaged<HTTPBody>.fromOpaque(COpaquePointer(info)).takeUnretainedValue()
            body.log("create")
            return UnsafeMutablePointer(Unmanaged.passRetained(body).toOpaque())
        }
        callbacks.finalize = { (stream, info) in
            // Decrement the retain count and discard the object.
            let body = Unmanaged<HTTPBody>.fromOpaque(COpaquePointer(info)).takeRetainedValue()
            body.log("finalize")
        }
        callbacks.open = { (stream, error, openComplete, info) in
            // We don't do any work on open.
            #if enableDebugLogging
                let body = Unmanaged<HTTPBody>.fromOpaque(COpaquePointer(info)).takeUnretainedValue()
                body.log("open")
            #endif
            openComplete.memory = true
            // Signal that we already have bytes available.
            _CFReadStreamSignalEventDelayed(stream, .HasBytesAvailable, nil)
            return true
        }
        callbacks.read = { (stream, buffer, bufferLength, errorPtr, atEOF, info) in
            let body = Unmanaged<HTTPBody>.fromOpaque(COpaquePointer(info)).takeUnretainedValue()
            body.log("read ...")
            do {
                let (count, eof) = try body.streamRead(stream, buffer, bufferLength)
                atEOF.memory = DarwinBoolean(eof)
                body.log("... returning \(count) byte(s), atEOF: \(eof)")
                return count
            } catch {
                body.log("... error occurred: \(error)")
                // NB: Can't use `as` to cast from NSError to CFError even though they're toll-free bridged.
                let cferr = unsafeBitCast(error as NSError, CFError.self)
                errorPtr.memory = Unmanaged.passRetained(cferr)
                atEOF.memory = false
                CFReadStreamSignalEvent(stream, .ErrorOccurred, UnsafePointer(Unmanaged.passUnretained(cferr).toOpaque()))
                return 0
            }
        }
        callbacks.canRead = { (stream, errorPtr, info) in
            let body = Unmanaged<HTTPBody>.fromOpaque(COpaquePointer(info)).takeUnretainedValue()
            do {
                let canRead = try body.streamCanRead(stream)
                body.log("canRead: \(canRead)")
                return DarwinBoolean(canRead)
            } catch {
                body.log("canRead; error occurred: \(error)")
                // NB: Can't use `as` to cast from NSError to CFError even though they're toll-free bridged.
                let cferr = unsafeBitCast(error as NSError, CFError.self)
                errorPtr.memory = Unmanaged.passRetained(cferr)
                CFReadStreamSignalEvent(stream, .ErrorOccurred, UnsafePointer(Unmanaged.passUnretained(cferr).toOpaque()))
                return false
            }
        }
        // All non-implemented callbacks are optional.
        
        return CFReadStreamCreate(kCFAllocatorDefault, &callbacks, UnsafeMutablePointer(Unmanaged.passUnretained(body).toOpaque())).takeRetainedValue() as NSInputStream
    }
    
    private let boundary: String
    private var queryItemGenerator: Array<NSURLQueryItem>.Generator?
    private var bodyPartGenerator: Array<MultipartBodyPart>.Generator
    private var deferredPartGenerator: Array<MultipartBodyPart.Data>.Generator?
    private var state: State = .Initial
    
    private enum State {
        case Initial
        /// Header includes the boundary and all header fields and the empty line
        /// terminator. The body part data should be able to be concatenated on the
        /// header in order to form a complete valid body part.
        case Header(String.UTF8View, Content)
        case Data(Content)
        case Terminator(String.UTF8View)
        case EOF
    }
    
    private enum Content {
        case Data(NSData, offset: Int)
        case Text(String.UTF8View)
    }
    
    private init(boundary: String, parameters: [NSURLQueryItem], bodyParts: [MultipartBodyPart]) {
        self.boundary = boundary
        queryItemGenerator = parameters.generate()
        bodyPartGenerator = bodyParts.generate()
        advanceState()
    }
    
    private func streamRead(stream: CFReadStream, _ bufferPtr: UnsafeMutablePointer<UInt8>, _ bufferLength: Int) throws -> (count: Int, atEOF: Bool) {
        guard bufferLength > 0 else {
            // This really shouldn't happen
            struct InvalidStreamReadError: ErrorType {}
            throw InvalidStreamReadError()
        }
        var buffer = UnsafeMutableBufferPointer(start: bufferPtr, count: bufferLength)
        func copyUTF8(inout buffer: UnsafeMutableBufferPointer<UInt8>, utf8: String.UTF8View) -> String.UTF8View.Index? {
            var count = 0
            var ptr = buffer.baseAddress
            defer { buffer = UnsafeMutableBufferPointer(start: ptr, count: buffer.count - count) }
            for idx in utf8.indices {
                if count == buffer.count {
                    return idx
                }
                ptr.initialize(utf8[idx])
                ptr += 1
                count += 1
            }
            return nil
        }
        loop: while !buffer.isEmpty {
            switch state {
            case let .Header(utf8, content):
                if let idx = copyUTF8(&buffer, utf8: utf8) {
                    state = .Header(utf8.suffixFrom(idx), content)
                } else {
                    advanceState()
                }
            case let .Data(.Data(data, offset)):
                let count = min(buffer.count, data.length - offset)
                guard count > 0 else {
                    // we shouldn't hit this
                    break loop
                }
                let end = offset + count
                data.getBytes(UnsafeMutablePointer(buffer.baseAddress), range: NSRange(offset..<end))
                buffer = UnsafeMutableBufferPointer(start: buffer.baseAddress + count, count: buffer.count - count)
                if end >= data.length {
                    advanceState()
                } else {
                    state = .Data(.Data(data, offset: end))
                }
            case .Data(.Text(let utf8)):
                if let idx = copyUTF8(&buffer, utf8: utf8) {
                    state = .Data(.Text(utf8.suffixFrom(idx)))
                } else {
                    advanceState()
                }
            case .Terminator(let utf8):
                if let idx = copyUTF8(&buffer, utf8: utf8) {
                    state = .Terminator(utf8.suffixFrom(idx))
                } else {
                    advanceState()
                }
            case .EOF:
                break loop
            case .Initial:
                fatalError("HTTPManager internal error: unreachable state .Initial in streamRead()")
            }
        }
        let count = buffer.baseAddress - bufferPtr
        switch state {
        case .EOF:
            _CFReadStreamSignalEventDelayed(stream, .EndEncountered, nil)
            return (count, true)
        default:
            _CFReadStreamSignalEventDelayed(stream, .HasBytesAvailable, nil)
            return (count, false)
        }
    }
    
    private func streamCanRead(stream: CFReadStream) throws -> Bool {
        switch state {
        case .EOF: return false
        default: return true
        }
    }
    
    /// Sets `state` to the appropriate state for the next part.
    /// Once the `state` hits `.EOF` it stays there.
    private func advanceState() {
        switch state {
        case .Header(_, let content):
            state = .Data(content)
            // Make sure the content isn't empty. If it is, advance again.
            switch content {
            case let .Data(data, offset) where data.length <= offset: return advanceState()
            case .Text(let utf8) where utf8.isEmpty: return advanceState()
            default: break
            }
        case .Initial, .Data:
            let prefix: String
            if case .Initial = state {
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
                state = .Header(header.utf8, .Text((queryItem.value ?? "").utf8))
            } else {
                queryItemGenerator = nil
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
                            state = .Terminator("\(prefix)--\(boundary)--\r\n".utf8)
                            break loop
                        }
                    }
                    let filename = data.filename.map({ "; filename=\"\(quotedString($0))\"" }) ?? ""
                    let mimeType: String
                    let content: Content
                    switch data.content {
                    case .Data(let data_):
                        content = .Data(data_, offset: 0)
                        mimeType = data.mimeType ?? "application/octet-stream"
                    case .Text(let text):
                        content = .Text(text.utf8)
                        mimeType = data.mimeType ?? "text/plain; charset=utf-8"
                    }
                    let header = prefix
                        + "--\(boundary)\r\n"
                        + "Content-Disposition: form-data; name=\"\(quotedString(data.name))\"\(filename)\r\n"
                        + "Content-Type: \(mimeType)\r\n"
                        + "\r\n"
                    state = .Header(header.utf8, content)
                    break
                }
            }
        case .Terminator:
            state = .EOF
        case .EOF:
            break
        }
    }
    
    #if enableDebugLogging
    func log(msg: String) {
        let ptr = unsafeBitCast(unsafeAddressOf(self), UInt.self)
        NSLog("<HTTPBody: 0x%@> %@", String(ptr, radix: 16), msg)
    }
    #else
    @inline(__always) func log(@autoclosure _: () -> String) {}
    #endif
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
