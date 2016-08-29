//
//  QueueConfined.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 12/23/15.
//  Copyright © 2015 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Foundation

/// Manages access to a contained value using a concurrent dispatch queue.
// NB: This is a class because struct copies would break the safety
internal class QueueConfined<Value: AnyObject> {
    private let queue: DispatchQueue
    private var value: Value
    
    init(label: String, value: Value) {
        queue = DispatchQueue(label: label, attributes: .concurrent)
        self.value = value
    }
    
    func sync(_ f: (Value) -> Void) {
        queue.sync {
            f(self.value)
        }
    }
    
    func sync<T>(_ f: (Value) -> T) -> T {
        return queue.sync {
            return f(self.value)
        }
    }
    
    func syncBarrier(_ f: (Value) -> Void) {
        queue.sync(flags: .barrier, execute: {
            f(self.value)
        })
    }
    
    func syncBarrier<T>(_ f: (Value) -> T) -> T {
        return queue.sync(flags: .barrier, execute: {
            return f(self.value)
        })
    }
    
    func async(_ f: @escaping (Value) -> Void) {
        queue.async {
            f(self.value)
        }
    }
    
    func asyncBarrier(_ f: @escaping (Value) -> Void) {
        queue.async(flags: .barrier, execute: {
            f(self.value)
        })
    }
    
    /// Provides direct access to the value without going through the queue.
    /// Use this only when you're guaranteed that there's no concurrency.
    func unsafeDirectAccess<T>(_ f: (Value) -> T) -> T {
        return f(value)
    }
}
