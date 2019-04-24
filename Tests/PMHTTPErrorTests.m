//
//  PMHTTPErrorTests.m
//  PMHTTPTests
//
//  Created by Lily Ballard on 3/20/19.
//  Copyright © 2019 Postmates.
//
//  Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
//  http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
//  <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
//  option. This file may not be copied, modified, or distributed
//  except according to those terms.
//

#import <XCTest/XCTest.h>
#import "PMHTTPTests-Swift.h"
@import PMHTTP;

@interface PMHTTPErrorTests : XCTestCase
@end

@implementation PMHTTPErrorTests

- (void)testPMHTTPErrorIsFailedResponse {
    // Use a dummy response for all errors. The status code of the response doesn't matter,
    // PMHTTPErrorIsFailedResponse looks at the error keys instead.
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://example.com"] statusCode:419 HTTPVersion:nil headerFields:nil];
    
    // failedResponse
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createFailedResponseErrorWithStatusCode:500 response:response body:[NSData data] bodyJson:nil], 500), @"failedResponse code 500");
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createFailedResponseErrorWithStatusCode:404 response:response body:[NSData data] bodyJson:nil], 404), @"failedResponse code 404");
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createFailedResponseErrorWithStatusCode:401 response:response body:[NSData data] bodyJson:nil], 401), @"failedResponse code 401");
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createFailedResponseErrorWithStatusCode:300 response:response body:[NSData data] bodyJson:nil], 300), @"failedResponse code 300");
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createFailedResponseErrorWithStatusCode:200 response:response body:[NSData data] bodyJson:nil], 200), @"failedResponse code 200");
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createFailedResponseErrorWithStatusCode:response.statusCode response:response body:[NSData data] bodyJson:nil], response.statusCode), @"failedResponse code %zd", response.statusCode);
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createFailedResponseErrorWithStatusCode:500 response:response body:[NSData data] bodyJson:nil], 404), @"failedResponse code 500");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createFailedResponseErrorWithStatusCode:500 response:response body:[NSData data] bodyJson:nil], 501), @"failedResponse code 500");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createFailedResponseErrorWithStatusCode:401 response:response body:[NSData data] bodyJson:nil], 404), @"failedResponse code 401");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createFailedResponseErrorWithStatusCode:401 response:response body:[NSData data] bodyJson:nil], response.statusCode), @"failedResponse code 401");
    
    // unauthorized
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnauthorizedErrorWith:nil response:response body:[NSData data] bodyJson:nil], 401), @"unauthorized");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnauthorizedErrorWith:nil response:response body:[NSData data] bodyJson:nil], 403), @"unauthorized");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnauthorizedErrorWith:nil response:response body:[NSData data] bodyJson:nil], response.statusCode), @"unauthorized");
    
    // unexpectedContentType
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedContentTypeErrorWithContentType:@"text/plain" response:response body:[NSData data]], 500), @"unexpectedContentType");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedContentTypeErrorWithContentType:@"text/plain" response:response body:[NSData data]], response.statusCode), @"unexpectedContentType");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedContentTypeErrorWithContentType:@"text/plain" response:response body:[NSData data]], 0), @"unexpectedContentType");
    
    // unexpectedNoContent
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedNoContentErrorWith:response], 204), @"unexpectedNoContent");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedNoContentErrorWith:response], 200), @"unexpectedNoContent");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedNoContentErrorWith:response], 404), @"unexpectedNoContent");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedNoContentErrorWith:response], response.statusCode), @"unexpectedNoContent");
    
    // unexpectedRedirect
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedRedirectErrorWithStatusCode:301 location:nil response:response body:[NSData data]], 301), @"unexpectedRedirect code 301");
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedRedirectErrorWithStatusCode:304 location:nil response:response body:[NSData data]], 304), @"unexpectedRedirect code 304");
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedRedirectErrorWithStatusCode:400 location:nil response:response body:[NSData data]], 400), @"unexpectedRedirect code 400");
    XCTAssert(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedRedirectErrorWithStatusCode:response.statusCode location:nil response:response body:[NSData data]], response.statusCode), @"unexpectedRedirect code %zd", response.statusCode);
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedRedirectErrorWithStatusCode:301 location:nil response:response body:[NSData data]], 304), @"unexpectedRedirect code 301");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedRedirectErrorWithStatusCode:304 location:nil response:response body:[NSData data]], 301), @"unexpectedRedirect code 304");
    XCTAssertFalse(PMHTTPErrorIsFailedResponse([ObjCTestSupport createUnexpectedRedirectErrorWithStatusCode:301 location:nil response:response body:[NSData data]], response.statusCode), @"unexpectedRedirect code 301");
    
    // Dummy error with the userInfo from a PMHTTP error
    NSError *dummyError = [NSError errorWithDomain:@"DummyErrorDomain" code:PMHTTPErrorFailedResponse
                                          userInfo:[ObjCTestSupport createFailedResponseErrorWithStatusCode:500 response:response body:[NSData data] bodyJson:nil].userInfo];
    XCTAssertFalse(PMHTTPErrorIsFailedResponse(dummyError, 500));
    XCTAssertFalse(PMHTTPErrorIsFailedResponse(dummyError, 419));
}

- (void)testPMHTTPErrorGetStatusCode {
    // Use a dummy response for all errors. The status code of the response doesn't matter,
    // PMHTTPErrorGetStatusCode looks at the error keys instead.
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://example.com"] statusCode:419 HTTPVersion:nil headerFields:nil];
    
    XCTAssertEqualObjects(PMHTTPErrorGetStatusCode([ObjCTestSupport createFailedResponseErrorWithStatusCode:500 response:response body:[NSData data] bodyJson:nil]), @500, @"failedResponse code 500");
    XCTAssertEqualObjects(PMHTTPErrorGetStatusCode([ObjCTestSupport createFailedResponseErrorWithStatusCode:404 response:response body:[NSData data] bodyJson:nil]), @404, @"failedResponse code 404");
    XCTAssertEqualObjects(PMHTTPErrorGetStatusCode([ObjCTestSupport createUnauthorizedErrorWith:nil response:response body:[NSData data] bodyJson:nil]), @401, @"unauthorized");
    XCTAssertNil(PMHTTPErrorGetStatusCode([ObjCTestSupport createUnexpectedContentTypeErrorWithContentType:@"text/plain" response:response body:[NSData data]]), @"unexpectedContentType");
    XCTAssertEqualObjects(PMHTTPErrorGetStatusCode([ObjCTestSupport createUnexpectedNoContentErrorWith:response]), @204, @"unexpectedNoContent");
    XCTAssertEqualObjects(PMHTTPErrorGetStatusCode([ObjCTestSupport createUnexpectedRedirectErrorWithStatusCode:301 location:nil response:response body:[NSData data]]), @301, @"unexpectedRedirect code 301");
    XCTAssertEqualObjects(PMHTTPErrorGetStatusCode([ObjCTestSupport createUnexpectedRedirectErrorWithStatusCode:304 location:nil response:response body:[NSData data]]), @304, @"unexpectedRedirect code 304");
}

@end
