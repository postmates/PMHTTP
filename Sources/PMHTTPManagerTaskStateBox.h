//
//  PMHTTPManagerTaskStateBox.h
//  PMHTTP
//
//  Created by Kevin Ballard on 1/5/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

@import Foundation;

/// A private implementation detail of PMHTTP. Do not use this enum.
typedef NS_ENUM(unsigned char, _PMHTTPManagerTaskStateBoxState) {
    // Important: The constants here must match those defined in HTTPManagerTaskState
    
    /// The Running state. This state can transition into Processing and Canceled.
    _PMHTTPManagerTaskStateBoxStateRunning = 0,
    /// The Processing state. This state can transition into any state. Transitioning
    /// back into Running occurs when the task fails and is automatically retried.
    _PMHTTPManagerTaskStateBoxStateProcessing = 1,
    /// The Canceled state. This state cannot transition anywhere.
    _PMHTTPManagerTaskStateBoxStateCanceled = 2,
    /// The Completed state. This state cannot transition anywhere.
    _PMHTTPManagerTaskStateBoxStateCompleted = 3
};

/// A private implementation detail of PMHTTP. Do not use this struct.
typedef struct _PMHTTPManagerTaskStateBoxResult {
    /// `true` if the state is now in the desired state, whether
    /// or not a transition actually happened.
    _Bool completed;
    /// The state that it was in before.
    _PMHTTPManagerTaskStateBoxState oldState;
} _PMHTTPManagerTaskStateBoxResult;

/// A private implementation detail of PMHTTP. Do not use this class.
__attribute__((objc_subclassing_restricted))
__attribute__((visibility("hidden")))
@interface _PMHTTPManagerTaskStateBox : NSObject
@property (atomic, readonly) _PMHTTPManagerTaskStateBoxState state;
@property (atomic, nonnull, retain) NSURLSessionTask *networkTask;
- (nonnull instancetype)initWithState:(_PMHTTPManagerTaskStateBoxState)state networkTask:(nonnull NSURLSessionTask *)task NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)init NS_UNAVAILABLE;
/// Transitions the state to \c newState if possible.
- (_PMHTTPManagerTaskStateBoxResult)transitionStateTo:(_PMHTTPManagerTaskStateBoxState)newState NS_SWIFT_NAME(transitionState(to:));
/// Sets the tracking network activity flag and returns the previous value.
- (BOOL)setTrackingNetworkActivity;
/// Clears the tracking network activity flag and returns the previous value.
- (BOOL)clearTrackingNetworkActivity;
@end
