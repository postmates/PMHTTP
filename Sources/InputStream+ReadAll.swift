//
//  InputStream+ReadAll.swift
//  PMHTTP
//
//  Created by Lily Ballard on 8/18/17.
//  Copyright © 2017 Postmates. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
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
                    data.append(DispatchData(bytesNoCopy: UnsafeRawBufferPointer(start: buf, count: len), deallocator: DispatchData.Deallocator.custom(nil, { [buf] in
                        #if swift(>=4.1)
                        buf.deallocate()
                        #else
                        buf.deallocate(capacity: cap)
                        #endif
                    })))
                } else {
                    #if swift(>=4.1)
                    buf.deallocate()
                    #else
                    buf.deallocate(capacity: cap)
                    #endif
                }
                // This is an ugly hack, but DispatchData doesn't have any way to go to Data directly.
                // This relies on the fact that OS_dispatch_data is toll-free bridged to NSData, even though Swift doesn't understand that.
                let nsdata = unsafeDowncast(data as AnyObject, to: NSData.self)
                return Data(referencing: nsdata)
            case let n where n > 0:
                let overflow: Bool
                (len, overflow) = len.addingReportingOverflow(n)
                guard len <= cap && !overflow else {
                    // The stream claims to have written more bytes than is available. We don't know
                    // how to handle this.
                    #if swift(>=4.1)
                    buf.deallocate()
                    #else
                    buf.deallocate(capacity: cap)
                    #endif
                    throw UnknownError()
                }
                if len == cap {
                    data.append(DispatchData(bytesNoCopy: UnsafeRawBufferPointer(start: buf, count: len), deallocator: DispatchData.Deallocator.custom(nil, { [buf] in
                        #if swift(>=4.1)
                        buf.deallocate()
                        #else
                        buf.deallocate(capacity: cap)
                        #endif
                    })))
                    buf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
                    len = 0
                }
            default: // -1
                #if swift(>=4.1)
                buf.deallocate()
                #else
                buf.deallocate(capacity: cap)
                #endif
                throw streamError ?? UnknownError()
            }
        }
    }
}
