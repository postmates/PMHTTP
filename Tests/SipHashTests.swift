//
//  SipHashTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 1/25/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import XCTest
@testable import PMHTTP

class SipHashTests: XCTestCase {
    func testSipHash() {
        // test data taken from https://github.com/veorq/SipHash/blob/master/main.c (public domain)
        // SipHash-2-4 output with
        // k = 00 01 02 ...
        // and
        // in = (empty string)
        // in = 00 (1 byte)
        // in = 00 01 (2 bytes)
        // in = 00 01 02 (3 bytes)
        // ...
        // in = 00 01 02 ... 3e (63 bytes)
        let expected: [UInt64] = [
            0x310e0edd47db6f72, 0xfd67dc93c539f874, 0x5a4fa9d909806c0d, 0x2d7efbd796666785,
            0xb7877127e09427cf, 0x8da699cd64557618, 0xcee3fe586e46c9cb, 0x37d1018bf50002ab,
            0x6224939a79f5f593, 0xb0e4a90bdf82009e, 0xf3b9dd94c5bb5d7a, 0xa7ad6b22462fb3f4,
            0xfbe50e86bc8f1e75, 0x903d84c02756ea14, 0xeef27a8e90ca23f7, 0xe545be4961ca29a1,
            0xdb9bc2577fcc2a3f, 0x9447be2cf5e99a69, 0x9cd38d96f0b3c14b, 0xbd6179a71dc96dbb,
            0x98eea21af25cd6be, 0xc7673b2eb0cbf2d0, 0x883ea3e395675393, 0xc8ce5ccd8c030ca8,
            0x94af49f6c650adb8, 0xeab8858ade92e1bc, 0xf315bb5bb835d817, 0xadcf6b0763612e2f,
            0xa5c91da7acaa4dde, 0x716595876650a2a6, 0x28ef495c53a387ad, 0x42c341d8fa92d832,
            0xce7cf2722f512771, 0xe37859f94623f3a7, 0x381205bb1ab0e012, 0xae97a10fd434e015,
            0xb4a31508beff4d31, 0x81396229f0907902, 0x4d0cf49ee5d4dcca, 0x5c73336a76d8bf9a,
            0xd0a704536ba93e0e, 0x925958fcd6420cad, 0xa915c29bc8067318, 0x952b79f3bc0aa6d4,
            0xf21df2e41d4535f9, 0x87577519048f53a9, 0x10a56cf5dfcd9adb, 0xeb75095ccd986cd0,
            0x51a9cb9ecba312e6, 0x96afadfc2ce666c7, 0x72fe52975a4364ee, 0x5a1645b276d592a1,
            0xb274cb8ebf87870a, 0x6f9bb4203de7b381, 0xeaecb2a30b22a87f, 0x9924a43cc1315724,
            0xbd838d3aafbf8db7, 0x0b1a2a3265d51aea, 0x135079a3231ce660, 0x932b2846e4d70666,
            0xe1915f5cb1eca46c, 0xf325965ca16d629f, 0x575ff28e60381be5, 0x724506eb4c328a95
            ].map({UInt64(bigEndian: $0)})
        let key: (UInt64, UInt64) = (0x0706050403020100, 0x0f0e0d0c0b0a0908)
        var buf = ContiguousArray<UInt8>(repeating: 0, count: 64)
        for i in 0..<buf.count {
            buf[i] = UInt8(i)
        }
        for (i, exp) in expected.enumerated() {
            var hasher = SipHasher(key: key)
            // hash as a single write
            do {
                hasher.write(buf[0..<i])
                let result = hasher.finish()
                XCTAssert(result == exp, "input of length \(i): 0x\(String(result, radix: 16)) is not equal to 0x\(String(exp, radix:16))")
            }
            // hash as two writes
            do {
                hasher.write(buf[0..<(i/2)])
                hasher.write(buf[(i/2)..<i])
                let result = hasher.finish()
                XCTAssert(result == exp, "input of length \(i): 0x\(String(result, radix: 16)) is not equal to 0x\(String(exp, radix:16))")
            }
            // hash as one write per byte
            do {
                for j in 0..<i {
                    hasher.write(buf[j])
                }
                let result = hasher.finish()
                XCTAssert(result == exp, "input of length \(i): 0x\(String(result, radix: 16)) is not equal to 0x\(String(exp, radix:16))")
            }
        }
    }
}
