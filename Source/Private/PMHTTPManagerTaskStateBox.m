//
//  PMHTTPManagerTaskStateBox.m
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 1/5/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

#import "PMHTTPManagerTaskStateBox.h"
#import <stdatomic.h>

@implementation PMHTTPManagerTaskStateBox {
    atomic_uchar _state;
}

- (nonnull instancetype)initWithState:(PMHTTPManagerTaskStateBoxState)state {
    if ((self = [super init])) {
        atomic_init(&_state, state);
    }
    return self;
}

- (PMHTTPManagerTaskStateBoxState)state {
    return atomic_load_explicit(&_state, memory_order_relaxed);
}

- (PMHTTPManagerTaskStateBoxResult)transitionStateTo:(PMHTTPManagerTaskStateBoxState)newState {
    switch (newState) {
        case PMHTTPManagerTaskStateBoxStateRunning: {
            // we can't transition here from anywhere
            PMHTTPManagerTaskStateBoxState current = atomic_load_explicit(&_state, memory_order_relaxed);
            return (PMHTTPManagerTaskStateBoxResult){current == newState, current};
        }
        case PMHTTPManagerTaskStateBoxStateProcessing: {
            // we can only transition here from Running
            PMHTTPManagerTaskStateBoxState expected = PMHTTPManagerTaskStateBoxStateRunning;
            _Bool success = atomic_compare_exchange_strong_explicit(&_state, &expected, newState, memory_order_relaxed, memory_order_relaxed);
            return (PMHTTPManagerTaskStateBoxResult){success || expected == newState, expected};
        }
        case PMHTTPManagerTaskStateBoxStateCanceled: {
            // transition from Running or Processing
            PMHTTPManagerTaskStateBoxState expected = PMHTTPManagerTaskStateBoxStateRunning;
            while (1) {
                if (atomic_compare_exchange_weak_explicit(&_state, &expected, newState, memory_order_relaxed, memory_order_relaxed)) {
                    return (PMHTTPManagerTaskStateBoxResult){true, expected};
                }
                switch (expected) {
                    case PMHTTPManagerTaskStateBoxStateRunning:
                    case PMHTTPManagerTaskStateBoxStateProcessing:
                        break;
                    case PMHTTPManagerTaskStateBoxStateCanceled:
                        return (PMHTTPManagerTaskStateBoxResult){true, expected};
                    case PMHTTPManagerTaskStateBoxStateCompleted:
                        return (PMHTTPManagerTaskStateBoxResult){false, expected};
                }
            }
        }
        case PMHTTPManagerTaskStateBoxStateCompleted: {
            // we can transition only from Processing
            PMHTTPManagerTaskStateBoxState expected = PMHTTPManagerTaskStateBoxStateProcessing;
            _Bool success = atomic_compare_exchange_strong_explicit(&_state, &expected, newState, memory_order_relaxed, memory_order_relaxed);
            return (PMHTTPManagerTaskStateBoxResult){success || expected == newState, expected};
        }
    }
}
@end
