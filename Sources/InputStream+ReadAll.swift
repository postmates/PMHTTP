//
//  InputStream+ReadAll.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 8/18/17.
//  Copyright © 2017 Postmates. All rights reserved.
//

import Foundation

internal extension InputStream {
    /// An error thrown from `readAll()` if the stream indicates that an error occurred but
    /// `streamError` is `nil`.
    struct UnknownError: Error {}
    
    /// Reads the entire stream and returns the contents as a `Data`.
    ///
    /// - Requires: The stream must be opened before invoking this method.
    ///
    /// - Note: This method automatically calls `close()` on the stream when it's done.
    ///
    /// - Throws: An error if the stream returns an error while reading.
    @nonobjc
    func readAll() throws -> Data {
        defer { close() }
        let cap = 64 * 1024
        var len = 0
        var buf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        var data = DispatchData.empty
        while true {
            switch read(buf, maxLength: cap - len) {
            case 0: // EOF
                if len > 0 {
                    data.append(DispatchData(bytesNoCopy: UnsafeBufferPointer(start: buf, count: len), deallocator: DispatchData.Deallocator.custom(nil, { [buf] in
                        buf.deallocate(capacity: cap)
                    })))
                } else {
                    buf.deallocate(capacity: cap)
                }
                // This is an ugly hack, but DispatchData doesn't have any way to go to Data directly.
                // This relies on the fact that OS_dispatch_data is toll-free bridged to NSData, even though Swift doesn't understand that.
                let nsdata = unsafeDowncast(data as AnyObject, to: NSData.self)
                return Data(referencing: nsdata)
            case let n where n > 0:
                let overflow: Bool
                (len, overflow) = Int.addWithOverflow(len, n)
                guard len <= cap && !overflow else {
                    // The stream claims to have written more bytes than is available. We don't know
                    // how to handle this.
                    buf.deallocate(capacity: cap)
                    throw UnknownError()
                }
                if len == cap {
                    data.append(DispatchData(bytesNoCopy: UnsafeBufferPointer(start: buf, count: len), deallocator: DispatchData.Deallocator.custom(nil, { [buf] in
                        buf.deallocate(capacity: cap)
                    })))
                    buf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
                    len = 0
                }
            default: // -1
                buf.deallocate(capacity: cap)
                throw streamError ?? UnknownError()
            }
        }
    }
}
