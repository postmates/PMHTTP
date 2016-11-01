//
//  PMHTTPError.h
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

@import Foundation;

/// Error domain for \c HTTPManager errors.
extern NSString * const PMHTTPErrorDomain;

/// Error codes for \c HTTPManager errors.
typedef NS_ENUM(NSInteger, PMHTTPError) {
    /// An HTTP response was returned that indicates failure.
    /// @see <tt>PMHTTPStatusCodeErrorKey</tt>, <tt>PMHTTPURLResponseErrorKey</tt>, <tt>PMHTTPBodyDataErrorKey</tt>, <tt>PMHTTPBodyJSONErrorKey</tt>.
    PMHTTPErrorFailedResponse = 1,
    /// A 401 Unauthorized HTTP response was returned.
    /// @see <tt>PMHTTPCredentialErrorKey</tt>, <tt>PMHTTPURLResponseErrorKey</tt>, <tt>PMHTTPBodyDataErrorKey</tt>, <tt>PMHTTPBodyJSONErrorKey</tt>.
    PMHTTPErrorUnauthorized,
    /// An HTTP response was returned that had an incorrect Content-Type header.
    /// @see <tt>PMHTTPContentTypeErrorKey</tt>, <tt>PMHTTPURLResponseErrorKey</tt>, <tt>PMHTTPBodyDataErrorKey</tt>
    PMHTTPErrorUnexpectedContentType,
    /// An HTTP response returned a 204 No Content where an entity was expected.
    /// @see <tt>PMHTTPURLResponseErrorKey</tt>.
    PMHTTPErrorUnexpectedNoContent,
    /// A redirect was encountered while trying to parse a response that has redirects disabled.
    /// @see <tt>PMHTTPStatusCodeErrorKey</tt>, <tt>PMHTTPLocationErrorKey</tt>, <tt>PMHTTPURLResponseErrorKey</tt>, <tt>PMHTTPBodyDataErrorKey</tt>.
    PMHTTPErrorUnexpectedRedirect
};

// User info keys

/// The corresponding value is an \c NSNumber with the status code of the response.
/// @see <tt>PMHTTPErrorFailedResponse</tt>, <tt>PMHTTPErrorUnexpectedRedirect</tt>.
extern NSString * const PMHTTPStatusCodeErrorKey;
/// The corresponding value is the \c NSHTTPURLResponse that represents the response.
/// This key is provided for all errors in the <tt>PMHTTPErrorDomain</tt> domain.
/// @see <tt>PMHTTPError</tt>.
extern NSString * const PMHTTPURLResponseErrorKey;
/// The corresponding value is a \c NSData with the body of the response.
/// @see <tt>PMHTTPErrorFailedResponse</tt>, <tt>PMHTTPErrorUnexpectedContentType</tt>, <tt>PMHTTPErrorUnexpectedRedirect</tt>.
extern NSString * const PMHTTPBodyDataErrorKey;
/// The corresponding value is an \c NSDictionary with the body of the response decoded as JSON.
/// This key may not be present if the response \c Content-Type is not <tt>application/json</tt> or <tt>text/json</tt>,
/// if the JSON decode fails, or if the JSON top-level value is not an object.
/// The dictionary does not include any \c NSNull values.
/// @see <tt>PMHTTPErrorFailedResponse</tt>.
extern NSString * const PMHTTPBodyJSONErrorKey;
/// The corresponding value is the \c NSURLCredential that was used in the request, if any.
/// @see <tt>PMHTTPErrorUnauthorized</tt>.
extern NSString * const PMHTTPCredentialErrorKey;
/// The corresponding value is a \c NSString with the Content-Type of the response.
/// @see <tt>PMHTTPErrorUnexpectedContentType</tt>.
extern NSString * const PMHTTPContentTypeErrorKey;
/// The corresponding value is an \c NSURL with the Location of the response. May be \c nil.
/// @see <tt>PMHTTPErrorUnexpectedRedirect</tt>.
extern NSString * const PMHTTPLocationErrorKey;
