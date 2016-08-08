//
//  PMHTTPError.m
//  PMHTTP
//
//  Created by Kevin Ballard on 1/19/16.
//  Copyright © 2016 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

#import "PMHTTPError.h"

NSString * const PMHTTPErrorDomain = @"PMHTTP.HTTPManagerError";

NSString * const PMHTTPStatusCodeErrorKey = @"statusCode";
NSString * const PMHTTPURLResponseErrorKey = @"response";
NSString * const PMHTTPBodyDataErrorKey = @"body";
NSString * const PMHTTPBodyJSONErrorKey = @"json";
NSString * const PMHTTPCredentialErrorKey = @"credential";
NSString * const PMHTTPContentTypeErrorKey = @"contentType";
NSString * const PMHTTPLocationErrorKey = @"location";
