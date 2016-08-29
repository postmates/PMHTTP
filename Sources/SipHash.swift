//
//  SipHash.swift
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

/// A generic hasher that implements SipHash-2-4.
/// Once a hasher is created, data can be added to it iteratively.
/// Once all data has been added, call `finish()` to get the resulting value.
/// After the hasher has been finalized, it resets to the initial state and can
/// be reused to hash new data.
///
/// - Important: Although the SipHash algorithm is considered to be cryptographically strong,
///   this implementation has not been reviewed for such purposes and is almost certainly insecure.
internal struct SipHasher: TextOutputStream {
    /// Creates a new `SipHasher`.
    /// - Parameter key: A pair of 64-bit integers to use as the key. Defaults to `(0,0)`.
    ///   This pair of integers is equivalent to a 128-bit key where the first element is
    ///   the low 64 bits and the second element is the high 64 bits.
    init(key: (UInt64, UInt64) = (0,0)) {
        k0 = key.0
        k1 = key.1
        v0 = k0 ^ 0x736f6d6570736575
        v1 = k1 ^ 0x646f72616e646f6d
        v2 = k0 ^ 0x6c7967656e657261
        v3 = k1 ^ 0x7465646279746573
    }
    
    // key
    let k0: UInt64
    let k1: UInt64
    // hash state
    // v0, v2 and v1, v3 show up in pairs in the algorithm.
    // order them that way here in case the compiler can pick up some simd optimizations automatically
    var v0: UInt64
    var v2: UInt64
    var v1: UInt64
    var v3: UInt64
    /// Number of bytes processed
    var b: UInt = 0
    /// Number of unprocessed bytes at the end.
    var tail: UInt64 = 0
    /// Number of bytes in `tail` that are valid. Guaranteed to be less than 8.
    var tailLen: UInt = 0
    
    mutating func write<C: Collection>(_ bytes: C) where C.Iterator.Element == UInt8 {
        var count: UInt = numericCast(bytes.count)
        b += count
        var startIndex = bytes.startIndex
        @inline(__always) func u8to64_le(_ idx: inout C.Index, len: UInt) -> UInt64 {
            var acc: UInt64 = 0
            for i in 0..<len {
                acc |= UInt64(bytes[idx]) << UInt64(8 * i)
                idx = bytes.index(after: idx)
            }
            return acc
        }
        if tailLen != 0 {
            let needed = 8 - tailLen
            tail |= u8to64_le(&startIndex, len: min(count, needed)) << UInt64(8 * tailLen)
            if count < needed {
                tailLen += count
                return
            } else {
                compress(tail)
                // NB: tail and tailLen are reset later
                count -= needed
            }
        }
        for _ in 0..<(count / 8) {
            compress(u8to64_le(&startIndex, len: 8))
        }
        tailLen = count % 8
        if tailLen > 0 {
            tail = u8to64_le(&startIndex, len: tailLen)
        }
    }
    
    mutating func finish() -> UInt64 {
        defer { self = SipHasher(key: (k0, k1)) }
        if tailLen == 0 {
            tail = 0
        }
        tail |= UInt64(b) << 56
        compress(tail)
        v2 ^= 0xff
        sipRound()
        sipRound()
        sipRound()
        sipRound()
        return v0 ^ v1 ^ v2 ^ v3
    }
    
    @inline(__always) private mutating func compress(_ m: UInt64) {
        v3 ^= m
        sipRound()
        sipRound()
        v0 ^= m
    }
    
    @inline(__always) private mutating func sipRound() {
        @inline(__always) func rotl(_ x: UInt64, _ n: UInt64) -> UInt64 {
            return (x << n) | (x >> (64 &- n))
        }
        v0 = v0 &+ v1
        v1 = rotl(v1, 13)
        v1 ^= v0
        
        v2 = v2 &+ v3
        v3 = rotl(v3, 16)
        v3 ^= v2
        
        v0 = rotl(v0, 32)
        
        v2 = v2 &+ v1
        v1 = rotl(v1, 17)
        v1 ^= v2
        
        v0 = v0 &+ v3
        v3 = rotl(v3, 21)
        v3 ^= v0
        
        v2 = rotl(v2, 32)
    }
    
