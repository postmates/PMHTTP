//
//  InputStreamTests.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 8/18/17.
//  Copyright © 2017 Postmates. All rights reserved.
//

import XCTest
@testable import PMHTTP

final class InputStreamTests: XCTestCase {
    func readAll(from stream: InputStream) throws -> Data {
        stream.open()
        return try stream.readAll()
    }
    
    func testReadAllFromData() throws {
        func testData(_ data: Data, file: StaticString = #file, line: UInt = #line) throws {
            XCTAssertEqual(try readAll(from: InputStream(data: data)), data, file: file, line: line)
        }
        
        try testData(Data(bytes: [1,2,3]))
        try testData(Data(repeating: 5, count: 1024))
        try testData((1...8).map({ Data(repeating: $0, count: 1024) }).joined())
        try testData((1...64).map({ Data(repeating: $0, count: 1024) }).joined())
        try testData((1...64).map({ Data(repeating: $0, count: 1025) }).joined())
        try testData((1...128).map({ Data(repeating: $0, count: 1024) }).joined())
    }
}

private extension Array where Element == Data {
    func joined() -> Data {
        var result = Data()
        for elt in self {
            result.append(elt)
        }
        return result
    }
}
