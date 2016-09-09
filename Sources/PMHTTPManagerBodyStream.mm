//
//  PMHTTPManagerBodyStream.mm
//  PMHTTP
//
//  Created by Kevin Ballard on 5/3/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

#import "PMHTTPManagerBodyStream.h"
#import <atomic>
#import <mutex>
#import <map>

// Historically, subclassing NSInputStream has required overriding a handful of private undocumented methods.
// I can't find any reference saying that this has been fixed, but, experimentally, as of iOS 8.1 at least
// these undocumented methods are no longer invoked by the URL loading system. I haven't tested iOS 8.0 (since
// no simulator for that exists for Xcode 7.3) and I haven't tested OS X 10.10 (though it should have the same
// behavior as iOS 8), but this behavioral change is unlikely to have happened in a minor release. I also
// haven't tested any older OSes as PMHTTP requires iOS 8.0 / OS X 10.10 or higher.

@interface NSInputStream ()
// We have to declare a designated initializer for the stream since it doesn't declare -init as designated
// (but we can't use any of the existing designated initializers).
- (nonnull instancetype)init NS_DESIGNATED_INITIALIZER;
@end

@interface _PMHTTPManagerBodyStream () <NSStreamDelegate>
- (nonnull instancetype)init NS_UNAVAILABLE;
@end

/// Wrapper around a CF type that automatically retains/releases it.
template<class T> struct CF {
private:
    T _value;
    
public:
    CF(T value) : _value(value) {
        if (_value) CFRetain(_value);
    }
    CF(const CF<T>& other) : _value(other._value) {
        if (_value) CFRetain(_value);
    }
    CF(CF<T>&& other) : _value(std::move(other._value)) {
        other._value = nullptr;
    }
    CF<T>& operator=(const CF<T>& other) {
        _value = other._value;
        if (_value) CFRetain(_value);
    }
    CF<T>& operator=(CF<T>&& other) {
        _value = std::move(other._value);
        other._value = nullptr;
    }
    ~CF() {
        if (_value) CFRelease(_value);
    }
    const T& operator*() const {
        return _value;
    }
    bool operator<(const CF<T>& other) const {
        return _value < other._value;
    }
};

@implementation _PMHTTPManagerBodyStream {
    std::atomic<NSStreamStatus> _streamStatus;
    std::atomic<void *> _delegate;
    std::atomic<NSStreamStatus> _lastStatus;
    
    std::mutex _mutex;
    NSInteger (^ _Nullable _handler)(uint8_t * _Nonnull buffer, NSInteger maxLength);
    std::map<CF<CFRunLoopRef>, NSMutableSet<NSString *> * _Nonnull> _runLoops;
    CFRunLoopSourceRef _Nullable _rlSource;
}

- (instancetype)initWithHandler:(NSInteger (^)(uint8_t * _Nonnull buffer, NSInteger maxLength))handler {
    if ((self = [super init])) {
        _handler = [handler copy];
        atomic_init(&_streamStatus, NSStreamStatusNotOpen);
        atomic_init(&_delegate, (void *)nullptr);
        atomic_init(&_lastStatus, NSStreamStatusNotOpen);
    }
    return self;
}

- (instancetype)init {
    // For some reason clang insists on us implementing -init or it'll emit a warning.
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"-[_PMHTTPManagerBodyStream init] is not available; use -initWithHandler:" userInfo:nil];
}

- (id<NSStreamDelegate>)delegate {
    return (__bridge id<NSStreamDelegate>)_delegate.load(std::memory_order_relaxed) ?: self;
}

- (void)setDelegate:(id<NSStreamDelegate>)delegate {
    _delegate.store((__bridge void *)delegate, std::memory_order_relaxed);
}

- (NSStreamStatus)streamStatus {
    return _streamStatus.load(std::memory_order_relaxed);
}

- (void)open {
    NSStreamStatus status = NSStreamStatusNotOpen;
    if (_streamStatus.compare_exchange_strong(status, NSStreamStatusOpen, std::memory_order_relaxed)) {
        [self signalSource];
    }
}

- (void)close {
    NSStreamStatus status = NSStreamStatusOpen;
    while (1) {
        if (_streamStatus.compare_exchange_weak(status, NSStreamStatusClosed, std::memory_order_relaxed)) {
            // Don't signal the source here since we don't send events for this.
            break;
        } else if (status == NSStreamStatusClosed) {
            // someone else closed us, so we can skip the unregistering portion as well
            return;
        }
    }
    std::lock_guard<std::mutex> lock(_mutex);
    if (_rlSource) {
        CFRunLoopSourceInvalidate(_rlSource);
        CFRelease(_rlSource);
        _rlSource = nullptr;
    }
    _runLoops.clear();
    _handler = nil;
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)maxLength {
    NSStreamStatus status = _streamStatus.load(std::memory_order_relaxed);
    switch (status) {
        case NSStreamStatusOpen:
        case NSStreamStatusReading: break;
        case NSStreamStatusAtEnd: return 0;
        default: return -1;
    }
    if (maxLength <= 0) return -1;
    if (maxLength > (NSUInteger)NSIntegerMax) {
        // this really shoudn't happen
        maxLength = NSIntegerMax;
    }
    NSUInteger totalLen = 0;
    bool shouldSignal = false;
    {
        std::lock_guard<std::mutex> lock(_mutex);
        while (maxLength > totalLen && _handler != nil) {
            NSInteger len = _handler(&buffer[totalLen], maxLength - totalLen);
            if (len <= 0) {
                _handler = nil;
                break;
            }
            totalLen += len;
        }
        if (!_handler) {
            while (status == NSStreamStatusOpen || status == NSStreamStatusReading) {
                if (_streamStatus.compare_exchange_weak(status, NSStreamStatusAtEnd, std::memory_order_relaxed)) {
                    shouldSignal = true;
                    break;
                }
            }
        }
    }
    if (shouldSignal) {
        [self signalSource];
    }
    return totalLen;
}

