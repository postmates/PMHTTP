//
//  HTTPManagerNetworkActivityManager.swift
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

#if os(iOS)
    
    import Foundation
    import UIKit
    
    @available(iOSApplicationExtension, unavailable)
    internal final class NetworkActivityManager: NSObject {
        static let shared = NetworkActivityManager()
        
        /// Increments the global network activity counter.
        func incrementCounter() {
            dispatch_source_merge_data(source, 1)
        }
        
        /// Decrements the global network activity counter.
        func decrementCounter() {
            dispatch_source_merge_data(source, UInt(bitPattern: -1))
        }
        
        /// Starts tracking a given task.
        func trackTask(task: NSURLSessionTask) {
            task.addObserver(self, forKeyPath: "state", options: [.Initial, .Old, .New], context: &kvoContext)
        }
        
        override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
            guard context == &kvoContext else {
                return super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
            }
            let old = (change?[NSKeyValueChangeOldKey] as? Int).flatMap(NSURLSessionTaskState.init)
            guard let new = (change?[NSKeyValueChangeNewKey] as? Int).flatMap(NSURLSessionTaskState.init) else { return }
            switch (old, new) {
            case (nil, .Running), (.Suspended?, .Running):
                incrementCounter()
            case (.Running?, .Suspended):
                decrementCounter()
            case (.Running?, .Canceling), (.Running?, .Completed):
                decrementCounter()
                fallthrough
            case (_, .Canceling), (_, .Completed):
                (object as? NSObject)?.removeObserver(self, forKeyPath: "state", context: &kvoContext)
            default:
                break
            }
        }
        
        private let source: dispatch_source_t
        private var counter: Int = 0
        
        private override init() {
            source = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, dispatch_get_main_queue())
            super.init()
            dispatch_source_set_cancel_handler(source) {
                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            }
            dispatch_source_set_event_handler(source) { [source] in
                let data = Int(bitPattern: dispatch_source_get_data(source))
                self.counter = max(self.counter + data, 0)
                UIApplication.sharedApplication().networkActivityIndicatorVisible = self.counter > 0
            }
            dispatch_resume(source)
        }
        
        deinit {
            // We can't support deinit if we're KVOing tasks without a lot of extra work.
            // Since we're actually a singleton, we should never deinit anyway.
            fatalError("NetworkActivityManager should never deinit")
        }
    }
    
    private var kvoContext: ()?
    
#endif
