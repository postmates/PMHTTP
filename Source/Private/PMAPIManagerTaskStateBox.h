//
//  PMAPIManagerTaskStateBox.h
//  PMAPI
//
//  Created by Kevin Ballard on 1/5/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

@import Foundation;

typedef NS_ENUM(unsigned char, PMAPIManagerTaskStateBoxState) {
    PMAPIManagerTaskStateBoxStateRunning = 0,
    PMAPIManagerTaskStateBoxStateProcessing = 1,
    PMAPIManagerTaskStateBoxStateCanceled = 2,
    PMAPIManagerTaskStateBoxStateCompleted = 3
};

typedef struct PMAPIManagerTaskStateBoxResult {
    /// `true` if the state is now in the desired state, whether
    /// or not a transition actually happened.
    _Bool completed;
    /// The state that it was in before.
    PMAPIManagerTaskStateBoxState oldState;
} PMAPIManagerTaskStateBoxResult;

__attribute__((objc_subclassing_restricted))
@interface PMAPIManagerTaskStateBox : NSObject
@property (atomic, readonly) PMAPIManagerTaskStateBoxState state;
- (nonnull instancetype)initWithState:(PMAPIManagerTaskStateBoxState)state NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)init NS_UNAVAILABLE;
/// Transitions the state to \c newState if possible.
- (PMAPIManagerTaskStateBoxResult)transitionStateTo:(PMAPIManagerTaskStateBoxState)newState;
@end
