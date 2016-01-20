//
//  PMAPIError.h
//  PostmatesNetworking
//
//  Created by Kevin Ballard on 1/19/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

@import Foundation;

/// Error domain for \c APIManager errors.
extern NSString * const PMAPIErrorDomain;

/// Error codes for \c APIManager errors.
typedef NS_ENUM(NSInteger, PMAPIError) {
    /// An HTTP response was returned that indicates failure.
    /// @see <tt>PMAPIStatusCodeErrorKey</tt>, <tt>PMAPIBodyDataErrorKey</tt>.
    PMAPIErrorFailedResponse = 1,
    /// An HTTP response was returned that had an incorrect Content-Type header.
    /// @see <tt>PMAPIContentTypeErrorKey</tt>, <tt>PMAPIBodyDataErrorKey</tt>
    PMAPIErrorUnexpectedContentType,
    /// An HTTP response returned a 204 No Content where an entity was expected.
    PMAPIErrorUnexpectedNoContent,
    /// A redirect was encountered while trying to parse a response that has redirects disabled.
    /// @see <tt>PMAPIStatusCodeErrorKey</tt>, <tt>PMAPILocationErrorKey</tt>, <tt>PMAPIBodyDataErrorKey</tt>.
    PMAPIErrorUnexpectedRedirect
};

// User info keys

/// The corresponding value is an \c NSNumber with the status code of the response.
extern NSString * const PMAPIStatusCodeErrorKey;
/// The corresponding value is a \c NSData with the body of the response.
extern NSString * const PMAPIBodyDataErrorKey;
/// The corresponding value is a \c NSString with the Content-Type of the response.
extern NSString * const PMAPIContentTypeErrorKey;
/// The corresponding value is an \c NSURL with the Location of the response. May be \c nil.
extern NSString * const PMAPILocationErrorKey;
