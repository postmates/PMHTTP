//
//  Utilities.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 1/18/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Darwin

#if swift(>=3.2)
    // nop
#else
    internal typealias Substring = String
#endif

/// Returns `true` iff the unicode scalar is a Linear White Space character
/// (as defined by RFC 2616).
internal func isLWS(_ us: UnicodeScalar) -> Bool {
    switch us {
    case " ", "\t": return true
    default: return false
    }
}

/// Trims any Linear White Space (as defined by RFC 2616) from both ends of the `String`.
internal func trimLWS(_ str: String) -> String {
    let scalars = str.unicodeScalars
    let start = scalars.index(where: { !isLWS($0) })
    let end = scalars.reversed().index(where: { !isLWS($0) })?.base
    return String(scalars[(start ?? scalars.startIndex)..<(end ?? scalars.endIndex)])
}

/// A `String` newtype that supports case-insensitive hashing and equality comparisons.
///
/// This type only works properly with ASCII strings. Strings with non-ASCII scalars will compare
/// using string scalar equality, without even taking NFD form into account. This means that
/// `"t\u{E9}st"` and `"te\u{301}st"` compare as non-equal even though the `String` versions
/// will compare as equal.
/// - Note: The `hashValue` of `CaseInsensitiveASCIIString` will not match the `hashValue` of `String`
///   even when the wrapped string is already lowercase.
internal struct CaseInsensitiveASCIIString: Hashable, ExpressibleByStringLiteral, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The wrapped string.
    let string: String
    
    /// Creates a new `CaseInsensitiveASCIIString` that wraps a given string.
    init(_ string: String) {
        self.string = string
    }
    
    init(stringLiteral: String) {
        string = stringLiteral
    }
    
    init(extendedGraphemeClusterLiteral value: String) {
        self.string = value
    }
    
    init(unicodeScalarLiteral value: String) {
        self.string = value
    }
    
    /// A 128-element array of the lowercase codepoint for all ASCII values 0-127.
    fileprivate static let lowercaseTable: ContiguousArray<UInt8> = ContiguousArray(((0 as UInt8)...127).lazy.map({ x in
        if x >= 0x41 && x <= 0x5a { // A-Z
            return x + 0x20
        } else {
            return x
        }
    }))
    
    var hashValue: Int {
        var hasher = SipHasher()
        CaseInsensitiveASCIIString.lowercaseTable.withUnsafeBufferPointer { table in
            for x in string.utf16 {
                if _fastPath(x <= 127) {
                    hasher.write(table[Int(x)])
                } else {
                    hasher.write(x)
                }
            }
        }
        return Int(truncatingBitPattern: hasher.finish())
    }
    
    var description: String {
        return string
    }
    
    var debugDescription: String {
        return String(reflecting: string)
    }
    
    var customMirror: Mirror {
        return Mirror(reflecting: string)
    }
}

func ==(lhs: CaseInsensitiveASCIIString, rhs: CaseInsensitiveASCIIString) -> Bool {
    return CaseInsensitiveASCIIString.lowercaseTable.withUnsafeBufferPointer { table in
        var (lhsGen, rhsGen) = (lhs.string.utf16.makeIterator(), rhs.string.utf16.makeIterator())
        while true {
            switch (lhsGen.next(), rhsGen.next()) {
            case let (a?, b?):
                if _fastPath(a <= 127 && b <= 127) {
                    if table[Int(a)] != table[Int(b)] {
                        return false
                    }
                } else if a != b {
                    return false
                }
            case (_?, nil), (nil, _?): return false
            case (nil, nil): return true
            }
        }
    }
}

/// Returns the result of `pattern == CaseInsensitiveASCIIString(value)`.
func ~=(pattern: CaseInsensitiveASCIIString, value: String) -> Bool {
    return pattern == CaseInsensitiveASCIIString(value)
}

