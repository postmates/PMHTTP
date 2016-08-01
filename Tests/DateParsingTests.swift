//
//  DateParsingTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 3/3/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import XCTest
import PMHTTP

class DateParsingTests: XCTestCase {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    
    func testRFC1123DateParse() {
        XCTAssertEqual(HTTPManager.parsedDateHeader(from: "Sun, 06 Nov 1994 08:49:37 GMT"),
                       calendar.date(from: DateComponents(era: 1, year: 1994, month: 11, day: 6, hour: 8, minute: 49, second: 37, nanosecond: 0)))
        XCTAssertEqual(HTTPManager.parsedDateHeader(from: "Mon, 29 Feb 2016 15:00:00 GMT"),
                       calendar.date(from: DateComponents(era: 1, year: 2016, month: 2, day: 29, hour: 15, minute: 0, second: 0, nanosecond: 0)))
    }
    
    func testRFC850DateParse() {
        XCTAssertEqual(HTTPManager.parsedDateHeader(from: "Sunday, 06-Nov-94 08:49:37 GMT"),
                       calendar.date(from: DateComponents(era: 1, year: 1994, month: 11, day: 6, hour: 8, minute: 49, second: 37, nanosecond: 0)))
        XCTAssertEqual(HTTPManager.parsedDateHeader(from: "Monday, 29-Feb-16 15:00:00 GMT"),
                       calendar.date(from: DateComponents(era: 1, year: 2016, month: 2, day: 29, hour: 15, minute: 0, second: 0, nanosecond: 0)))
    }
    
    func testAsctimeDateParse() {
        XCTAssertEqual(HTTPManager.parsedDateHeader(from: "Sun Nov  6 08:49:37 1994"),
                       calendar.date(from: DateComponents(era: 1, year: 1994, month: 11, day: 6, hour: 8, minute: 49, second: 37, nanosecond: 0)))
        XCTAssertEqual(HTTPManager.parsedDateHeader(from: "Mon FEb 29 15:00:00 2016"),
                       calendar.date(from: DateComponents(era: 1, year: 2016, month: 2, day: 29, hour: 15, minute: 0, second: 0, nanosecond: 0)))
    }
    
    func testInvalidParse() {
        XCTAssertNil(HTTPManager.parsedDateHeader(from: ""))
        XCTAssertNil(HTTPManager.parsedDateHeader(from: "bob's yer uncle"))
        XCTAssertNil(HTTPManager.parsedDateHeader(from: "2016-01-02 03:04:05"))
        XCTAssertNil(HTTPManager.parsedDateHeader(from: "1457035967"))
    }
}
