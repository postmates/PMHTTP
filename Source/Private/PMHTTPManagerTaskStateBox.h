//
//  PMHTTPManagerTaskStateBox.h
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 1/5/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

@import Foundation;

typedef NS_ENUM(unsigned char, PMHTTPManagerTaskStateBoxState) {
    PMHTTPManagerTaskStateBoxStateRunning = 0,
    PMHTTPManagerTaskStateBoxStateProcessing = 1,
    PMHTTPManagerTaskStateBoxStateCanceled = 2,
    PMHTTPManagerTaskStateBoxStateCompleted = 3
};

typedef struct PMHTTPManagerTaskStateBoxResult {
    /// `true` if the state is now in the desired state, whether
    /// or not a transition actually happened.
    _Bool completed;
    /// The state that it was in before.
    PMHTTPManagerTaskStateBoxState oldState;
} PMHTTPManagerTaskStateBoxResult;

__attribute__((objc_subclassing_restricted))
@interface PMHTTPManagerTaskStateBox : NSObject
@property (atomic, readonly) PMHTTPManagerTaskStateBoxState state;
- (nonnull instancetype)initWithState:(PMHTTPManagerTaskStateBoxState)state NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)init NS_UNAVAILABLE;
/// Transitions the state to \c newState if possible.
- (PMHTTPManagerTaskStateBoxResult)transitionStateTo:(PMHTTPManagerTaskStateBoxState)newState;
@end
