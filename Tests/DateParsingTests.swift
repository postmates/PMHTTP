//
//  DateParsingTests.swift
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 3/3/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

import XCTest
import PMHTTP

class DateParsingTests: XCTestCase {
    let calendar: NSCalendar = {
        let calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
        calendar.timeZone = NSTimeZone(forSecondsFromGMT: 0)
        return calendar
    }()
    
    func testRFC1123DateParse() {
        XCTAssertEqual(HTTPManager.parsedDateHeaderFromString("Sun, 06 Nov 1994 08:49:37 GMT"),
            calendar.dateWithEra(1, year: 1994, month: 11, day: 6, hour: 8, minute: 49, second: 37, nanosecond: 0))
        XCTAssertEqual(HTTPManager.parsedDateHeaderFromString("Mon, 29 Feb 2016 15:00:00 GMT"),
            calendar.dateWithEra(1, year: 2016, month: 2, day: 29, hour: 15, minute: 0, second: 0, nanosecond: 0))
    }
    
    func testRFC850DateParse() {
        XCTAssertEqual(HTTPManager.parsedDateHeaderFromString("Sunday, 06-Nov-94 08:49:37 GMT"),
            calendar.dateWithEra(1, year: 1994, month: 11, day: 6, hour: 8, minute: 49, second: 37, nanosecond: 0))
        XCTAssertEqual(HTTPManager.parsedDateHeaderFromString("Monday, 29-Feb-16 15:00:00 GMT"),
            calendar.dateWithEra(1, year: 2016, month: 2, day: 29, hour: 15, minute: 0, second: 0, nanosecond: 0))
    }
    
    func testAsctimeDateParse() {
        XCTAssertEqual(HTTPManager.parsedDateHeaderFromString("Sun Nov  6 08:49:37 1994"),
            calendar.dateWithEra(1, year: 1994, month: 11, day: 6, hour: 8, minute: 49, second: 37, nanosecond: 0))
        XCTAssertEqual(HTTPManager.parsedDateHeaderFromString("Mon FEb 29 15:00:00 2016"),
            calendar.dateWithEra(1, year: 2016, month: 2, day: 29, hour: 15, minute: 0, second: 0, nanosecond: 0))
    }
    
    func testInvalidParse() {
        XCTAssertNil(HTTPManager.parsedDateHeaderFromString(""))
        XCTAssertNil(HTTPManager.parsedDateHeaderFromString("bob's yer uncle"))
        XCTAssertNil(HTTPManager.parsedDateHeaderFromString("2016-01-02 03:04:05"))
        XCTAssertNil(HTTPManager.parsedDateHeaderFromString("1457035967"))
    }
}
