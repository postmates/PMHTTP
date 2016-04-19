//
//  QueueConfined.swift
//  PostmatesNetworking
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
    private let queue: dispatch_queue_t
    private var value: Value
    
    init(label: String, value: Value) {
        queue = dispatch_queue_create(label, DISPATCH_QUEUE_CONCURRENT)
        self.value = value
    }
    
    func sync(f: Value -> Void) {
        dispatch_sync(queue) {
            f(self.value)
        }
    }
    
    func sync<T>(f: Value -> T) -> T {
        var result: T!
        dispatch_sync(queue) {
            result = f(self.value)
        }
        return result
    }
    
    func syncBarrier(f: Value -> Void) {
        dispatch_barrier_sync(queue) {
            f(self.value)
        }
    }
    
    func syncBarrier<T>(f: Value -> T) -> T {
        var result: T!
        dispatch_barrier_sync(queue) {
            result = f(self.value)
        }
        return result
    }
    
    func async(f: Value -> Void) {
        dispatch_async(queue) {
            f(self.value)
        }
    }
    
    func asyncBarrier(f: Value -> Void) {
        dispatch_barrier_async(queue) {
            f(self.value)
        }
    }
    
    /// Provides direct access to the value without going through the queue.
    /// Use this only when you're guaranteed that there's no concurrency.
    func unsafeDirectAccess<T>(@noescape f: Value -> T) -> T {
        return f(value)
    }
}