    // MARK: Convenience methods
    
    /// Writes an `Int8` to the `SipHasher`.
    mutating func write(_ n: Int8) {
        write(CollectionOfOne(UInt8(bitPattern: n)))
    }
    
    /// Writes the little-endian representation of an `Int16` to the `SipHasher`.
    mutating func write(_ n: Int16) {
        var n = n.littleEndian
        withUnsafePointer(to: &n) { ptr in
            let count = MemoryLayout<Int16>.size
            ptr.withMemoryRebound(to: UInt8.self, capacity: count, { ptr in
                write(UnsafeBufferPointer(start: ptr, count: count))
            })
        }
    }
    
    /// Writes the little-endian representation of an `Int32` to the `SipHasher`.
    mutating func write(_ n: Int32) {
        var n = n.littleEndian
        withUnsafePointer(to: &n) { ptr in
            let count = MemoryLayout<Int32>.size
            ptr.withMemoryRebound(to: UInt8.self, capacity: count, { ptr in
                write(UnsafeBufferPointer(start: ptr, count: count))
            })
        }
    }
    
    /// Writes the little-endian representation of an `Int64` to the `SipHasher`.
    mutating func write(_ n: Int64) {
        var n = n.littleEndian
        withUnsafePointer(to: &n) { ptr in
            let count = MemoryLayout<Int64>.size
            ptr.withMemoryRebound(to: UInt8.self, capacity: count, { ptr in
                write(UnsafeBufferPointer(start: ptr, count: count))
            })
        }
    }
    
    /// Writes a `UInt8` to the `SipHasher`.
    mutating func write(_ n: UInt8) {
        write(CollectionOfOne(n))
    }
    
    /// Writes the little-endian representation of a `UInt16` to the `SipHasher`.
    mutating func write(_ n: UInt16) {
        var n = n.littleEndian
        withUnsafePointer(to: &n) { ptr in
            let count = MemoryLayout<UInt16>.size
            ptr.withMemoryRebound(to: UInt8.self, capacity: count, { ptr in
                write(UnsafeBufferPointer(start: ptr, count: count))
            })
        }
    }
    
    /// Writes the little-endian representation of a `UInt32` to the `SipHasher`.
    mutating func write(_ n: UInt32) {
        var n = n.littleEndian
        withUnsafePointer(to: &n) { ptr in
            let count = MemoryLayout<UInt32>.size
            ptr.withMemoryRebound(to: UInt8.self, capacity: count, { ptr in
                write(UnsafeBufferPointer(start: ptr, count: count))
            })
        }
    }
    
    /// Writes the little-endian representation of a `UInt64` to the `SipHasher`.
    mutating func write(_ n: UInt64) {
        var n = n.littleEndian
        withUnsafePointer(to: &n) { ptr in
            let count = MemoryLayout<UInt64>.size
            ptr.withMemoryRebound(to: UInt8.self, capacity: count, { ptr in
                write(UnsafeBufferPointer(start: ptr, count: count))
            })
        }
    }
    
    /// Writes a `Bool` to the `SipHasher`, as a single byte of value `0` or `1`.
    mutating func write(_ b: Bool) {
        let n: UInt8 = b ? 1 : 0
        write(n)
    }
    
    /// Writes the UTF-16 representation of `string` to the hasher.
    /// - Note: This does not take canonical equivalence into account.
    mutating func write(_ string: String) {
        for x in string.utf16 {
            write(x)
        }
    }
    
    /// Writes the `UInt32` representation of `scalar` to the hasher.
    mutating func write(_ scalar: UnicodeScalar) {
        write(scalar.value)
    }
    
    /// Writes the string representation of `c` to the hasher.
    mutating func write(_ c: Character) {
        c.write(to: &self)
    }
}
