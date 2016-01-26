//
//  Utilities.swift
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 1/18/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

/// Returns `true` iff the unicode scalar is a Linear White Space character
/// (as defined by RFC 2616).
internal func isLWS(us: UnicodeScalar) -> Bool {
    switch us {
    case " ", "\t": return true
    default: return false
    }
}

/// Trims any Linear White Space (as defined by RFC 2616) from both ends of the `String`.
internal func trimLWS(str: String) -> String {
    let scalars = str.unicodeScalars
    let start = scalars.indexOf({ !isLWS($0) })
    let end = scalars.reverse().indexOf({ !isLWS($0) })?.base
    return String(scalars[(start ?? scalars.startIndex)..<(end ?? scalars.endIndex)])
}

/// A `String` newtype that supports case-insensitive hashing and equality comparisons.
///
/// This type only works properly with ASCII strings. Strings with non-ASCII scalars will compare
/// using string scalar equality, without even taking NFD form into account. This means that
/// `"t\u{E9}st"` and `"te\u{301}st"` compare as non-equal even though the `String` versions
/// will compare as equal.
/// - Note: The `hashValue` of `CaseInsensitiveString` will not match the `hashValue` of `String`
///   even when the wrapped string is already lowercase.
internal struct CaseInsensitiveASCIIString: Hashable, StringLiteralConvertible, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The wrapped string.
    let string: String
    
    /// Creates a new `CaseInsensitiveString` that wraps a given string.
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
    private static let lowercaseTable: ContiguousArray<UInt8> = ContiguousArray(((0 as UInt8)...127).lazy.map({ x in
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
    
    func customMirror() -> Mirror {
        return Mirror(reflecting: string)
    }
}

func ==(lhs: CaseInsensitiveASCIIString, rhs: CaseInsensitiveASCIIString) -> Bool {
    return CaseInsensitiveASCIIString.lowercaseTable.withUnsafeBufferPointer { table in
        var (lhsGen, rhsGen) = (lhs.string.utf16.generate(), rhs.string.utf16.generate())
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
struct DelimitedParameters : SequenceType, CustomStringConvertible {
    /// The raw value that was used to initialize the `DelimitedParameters`.
    let rawValue: String
    /// The delimiter that separates the elements in the raw value.
    let delimiter: UnicodeScalar
    
    var description: String {
        return rawValue
    }
    
    func generate() -> Generator {
        return Generator(scalars: rawValue.unicodeScalars, delimiter: delimiter)
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
    
    struct Generator : GeneratorType {
        private var scalars: String.UnicodeScalarView
        private let delimiter: UnicodeScalar
        
        mutating func next() -> (String,String?)? {
            /// Skips a quoted-string that starts at `start`. Returns the index of the first scalar
            /// past the end of the quoted-string, or `scalars.endIndex` if the string never ends.
            func skipQuotedStringAt(start: String.UnicodeScalarIndex, scalars: String.UnicodeScalarView) -> String.UnicodeScalarIndex {
                // we already know start contains a dquote, don't bother looking at it.
                var gen = (start.successor()..<scalars.endIndex).generate()
                while let idx = gen.next() {
                    switch scalars[idx] {
                    case "\"": return idx.successor()
                    case "\\": _ = gen.next()
                    default: break
                    }
                }
                return scalars.endIndex
            }
            
            top: while true { // loop in case of empty parameters
                guard let startIdx = scalars.indexOf({ !isLWS($0) }) else { return nil }
                var equalIdx_: String.UnicodeScalarIndex?
                loop: for idx in startIdx..<scalars.endIndex {
                    switch scalars[idx] {
                    case "=":
                        equalIdx_ = idx
                        break loop
                    case delimiter:
                        // token with no value
                        defer { scalars = scalars.suffixFrom(idx.successor()) }
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
                    defer { scalars = String.UnicodeScalarView() }
                    return (String(scalars.suffixFrom(startIdx)), nil)
                }
                let valueIdx = equalIdx.successor()
                var nextIdx = valueIdx
                if valueIdx != scalars.endIndex && scalars[valueIdx] == "\"" {
                    // skip the quoted-string
                    nextIdx = skipQuotedStringAt(valueIdx, scalars: scalars)
                    // there shouldn't be anything besides LWS before the next delimiter, but we'll just fall back
                    // to the non-quoted-string parse in case it is invalid.
                }
                var trailingLWSIdx: String.UnicodeScalarIndex?
                for idx in nextIdx..<scalars.endIndex {
                    switch scalars[idx] {
                    case delimiter:
                        defer { scalars = scalars.suffixFrom(idx.successor()) }
                        return (String(scalars[startIdx..<equalIdx]), String(scalars[valueIdx..<(trailingLWSIdx ?? idx)]))
                    case let us where isLWS(us):
                        if trailingLWSIdx == nil {
                            trailingLWSIdx = idx
                        }
                    default:
                        trailingLWSIdx = nil
                    }
                }
                defer { scalars = String.UnicodeScalarView() }
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
        if let idx = rawValue.unicodeScalars.indexOf(";") {
            typeSubtype = trimLWS(String(rawValue.unicodeScalars.prefixUpTo(idx)))
            params = DelimitedParameters(String(rawValue.unicodeScalars.suffixFrom(idx.successor())), delimiter: ";")
        } else {
            typeSubtype = trimLWS(rawValue)
            params = DelimitedParameters("", delimiter: ";")
        }
        if let slashIdx = typeSubtype.unicodeScalars.indexOf("/") {
            type = String(typeSubtype.unicodeScalars.prefixUpTo(slashIdx))
            subtype = String(typeSubtype.unicodeScalars.suffixFrom(slashIdx.successor()))
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
    return lhs.typeSubtype.caseInsensitiveCompare(rhs.typeSubtype) == .OrderedSame
        && lhs.params.elementsEqual(rhs.params, isEquivalent: { $0.0.caseInsensitiveCompare($1.0) == .OrderedSame && $0.1 == $1.1 })
}

/// Returns `true` iff `pattern` is equal to `value`, where a `type` or `subtype` of `*`
/// in `pattern` is treated as matching all strings, and where `value` may contain parameters
/// that `pattern` does not have. Any parameters in `pattern` are treated as required.
/// The type, subtype, and parameter names are case-insensitive, but the parameter values are case-sensitive.
/// - Note: The order of parameters is considered significant. The `value` may contain
///   parameters that `pattern` does not have, but any parameters in `pattern` must occur in
///   the same order in `value` (possibly with other parameters interspersed).
func ~=(pattern: MediaType, value: MediaType) -> Bool {
    if pattern.type != "*" && pattern.type.caseInsensitiveCompare(value.type) != .OrderedSame { return false }
    if pattern.subtype != "*" && pattern.subtype.caseInsensitiveCompare(value.subtype) != .OrderedSame { return false }
    if !pattern.params.rawValue.isEmpty {
        var pgen = pattern.params.generate()
        var vgen = value.params.generate()
        outer: while let pparam = pgen.next() {
            while let vparam = vgen.next() {
                if pparam.0.caseInsensitiveCompare(vparam.0) == .OrderedSame && pparam.1 == vparam.1 {
                    continue outer
                }
            }
            // we ran out of value parameters
            return false
        }
    }
    return true
}
