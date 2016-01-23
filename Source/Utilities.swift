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
    let params: Parameters
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
            params = Parameters(String(rawValue.unicodeScalars.suffixFrom(idx.successor())))
        } else {
            typeSubtype = trimLWS(rawValue)
            params = Parameters("")
        }
        if let slashIdx = typeSubtype.unicodeScalars.indexOf("/") {
            type = String(typeSubtype.unicodeScalars.prefixUpTo(slashIdx))
            subtype = String(typeSubtype.unicodeScalars.suffixFrom(slashIdx.successor()))
        } else {
            type = typeSubtype
            subtype = ""
        }
    }
    
    /// Parameters from a media type. Acts as a sequence of `(name, value)` pairs.
    /// The value is provided as-is, without any unquoting.
    struct Parameters : SequenceType, CustomStringConvertible {
        /// The raw value that was used to initialize the `Parameters`.
        let rawValue: String
        
        var description: String {
            return rawValue
        }
        
        func generate() -> Generator {
            return Generator(scalars: rawValue.unicodeScalars)
        }
        
        /// Constructs a `Parameters` from the parameter portion of a media type string.
        /// - Parameter rawValue: A string like `"level=1"` or `"level=1; q=0.9"`.
        ///   The string must match the following syntax:
        ///   ```
        ///   params = name "=" value *( *LWS ";" *LWS name "=" value )
        ///   name = token
        ///   value = token | quoted-string
        ///   ```
        ///   The definitions of `LWS`, `token`, and `quoted-string` come from RFC 2616.
        init(_ rawValue: String) {
            self.rawValue = rawValue
        }
        
        struct Generator : GeneratorType {
            var scalars: String.UnicodeScalarView
            
            mutating func next() -> (String,String)? {
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
                
                top: while true { // loop in case of empty parameters (which aren't legal anyway)
                    guard let startIdx = scalars.indexOf({ !isLWS($0) }) else { return nil }
                    var equalIdx_: String.UnicodeScalarIndex?
                    loop: for idx in startIdx..<scalars.endIndex {
                        switch scalars[idx] {
                        case "=":
                            equalIdx_ = idx
                            break loop
                        case ";":
                            // parameter with no value; not legal, but we'll handle it anyway
                            defer { scalars = scalars.suffixFrom(idx.successor()) }
                            if idx == startIdx { // empty parameter, loop again
                                continue top
                            } else {
                                return (String(scalars[startIdx..<idx]), "")
                            }
                        default:
                            break
                        }
                    }
                    guard let equalIdx = equalIdx_ else {
                        // final parameter has no value
                        defer { scalars = String.UnicodeScalarView() }
                        return (String(scalars.suffixFrom(startIdx)), "")
                    }
                    let valueIdx = equalIdx.successor()
                    var nextIdx = valueIdx
                    if valueIdx != scalars.endIndex && scalars[valueIdx] == "\"" {
                        // skip the quoted-string
                        nextIdx = skipQuotedStringAt(valueIdx, scalars: scalars)
                        // there shouldn't be anything besides LWS before the next semi, but we'll just fall back
                        // to the non-quoted-string parse in case it is invalid.
                    }
                    var trailingLWSIdx: String.UnicodeScalarIndex?
                    for idx in nextIdx..<scalars.endIndex {
                        switch scalars[idx] {
                        case ";":
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
