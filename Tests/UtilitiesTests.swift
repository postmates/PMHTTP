//
//  UtilitiesTests.swift
//  PMHTTPTests
//
//  Created by Lily Ballard on 6/27/18.
//  Copyright © 2018 Lily Ballard.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import XCTest
@testable import PMHTTP

final class UtilitiesTests: XCTestCase {
    #if !compiler(>=5) // Swift 5 got rid of the preprocessing pass that caused double-evaluation
    func testSequenceMultiPass() {
        // This test validates that we can detect multi-pass evaluations on `lazy`.
        // This is so we can have confidence in the test against `lazySequence`.
        let expectations = (0..<5).map({ i -> XCTestExpectation in
            let expectation = XCTestExpectation(description: "element \(i)")
            expectation.expectedFulfillmentCount = 2
            expectation.assertForOverFulfill = false // 3 passes instead of 2 makes no difference for our test
            return expectation
        })
        let s = expectations.lazy.map({ expectation -> String in
            expectation.fulfill()
            return "x"
        }).joined(separator: "")
        XCTAssertEqual(s, "xxxxx")
        wait(for: expectations, timeout: 0)
    }
    #endif
    
    func testLazySequence() {
        let expectations = (0..<5).map({ i -> XCTestExpectation in
            let expectation = XCTestExpectation(description: "element \(i)")
            expectation.expectedFulfillmentCount = 1
            expectation.assertForOverFulfill = true
            return expectation
        })
        let s = expectations.lazySequence.map({ expectation -> String in
            expectation.fulfill()
            return "x"
        }).joined(separator: "")
        XCTAssertEqual(s, "xxxxx")
        wait(for: expectations, timeout: 0)
    }
}