/// Parameters separated by a single character (typically comma or semicolon).
/// Acts as a sequence of `(name, value?)` pairs. The value is provided as-is, without any unquoting.
/// LWS is allowed around the delimiter character, but is not allowed around the =.
/// The accepted syntax is:
/// ```
/// params = OWS *( *( delim OWS ) token [ "=" ( token / quoted-string ) ] OWS ) *( delim OWS )
/// OWS = <OWS, see [RFC7230], Section 3.2.3> ; optional white-space
/// token = <token, see [RFC7230], Section 3.2.6>
/// quoted-string = <quoted-string, see [RFC7230], Section 3.2.6>
/// delim = <provided to the initializer, anything besides SP, HTAB, "=", or '"'>
/// ```
/// - Bug: Does not actually validate the whole syntax. Invalid sequences will still be yielded
///   as written, e.g. `"\"baz\"=foo bar"` will yield `("\"baz\"", "foo bar")`.
struct DelimitedParameters : Sequence, CustomStringConvertible {
    /// The raw value that was used to initialize the `DelimitedParameters`.
    let rawValue: String
    /// The delimiter that separates the elements in the raw value.
    let delimiter: UnicodeScalar
    
    var description: String {
        return rawValue
    }
    
    func makeIterator() -> Iterator {
        return Iterator(scalars: rawValue, delimiter: delimiter)
    }
    
    /// Constructs a `DelimitedParameters` from a given string.
    /// - Parameter rawValue: A string containing the delimited parameters.
    ///   For example, if the delimiter is `";"`, the raw value might be `"level=1"` or `"level=1; q=0.9"`.
    /// - Parameter delimiter: The delimiter that separates the parameters in the raw value. Default is `","`.
    /// - Requires: `delimiter` must not be `" "`, `"\t"`, `"="`, or `"\""`.
    init(_ rawValue: String, delimiter: UnicodeScalar = ",") {
        self.rawValue = rawValue
        self.delimiter = delimiter
        switch delimiter {
        case " ", "\t", "=", "\"":
            fatalError("cannot initialize DelimitedParameters with a scalar value \(String(reflecting: delimiter))")
        default: break
        }
    }
    
    struct Iterator : IteratorProtocol {
        private var scalars: Substring.UnicodeScalarView
        private let delimiter: UnicodeScalar
        
        init(scalars: String, delimiter: UnicodeScalar) {
            self.scalars = Substring(scalars).unicodeScalars
            self.delimiter = delimiter
        }
        
