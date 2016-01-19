//
//  APIManagerNetworkActivityManager.swift
//  PMAPI
//
//  Created by Kevin Ballard on 1/6/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

#if os(iOS)
    
    import Foundation
    import UIKit
    
    @available(iOSApplicationExtension, unavailable)
    internal final class NetworkActivityManager: NSObject {
        static let shared = NetworkActivityManager()
        
        let source: dispatch_source_t
        var counter: Int = 0
        
        override init() {
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
            dispatch_source_cancel(source)
        }
        
        func incrementCounter() {
            dispatch_source_merge_data(source, 1)
        }
        
        func decrementCounter() {
            dispatch_source_merge_data(source, UInt(bitPattern: -1))
        }
    }
    
#endif
