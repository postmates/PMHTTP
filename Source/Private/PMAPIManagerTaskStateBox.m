//
//  PMAPIManagerTaskStateBox.m
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 1/5/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

#import "PMAPIManagerTaskStateBox.h"
#import <stdatomic.h>

@implementation PMAPIManagerTaskStateBox {
    atomic_uchar _state;
}

- (nonnull instancetype)initWithState:(PMAPIManagerTaskStateBoxState)state {
    if ((self = [super init])) {
        atomic_init(&_state, state);
    }
    return self;
}

- (PMAPIManagerTaskStateBoxState)state {
    return atomic_load_explicit(&_state, memory_order_relaxed);
}

- (PMAPIManagerTaskStateBoxResult)transitionStateTo:(PMAPIManagerTaskStateBoxState)newState {
    switch (newState) {
        case PMAPIManagerTaskStateBoxStateRunning: {
            // we can't transition here from anywhere
            PMAPIManagerTaskStateBoxState current = atomic_load_explicit(&_state, memory_order_relaxed);
            return (PMAPIManagerTaskStateBoxResult){current == newState, current};
        }
        case PMAPIManagerTaskStateBoxStateProcessing: {
            // we can only transition here from Running
            PMAPIManagerTaskStateBoxState expected = PMAPIManagerTaskStateBoxStateRunning;
            _Bool success = atomic_compare_exchange_strong_explicit(&_state, &expected, newState, memory_order_relaxed, memory_order_relaxed);
            return (PMAPIManagerTaskStateBoxResult){success || expected == newState, expected};
        }
        case PMAPIManagerTaskStateBoxStateCanceled: {
            // transition from Running or Processing
            PMAPIManagerTaskStateBoxState expected = PMAPIManagerTaskStateBoxStateRunning;
            while (1) {
                if (atomic_compare_exchange_weak_explicit(&_state, &expected, newState, memory_order_relaxed, memory_order_relaxed)) {
                    return (PMAPIManagerTaskStateBoxResult){true, expected};
                }
                switch (expected) {
                    case PMAPIManagerTaskStateBoxStateRunning:
                    case PMAPIManagerTaskStateBoxStateProcessing:
                        break;
                    case PMAPIManagerTaskStateBoxStateCanceled:
                        return (PMAPIManagerTaskStateBoxResult){true, expected};
                    case PMAPIManagerTaskStateBoxStateCompleted:
                        return (PMAPIManagerTaskStateBoxResult){false, expected};
                }
            }
        }
        case PMAPIManagerTaskStateBoxStateCompleted: {
            // we can transition only from Processing
            PMAPIManagerTaskStateBoxState expected = PMAPIManagerTaskStateBoxStateProcessing;
            _Bool success = atomic_compare_exchange_strong_explicit(&_state, &expected, newState, memory_order_relaxed, memory_order_relaxed);
            return (PMAPIManagerTaskStateBoxResult){success || expected == newState, expected};
        }
    }
}
@end
