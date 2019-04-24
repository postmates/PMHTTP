//
//  PMHTTPError.m
//  PMHTTP
//
//  Created by Lily Ballard on 1/19/16.
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
NSString * const PMHTTPAuthErrorKey = @"auth";
NSString * const PMHTTPContentTypeErrorKey = @"contentType";
NSString * const PMHTTPLocationErrorKey = @"location";

BOOL PMHTTPErrorIsFailedResponse(NSError * _Nullable error, NSInteger statusCode) {
    NSNumber *errorStatusCode = PMHTTPErrorGetStatusCode(error);
    return errorStatusCode && errorStatusCode.integerValue == statusCode;
}

NSNumber * _Nullable PMHTTPErrorGetStatusCode(NSError * _Nullable error) {
    if (![error.domain isEqualToString:PMHTTPErrorDomain]) return nil;
    switch ((PMHTTPError)error.code) {
        case PMHTTPErrorFailedResponse:
        case PMHTTPErrorUnexpectedRedirect: {
            NSNumber *errorStatusCode = error.userInfo[PMHTTPStatusCodeErrorKey];
            return [errorStatusCode isKindOfClass:[NSNumber class]] ? errorStatusCode : nil;
        }
        case PMHTTPErrorUnauthorized:
            // NB: Ignore PMHTTPStatusCodeErrorKey and just hardcode the status here, because there's only one valid code.
            // This protects us from hand-crafted `NSError`s that are missing the key.
            return @401;
        case PMHTTPErrorUnexpectedContentType:
            return nil;
        case PMHTTPErrorUnexpectedNoContent:
            // NB: See above regarding hardcoding the status code.
            return @204;
    }
    return nil;
}
