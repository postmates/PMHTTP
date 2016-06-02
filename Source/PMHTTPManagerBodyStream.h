//
//  PMHTTPManagerBodyStream.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A private implementation detail of PMHTTP. Do not use this class.
__attribute__((visibility("hidden")))
@interface _PMHTTPManagerBodyStream : NSInputStream
/// Returns a new \c _PMHTTPManagerBodyStream that uses a given handler to provide the data.
///
/// \param handler A handler function that is executed to fill a buffer. The handler must return
///        the number of bytes written. The handler returns \c 0 to indicate EOF, at which point
///        the handler is released. The handler will never be called with a value of \c 0 for
///        <code>maxLength</code>. The handler should not return a negative value.
- (instancetype)initWithHandler:(NSInteger (^)(uint8_t *buffer, NSInteger maxLength))handler NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithData:(NSData *)data NS_UNAVAILABLE;
- (nullable instancetype)initWithURL:(NSURL *)url NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
