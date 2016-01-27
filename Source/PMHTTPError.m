//
//  PMHTTPError.m
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 1/19/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

#import "PMHTTPError.h"

NSString * const PMHTTPErrorDomain = @"PMHTTP.HTTPManagerError";

NSString * const PMHTTPStatusCodeErrorKey = @"statusCode";
NSString * const PMHTTPURLResponseErrorKey = @"response";
NSString * const PMHTTPBodyDataErrorKey = @"body";
NSString * const PMHTTPBodyJSONErrorKey = @"json";
NSString * const PMHTTPContentTypeErrorKey = @"contentType";
NSString * const PMHTTPLocationErrorKey = @"location";