- (BOOL)getBuffer:(uint8_t * _Nullable *)buffer length:(NSUInteger *)len {
    return NO;
}

- (BOOL)hasBytesAvailable {
    switch (_streamStatus.load(std::memory_order_relaxed)) {
        case NSStreamStatusOpen:
        case NSStreamStatusReading: {
            return YES;
        }
        default:
            return NO;
    }
}

- (id)propertyForKey:(NSStreamPropertyKey)key {
    return nil;
}

- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key {
    return NO;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    if (_streamStatus.load(std::memory_order_relaxed) == NSStreamStatusClosed) {
        // We can't be scheduled while closed
        return;
    }
    std::lock_guard<std::mutex> lock(_mutex);
    if (!_rlSource) {
        CFRunLoopSourceContext ctxt = {
            .version = 0,
            .info = (__bridge void *)self,
            .retain = CFRetain,
            .release = CFRelease,
            .perform = [](void *info){
                auto stream = (__bridge _PMHTTPManagerBodyStream *)(info);
                auto delegate = stream.delegate;
                if (![delegate respondsToSelector:@selector(stream:handleEvent:)]) return;
                auto status = stream->_streamStatus.load(std::memory_order_relaxed);
                auto lastStatus = stream->_lastStatus.exchange(status, std::memory_order_relaxed);
                NSStreamEvent events = NSStreamEventNone;
                switch (status) {
                    case NSStreamStatusClosed:
                        // once we're closed we have no more events
                        break;
                    case NSStreamStatusError:
                        if (lastStatus != NSStreamStatusError) events = NSStreamEventErrorOccurred;
                        break;
                    case NSStreamStatusAtEnd:
                        switch (lastStatus) {
                            case NSStreamStatusNotOpen:
                            case NSStreamStatusOpening:
                                events = NSStreamEventOpenCompleted;
                                [[clang::fallthrough]];
                            case NSStreamStatusOpen:
                            case NSStreamStatusReading:
                                events |= NSStreamEventEndEncountered;
                                break;
                            default: break;
                        }
                    case NSStreamStatusOpen:
                    case NSStreamStatusReading:
                        switch (lastStatus) {
                            case NSStreamStatusNotOpen:
                            case NSStreamStatusOpening:
                                // signal both open completed and has bytes
                                // since we always have bytes until we hit EOF we never have to signal it a second time
                                // this matches observed behavior of +[NSInputStream inputStreamWithData:]
                                events = NSStreamEventOpenCompleted | NSStreamEventHasBytesAvailable;
                                break;
                            default: break;
                        }
                    case NSStreamStatusNotOpen:
                    case NSStreamStatusOpening:
                    case NSStreamStatusWriting:
                        break;
                }
                if (events != NSStreamEventNone) {
                    [delegate stream:stream handleEvent:events];
                }
            }
        };
        _rlSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &ctxt);
    }
    auto cfRunLoop = [aRunLoop getCFRunLoop];
    auto it = _runLoops.find(cfRunLoop);
    if (it == _runLoops.end()) {
        CFRetain(cfRunLoop);
        it = _runLoops.emplace(cfRunLoop, [NSMutableSet set]).first;
    }
    if (![it->second containsObject:mode]) {
        [it->second addObject:mode];
        CFRunLoopAddSource([aRunLoop getCFRunLoop], _rlSource, (__bridge CFStringRef)mode);
    }
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_rlSource) {
        auto cfRunLoop = [aRunLoop getCFRunLoop];
        auto it = _runLoops.find(cfRunLoop);
        if (it != _runLoops.end()) {
            [it->second removeObject:mode];
            CFRunLoopRemoveSource([aRunLoop getCFRunLoop], _rlSource, (__bridge CFStringRef)mode);
            if ([it->second count] == 0) {
                _runLoops.erase(it);
            }
        }
        if (_runLoops.cbegin() == _runLoops.cend()) {
            // we've emptied out the run loops, so we need to discard the source as well or we'll have an infinite loop
            CFRunLoopSourceInvalidate(_rlSource);
            CFRelease(_rlSource);
            _rlSource = nullptr;
        }
    }
}

- (void)signalSource {
    std::lock_guard<std::mutex> lock(_mutex);
    if (!_rlSource) return;
    CFRunLoopSourceSignal(_rlSource);
    auto cfRunLoop = [[NSRunLoop currentRunLoop] getCFRunLoop];
    if (auto currentMode = (__bridge_transfer NSString *)CFRunLoopCopyCurrentMode(cfRunLoop)) {
        auto it = _runLoops.find(cfRunLoop);
        if (it == _runLoops.end() || ![it->second containsObject:currentMode]) {
            // the source isn't scheduled on the current mode of the current run loop
            cfRunLoop = nullptr;
        }
    }
    if (!cfRunLoop) {
        // find the first runloop that's waiting in the correct mode
        for (const auto& pair : _runLoops) {
            if (auto currentMode = (__bridge_transfer NSString *)CFRunLoopCopyCurrentMode(*pair.first)) {
                if ([pair.second containsObject:currentMode] && CFRunLoopIsWaiting(*pair.first)) {
                    cfRunLoop = *pair.first;
                    break;
                }
            }
        }
    }
    if (!cfRunLoop) {
        // We couldn't find any good runloops, so just go with the first one
        auto it = _runLoops.cbegin();
        if (it != _runLoops.cend()) {
            cfRunLoop = *it->first;
        }
    }
    if (cfRunLoop) {
        CFRunLoopWakeUp(cfRunLoop);
    }
}
@end
