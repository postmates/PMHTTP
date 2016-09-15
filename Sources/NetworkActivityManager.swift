//
//  NetworkActivityManager.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 1/6/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

import Foundation

internal final class NetworkActivityManager: NSObject {
    static let shared = NetworkActivityManager()
    
    var networkActivityHandler: ((_ numberOfActiveTasks: Int) -> Void)? {
        get {
            if Thread.isMainThread {
                return data.networkActivityHandler
            } else {
                return inner.sync({ $0.networkActivityHandler })
            }
        }
        set {
            // This is a little complicated. The main thread is the source of truth for this, but we need
            // to avoid having the background reference get out of sync. To that end, if we're not on the main
            // thread already, we schedule a block to update the background reference first. Then we update the
            // reference on the main thread, and from there we schedule another block to ensure the background
            // reference is up-to-date. This means that the background reference is guaranteed to sync back up
            // with the main thread even if someone else mucks with this property concurrently. And the initial
            // background assignment exists so that way the property can be queried immediately after being set
            // and it will return the correct value.
            func handler() {
                data.networkActivityHandler = newValue
                inner.asyncBarrier {
                    $0.networkActivityHandler = newValue
                }
                if data.counter > 0 && newValue != nil && !data.pendingHandlerInvocation {
                    data.pendingHandlerInvocation = true
                    DispatchQueue.main.async { [data] in
                        data.pendingHandlerInvocation = false
                        if data.counter > 0, let handler = data.networkActivityHandler {
                            autoreleasepool {
                                handler(data.counter)
                            }
                        }
                    }
                }
            }
            if Thread.isMainThread {
                handler()
            } else {
                inner.asyncBarrier {
                    $0.networkActivityHandler = newValue
                }
                DispatchQueue.main.async {
                    autoreleasepool {
                        handler()
                    }
                }
            }
        }
    }
    
    /// Increments the global network activity counter.
    func incrementCounter() {
        source.add(data: 1)
    }
    
    /// Decrements the global network activity counter.
    func decrementCounter() {
        source.add(data: UInt(bitPattern: -1))
    }
    
    private var inner = QueueConfined(label: "NetworkActivityManager internal queue", value: Inner())
    
    private class Inner {
        /// A reference to the network activity handler that can only be accessed via a queue.
        var networkActivityHandler: ((_ numberOfActiveTasks: Int) -> Void)?
    }
    
    /// Data for the network activity indicator.
    /// - Important: This must be accessed from the main thread only.
    private class Data {
        var counter: Int = 0
        /// A reference to the network activity handler that is only safe to access from the main thread.
        /// This exists so we don't have to go through a queue on every state change, since all our interactions
        /// with the handler are expected to occur on the main thread.
        var networkActivityHandler: ((_ numberOfActiveTasks: Int) -> Void)?
        /// Set to `true` when modifying the `networkActivityHandler` property to indicate that an asynchronous
        /// invocation of the property has been scheduled.
        var pendingHandlerInvocation = false
    }
    
    private let source: DispatchSourceUserDataAdd
    private let data = Data()
    
    private override init() {
        source = DispatchSource.makeUserDataAddSource(queue: DispatchQueue.main)
        super.init()
        source.setCancelHandler { [data] in
            data.counter = 0
            data.networkActivityHandler?(0)
        }
        source.setEventHandler { [data, source] in
            let delta = Int(bitPattern: source.data)
            data.counter = data.counter + delta
            data.networkActivityHandler?(max(data.counter, 0))
        }
        source.resume()
    }
    
    deinit {
        source.cancel()
    }
}