        mutating func next() -> (String,String?)? {
            func indexSequence(scalars: Substring.UnicodeScalarView, start: Substring.UnicodeScalarView.Index, end: Substring.UnicodeScalarView.Index) -> UnfoldSequence<Substring.UnicodeScalarView.Index, (Substring.UnicodeScalarView.Index, Bool)> {
                return sequence(state: (start, true), next: { (state: inout (String.UnicodeScalarIndex, Bool)) -> String.UnicodeScalarIndex? in
                    if !state.1 {
                        scalars.formIndex(after: &state.0)
                    } else {
                        state.1 = false
                    }
                    if state.0 == end {
                        return nil
                    } else {
                        return state.0
                    }
                })
            }
            
            /// Skips a quoted-string that starts at `start`. Returns the index of the first scalar
            /// past the end of the quoted-string, or `scalars.endIndex` if the string never ends.
            func skipQuotedStringAt(_ start: Substring.UnicodeScalarView.Index, scalars: Substring.UnicodeScalarView) -> Substring.UnicodeScalarView.Index {
                var iter = indexSequence(scalars: scalars, start: start, end: scalars.endIndex).makeIterator()
                _ = iter.next() // we already know start contains a dquote, don't bother looking at it.
                while let idx = iter.next() {
                    switch scalars[idx] {
                    case "\"": return scalars.index(after: idx)
                    case "\\": _ = iter.next()
                    default: break
                    }
                }
                return scalars.endIndex
            }
            
            top: while true { // loop in case of empty parameters
                guard let startIdx = scalars.index(where: { !isLWS($0) }) else { return nil }
                var equalIdx_: String.UnicodeScalarIndex?
                loop: for idx in indexSequence(scalars: scalars, start: startIdx, end: scalars.endIndex) {
                    switch scalars[idx] {
                    case "=":
                        equalIdx_ = idx
                        break loop
                    case delimiter:
                        // token with no value
                        defer { scalars = scalars.suffix(from: scalars.index(after: idx)) }
                        if idx == startIdx { // empty parameter, loop again
                            continue top
                        } else {
                            return (String(scalars[startIdx..<idx]), nil)
                        }
                    default:
                        break
                    }
                }
                guard let equalIdx = equalIdx_ else {
                    // final parameter has no value
                    defer { scalars = Substring.UnicodeScalarView() }
                    return (String(scalars.suffix(from: startIdx)), nil)
                }
                let valueIdx = scalars.index(after: equalIdx)
                var nextIdx = valueIdx
                if valueIdx != scalars.endIndex && scalars[valueIdx] == "\"" {
                    // skip the quoted-string
                    nextIdx = skipQuotedStringAt(valueIdx, scalars: scalars)
                    // there shouldn't be anything besides LWS before the next delimiter, but we'll just fall back
                    // to the non-quoted-string parse in case it is invalid.
                }
                var trailingLWSIdx: String.UnicodeScalarIndex?
                for idx in indexSequence(scalars: scalars, start: nextIdx, end: scalars.endIndex) {
                    switch scalars[idx] {
                    case delimiter:
                        defer { scalars = scalars.suffix(from: scalars.index(after: idx)) }
                        return (String(scalars[startIdx..<equalIdx]), String(scalars[valueIdx..<(trailingLWSIdx ?? idx)]))
                    case let us where isLWS(us):
                        if trailingLWSIdx == nil {
                            trailingLWSIdx = idx
                        }
                    default:
                        trailingLWSIdx = nil
                    }
                }
                defer { scalars = Substring.UnicodeScalarView() }
                return (String(scalars[startIdx..<equalIdx]), String(scalars[valueIdx..<(trailingLWSIdx ?? scalars.endIndex)]))
            }
        }
    }
}

/// Helper class for manipulating media types.
internal struct MediaType: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The portion of the media type before any parameters, with LWS trimmed off.
    /// Values are of the form `"text/plain"` or `"application/json"`.
    let typeSubtype: String
    /// The type portion of the media type, e.g. `"text"` for `"text/plain"`.
    let type: String
    /// The subtype portion of the media type, e.g. `"plain"` for `"text/plain"`.
    let subtype: String
    // The parameter portion of the media type. May be empty.
    let params: DelimitedParameters
    /// The raw value that was used to initialize the `MediaType`, with surrounding LWS removed.
    let rawValue: String
    
    var description: String {
        return rawValue
    }
    
    var debugDescription: String {
        return "MediaType(\(String(reflecting: typeSubtype)), \(String(reflecting: params.rawValue)))"
    }
    
    /// Constructs a `MediaType` from a string like `"text/plain"` or `"text/html; level=1; q=0.9"`.
    ///
    /// The expected format of the string is
    /// ```
    /// media-type = *LWS type "/" subtype *( *LWS ";" *LWS name "=" value ) *LWS
    /// type = token | "*"
    /// subtype = token | "*"
    /// name = token
    /// value = token | quoted-string
    /// ```
    ///
    /// - Bug: This does not currently perform any validation of the media type syntax.
    init(_ rawValue: String) {
        let rawValue = trimLWS(rawValue)
        self.rawValue = rawValue
        if let idx = rawValue.unicodeScalars.index(of: ";") {
            typeSubtype = trimLWS(String(rawValue.unicodeScalars.prefix(upTo: idx)))
            params = DelimitedParameters(String(rawValue.unicodeScalars.suffix(from: rawValue.unicodeScalars.index(after: idx))), delimiter: ";")
        } else {
            typeSubtype = rawValue
            params = DelimitedParameters("", delimiter: ";")
        }
        if let slashIdx = typeSubtype.unicodeScalars.index(of: "/") {
            type = String(typeSubtype.unicodeScalars.prefix(upTo: slashIdx))
            subtype = String(typeSubtype.unicodeScalars.suffix(from: typeSubtype.unicodeScalars.index(after: slashIdx)))
        } else {
            type = typeSubtype
            subtype = ""
        }
    }
}

/// Compares two `MediaType`s for equality, ignoring any LWS.
/// The type, subtype, and parameter names are case-insensitive, but the parameter values are case-sensitive.
/// - Note: The order of parameters is considered significant.
func ==(lhs: MediaType, rhs: MediaType) -> Bool {
    return lhs.typeSubtype.caseInsensitiveCompare(rhs.typeSubtype) == .orderedSame
        && lhs.params.elementsEqual(rhs.params, by: { $0.0.caseInsensitiveCompare($1.0) == .orderedSame && $0.1 == $1.1 })
}

/// Returns `true` iff `pattern` is equal to `value`, where a `type` or `subtype` of `*`
/// in `pattern` is treated as matching all strings, and where `value` may contain parameters
/// that `pattern` does not have. Any parameters in `pattern` are treated as required.
/// The type, subtype, and parameter names are case-insensitive, but the parameter values are case-sensitive.
/// - Note: The order of parameters is considered significant. The `value` may contain
///   parameters that `pattern` does not have, but any parameters in `pattern` must occur in
///   the same order in `value` (possibly with other parameters interspersed).
func ~=(pattern: MediaType, value: MediaType) -> Bool {
    if pattern.type != "*" && pattern.type.caseInsensitiveCompare(value.type) != .orderedSame { return false }
    if pattern.subtype != "*" && pattern.subtype.caseInsensitiveCompare(value.subtype) != .orderedSame { return false }
    if !pattern.params.rawValue.isEmpty {
        var pgen = pattern.params.makeIterator()
        var vgen = value.params.makeIterator()
        outer: while let pparam = pgen.next() {
            while let vparam = vgen.next() {
                if pparam.0.caseInsensitiveCompare(vparam.0) == .orderedSame && pparam.1 == vparam.1 {
                    continue outer
                }
            }
            // we ran out of value parameters
            return false
        }
    }
    return true
}

internal extension Sequence {
    func chain<Seq: Sequence>(_ seq: Seq) -> Chain<Self, Seq> where Seq.Iterator.Element == Self.Iterator.Element {
        return Chain(self, seq)
    }
}

internal struct Chain<First: Sequence, Second: Sequence>: Sequence where First.Iterator.Element == Second.Iterator.Element {
    init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
    
    func makeIterator() -> ChainGenerator<First.Iterator, Second.Iterator> {
        return ChainGenerator(first.makeIterator(), second.makeIterator())
    }
    
    func underestimateCount() -> Int {
        return first.underestimatedCount + second.underestimatedCount
    }
    
    private let first: First
    private let second: Second
}

internal struct ChainGenerator<First: IteratorProtocol, Second: IteratorProtocol>: IteratorProtocol where First.Element == Second.Element {
    init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
    
    mutating func next() -> First.Element? {
        if !firstDone {
            switch first.next() {
            case let x?: return x
            case nil: firstDone = true
            }
        }
        return second.next()
    }
    
    private var first: First
    private var second: Second
    private var firstDone: Bool = false
}

/// Returns the mach absolute time in nanoseconds.
/// This is a monotonic clock that is suitable for measuring short durations.
/// - Bug: This function might overflow when converting to the timebase.
///   The overflow will not trap, but will likely result in an incorrect value.
internal func getMachAbsoluteTimeInNanoseconds() -> UInt64 {
    struct Static {
        static let timebase: mach_timebase_info = {
            var timebase = mach_timebase_info(numer: 0, denom: 0)
            let err = mach_timebase_info(&timebase)
            if err != 0 {
                print("Error in mach_timebase_info: \(err)")
                exit(1)
            }
            return timebase
        }()
    }
    
    let timebase = Static.timebase
    let time = mach_absolute_time()
    return time &* UInt64(timebase.numer) / UInt64(timebase.denom)
}
