//
//  PlatformSpecific.swift
//  PMHTTP
//
//  Created by Kevin Ballard on 10/31/16.
//  Copyright © 2016 Postmates. All rights reserved.
//

import Foundation

#if os(iOS) || os(watchOS) || os(tvOS)
    
    import UIKit
#if os(watchOS)
    import WatchKit
#endif
    import ImageIO
    import MobileCoreServices
    
    // MARK: UIImage Support
    
    public extension HTTPManagerUploadFormRequest {
        /// Specifies a named multipart body for this request consisting of PNG data.
        ///
        /// The provided image is converted into PNG data asynchronously.
        ///
        /// Calling this method sets the request's overall Content-Type to
        /// `multipart/form-data`.
        ///
        /// - Note: In the unlikely event that PNG data cannot be generated for the image,
        ///   the multipart body will be omitted.
        ///
        /// - Bug: `name` and `filename` are assumed to be ASCII and not need any escaping.
        ///
        /// - Parameters:
        ///   - image: The image for the multipart.
        ///   - name: The name of the multipart body. This is the name the server expects.
        ///   - filename: The filename of the attachment. Optional.
        public func addMultipartPNG(for image: UIImage, withName name: String, filename: String? = nil) {
            self.addMultipartBody(using: { upload in
                guard let data = UIImagePNGRepresentation(image) else { return }
                upload.addMultipart(data: data, withName: name, mimeType: "image/png", filename: filename)
            })
        }
        
        /// Specifies a named multipart body for this request consisting of JPEG data.
        ///
        /// The provided image is converted into JPEG data asynchronously.
        ///
        /// Calling this method sets the request's overall Content-Type to
        /// `multipart/form-data`.
        ///
        /// - Note: In the unlikely event that JPEG data cannot be generated for the image,
        ///   the multipart body will be omitted.
        ///
        /// - Bug: `name` and `filename` are assumed to be ASCII and not need any escaping.
        ///
        /// - Parameters:
        ///   - image: The image for the multipart.
        ///   - compressionQuality: The quality of the resulting JPEG image, expressed as a value
        ///     from `0.0` to `1.0`.
        ///   - name: The name of the multipart body. This is the name the server expects.
        ///   - filename: The filename of the attachment. Optional.
        public func addMultipartJPEG(for image: UIImage, withCompressionQuality quality: CGFloat, name: String, filename: String? = nil) {
            self.addMultipartBody(using: { upload in
                guard let data = UIImageJPEGRepresentation(image, quality) else { return }
                upload.addMultipart(data: data, withName: name, mimeType: "image/jpeg", filename: filename)
            })
        }
    }
    
    @objc(PMHTTPImageError)
    public enum HTTPManagerImageError: Int, LocalizedError {
        /// The image returned by the server could not be decoded.
        case cannotDecode
        
        public var failureReason: String? {
            switch self {
            case .cannotDecode: return "The image could not be decoded."
            }
        }
    }
    
    public extension HTTPManagerDataRequest {
        /// Returns a new request that parses the data as an image.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: If the server responds with 204 No Content, the parse is skipped and
        ///   `HTTPManagerError.unexpectedNoContent` is returned as the parse result.
        /// - Parameter scale: The scale to use for the resulting image. Defaults to `1`.
        /// - Returns: An `HTTPManagerParseRequest`.
        public func parseAsImage(scale: CGFloat = 1) -> HTTPManagerParseRequest<UIImage> {
            let req = parse(using: { (response, data) -> UIImage in
                if let response = response as? HTTPURLResponse, response.statusCode == 204 {
                    throw HTTPManagerError.unexpectedNoContent(response: response)
                }
                guard let image = UIImage(data: data, scale: scale, mimeType: (response as? HTTPURLResponse)?.mimeType)
                    else { throw HTTPManagerImageError.cannotDecode }
                return image
            })
            req.expectedContentTypes = supportedImageMIMETypes
            return req
        }
        
        /// Returns a new request that parses the data as an image and passes it through the
        /// specified handler.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: If the server responds with 204 No Content, the parse is skipped and
        ///   `HTTPManagerError.unexpectedNoContent` is returned as the parse result.
        /// - Parameter scale: The scale to use for the resulting image. Defaults to `1`.
        /// - Parameter handler: The handler to call as part of the request processing. This handler
        ///   is not guaranteed to be called on any particular thread. The handler returns the new
        ///   value for the request.
        /// - Returns: An `HTTPManagerParseRequest`.
        /// - Note: If you need to parse on a particular thread, such as on the main thread, you
        ///   should use `performRequest(withCompletionQueue:completion:)` instead.
        /// - Warning: If the request is canceled, the results of the handler may be discarded. Any
        ///   side-effects performed by your handler must be safe in the event of a cancelation.
        /// - Warning: The parse request inherits the `isIdempotent` value of `self`. If the parse
        ///   handler has side effects and can throw, you should either ensure that it's safe to run
        ///   the parse handler again or set `isIdempotent` to `false`.
        public func parseAsImage<T>(scale: CGFloat = 1, using handler: @escaping (_ response: URLResponse, _ image: UIImage) throws -> T) -> HTTPManagerParseRequest<T> {
            let req = parse(using: { (response, data) -> T in
                if let response = response as? HTTPURLResponse, response.statusCode == 204 {
                    throw HTTPManagerError.unexpectedNoContent(response: response)
                }
                guard let image = UIImage(data: data, scale: scale, mimeType: (response as? HTTPURLResponse)?.mimeType)
                    else { throw HTTPManagerImageError.cannotDecode }
                return try handler(response, image)
            })
            req.expectedContentTypes = supportedImageMIMETypes
            return req
        }
        
        /// Returns a new request that parses the data as an image.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: If the server responds with 204 No Content, the parse is skipped and
        ///   `HTTPManagerError.unexpectedNoContent` is returned as the parse result.
        /// - Returns: An `HTTPManagerParseRequest`.
        @objc(parseAsImage)
        public func __objc_parseAsImage() -> HTTPManagerObjectParseRequest {
            return HTTPManagerObjectParseRequest(request: parseAsImage(using: { $1 }))
        }
        
        /// Returns a new request that parses the data as an image.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: If the server responds with 204 No Content, the parse is skipped and
        ///   `HTTPManagerError.unexpectedNoContent` is returned as the parse result.
        /// - Parameter scale: The scale to use for the resulting image.
        /// - Returns: An `HTTPManagerParseRequest`.
        @objc(parseAsImageWithScale:)
        public func __objc_parseAsImage(scale: CGFloat) -> HTTPManagerObjectParseRequest {
            return HTTPManagerObjectParseRequest(request: parseAsImage(scale: scale, using: { $1 }))
        }
        
        /// Returns a new request that parses the data as an image and passes it through the
        /// specified handler.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: If the server responds with 204 No Content, the parse is skipped and
        ///   `HTTPManagerError.unexpectedNoContent` is returned as the parse result.
        /// - Parameter handler: The handler to call as part of the request processing. This handler
        ///   is not guaranteed to be called on any particular thread. The handler returns the new
        ///   value for the request.
        /// - Returns: An `HTTPManagerParseRequest`.
        /// - Note: If you need to parse on a particular thread, such as on the main thread, you
        ///   should use `performRequest(withCompletionQueue:completion:)` instead.
        /// - Warning: If the request is canceled, the results of the handler may be discarded. Any
        ///   side-effects performed by your handler must be safe in the event of a cancelation.
        /// - Warning: The parse request inherits the `isIdempotent` value of `self`. If the parse
        ///   handler has side effects and can throw, you should either ensure that it's safe to run
        ///   the parse handler again or set `isIdempotent` to `false`.
        @objc(parseAsImageWithHandler:)
        public func __objc_parseAsImage(handler: @escaping @convention(block) (_ response: URLResponse, _ image: UIImage, _ error: AutoreleasingUnsafeMutablePointer<NSError?>) -> Any?) -> HTTPManagerObjectParseRequest {
            return __objc_parseAsImage(scale: 1, handler: handler)
        }
        
        /// Returns a new request that parses the data as an image and passes it through the
        /// specified handler.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: If the server responds with 204 No Content, the parse is skipped and
        ///   `HTTPManagerError.unexpectedNoContent` is returned as the parse result.
        /// - Parameter scale: The scale to use for the resulting image.
        /// - Parameter handler: The handler to call as part of the request processing. This handler
        ///   is not guaranteed to be called on any particular thread. The handler returns the new
        ///   value for the request.
        /// - Returns: An `HTTPManagerParseRequest`.
        /// - Note: If you need to parse on a particular thread, such as on the main thread, you
        ///   should use `performRequest(withCompletionQueue:completion:)` instead.
        /// - Warning: If the request is canceled, the results of the handler may be discarded. Any
        ///   side-effects performed by your handler must be safe in the event of a cancelation.
        /// - Warning: The parse request inherits the `isIdempotent` value of `self`. If the parse
        ///   handler has side effects and can throw, you should either ensure that it's safe to run
        ///   the parse handler again or set `isIdempotent` to `false`.
        @objc(parseAsImageWithScale:handler:)
        public func __objc_parseAsImage(scale: CGFloat, handler: @escaping @convention(block) (_ response: URLResponse, _ image: UIImage, _ error: AutoreleasingUnsafeMutablePointer<NSError?>) -> Any?) -> HTTPManagerObjectParseRequest {
            return HTTPManagerObjectParseRequest(request: parseAsImage(scale: scale, using: { (response, image) in
                var error: NSError?
                if let value = handler(response, image, &error) {
                    return value
                } else if let error = error {
                    throw error
                } else {
                    return nil
                }
            }))
        }
    }
    
    public extension HTTPManagerActionRequest {
        /// Returns a new request that parses the data as an image.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: The parse result is `nil` if and only if the server responded with 204 No
        ///   Content.
        /// - Parameter scale: The scale to use for the resulting image. Defaults to `1`.
        /// - Returns: An `HTTPManagerParseRequest`.
        public func parseAsImage(scale: CGFloat = 1) -> HTTPManagerParseRequest<UIImage?> {
            let req = parse(using: { (response, data) -> UIImage? in
                if let response = response as? HTTPURLResponse, response.statusCode == 204 {
                    // No Content
                    return nil
                }
                guard let image = UIImage(data: data, scale: scale, mimeType: (response as? HTTPURLResponse)?.mimeType)
                    else { throw HTTPManagerImageError.cannotDecode }
                return image
            })
            req.expectedContentTypes = supportedImageMIMETypes
            return req
        }
        
        /// Returns a new request that parses the data as an image and passes it through the
        /// specified handler.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: The parse result is `nil` if and only if the server responded with 204 No
        ///   Content and the `response` argument is guaranteed to be an instance of
        ///   `HTTPURLResponse`.
        /// - Parameter scale: The scale to use for the resulting image. Defaults to `1`.
        /// - Parameter handler: The handler to call as part of the request processing. This handler
        ///   is not guaranteed to be called on any particular thread. The handler returns the new
        ///   value for the request.
        /// - Returns: An `HTTPManagerParseRequest`.
        /// - Note: If you need to parse on a particular thread, such as on the main thread, you
        ///   should use `performRequest(withCompletionQueue:completion:)` instead.
        /// - Warning: If the request is canceled, the results of the handler may be discarded. Any
        ///   side-effects performed by your handler must be safe in the event of a cancelation.
        /// - Warning: The parse request inherits the `isIdempotent` value of `self`. If the parse
        ///   handler has side effects and can throw, you should either ensure that it's safe to run
        ///   the parse handler again or set `isIdempotent` to `false`.
        public func parseAsImage<T>(scale: CGFloat = 1, using handler: @escaping (_ response: URLResponse, _ image: UIImage?) throws -> T) -> HTTPManagerParseRequest<T> {
            let req = parse(using: { (response, data) -> T in
                if let response = response as? HTTPURLResponse, response.statusCode == 204 {
                    // No Content
                    return try handler(response, nil)
                }
                guard let image = UIImage(data: data, scale: scale, mimeType: (response as? HTTPURLResponse)?.mimeType)
                    else { throw HTTPManagerImageError.cannotDecode }
                return try handler(response, image)
            })
            req.expectedContentTypes = supportedImageMIMETypes
            return req
        }
        
        /// Returns a new request that parses the data as an image.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: If the parse result is `nil`, this means the server responded with 204 No
        ///   Content and the `response` argument is guaranteed to be an instance of
        ///   `NSHTTPURLResponse`.
        /// - Returns: An `HTTPManagerParseRequest`.
        @objc(parseAsImage)
        public func __objc_parseAsImage() -> HTTPManagerObjectParseRequest {
            return HTTPManagerObjectParseRequest(request: parseAsImage(using: { $1 }))
        }
        
        /// Returns a new request that parses the data as an image.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: If the parse result is `nil`, this means the server responded with 204 No
        ///   Content and the `response` argument is guaranteed to be an instance of
        ///   `NSHTTPURLResponse`.
        /// - Parameter scale: The scale to use for the resulting image.
        /// - Returns: An `HTTPManagerParseRequest`.
        @objc(parseAsImageWithScale:)
        public func __objc_parseAsImage(scale: CGFloat) -> HTTPManagerObjectParseRequest {
            return HTTPManagerObjectParseRequest(request: parseAsImage(scale: scale, using: { $1 }))
        }
        
        /// Returns a new request that parses the data as an image and passes it through the
        /// specified handler.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: If the `value` argument to the handler is `nil`, this means the server responded
        ///   with 204 No Content and the `response` argument is guaranteed to be an instance of
        ///   `NSHTTPURLResponse`.
        /// - Parameter handler: The handler to call as part of the request processing. This handler
        ///   is not guaranteed to be called on any particular thread. The handler returns the new
        ///   value for the request.
        /// - Returns: An `HTTPManagerParseRequest`.
        /// - Note: If you need to parse on a particular thread, such as on the main thread, you
        ///   should use `performRequest(withCompletionQueue:completion:)` instead.
        /// - Warning: If the request is canceled, the results of the handler may be discarded. Any
        ///   side-effects performed by your handler must be safe in the event of a cancelation.
        /// - Warning: The parse request inherits the `isIdempotent` value of `self`. If the parse
        ///   handler has side effects and can throw, you should either ensure that it's safe to run
        ///   the parse handler again or set `isIdempotent` to `false`.
        @objc(parseAsImageWithHandler:)
        public func __objc_parseAsImage(handler: @escaping @convention(block) (_ response: URLResponse, _ image: UIImage?, _ error: AutoreleasingUnsafeMutablePointer<NSError?>) -> Any?) -> HTTPManagerObjectParseRequest {
            return __objc_parseAsImage(scale: 1, handler: handler)
        }
        
        /// Returns a new request that parses the data as an image and passes it through the
        /// specified handler.
        ///
        /// If the image container has multiple images, only the first one is returned.
        ///
        /// - Note: If the `value` argument to the handler is `nil`, this means the server responded
        ///   with 204 No Content and the `response` argument is guaranteed to be an instance of
        ///   `NSHTTPURLResponse`.
        /// - Parameter scale: The scale to use for the resulting image.
        /// - Parameter handler: The handler to call as part of the request processing. This handler
        ///   is not guaranteed to be called on any particular thread. The handler returns the new
        ///   value for the request.
        /// - Returns: An `HTTPManagerParseRequest`.
        /// - Note: If you need to parse on a particular thread, such as on the main thread, you
        ///   should use `performRequest(withCompletionQueue:completion:)` instead.
        /// - Warning: If the request is canceled, the results of the handler may be discarded. Any
        ///   side-effects performed by your handler must be safe in the event of a cancelation.
        /// - Warning: The parse request inherits the `isIdempotent` value of `self`. If the parse
        ///   handler has side effects and can throw, you should either ensure that it's safe to run
        ///   the parse handler again or set `isIdempotent` to `false`.
        @objc(parseAsImageWithScale:handler:)
        public func __objc_parseAsImage(scale: CGFloat, handler: @escaping @convention(block) (_ response: URLResponse, _ image: UIImage?, _ error: AutoreleasingUnsafeMutablePointer<NSError?>) -> Any?) -> HTTPManagerObjectParseRequest {
            return HTTPManagerObjectParseRequest(request: parseAsImage(scale: scale, using: { (response, image) in
                var error: NSError?
                if let value = handler(response, image, &error) {
                    return value
                } else if let error = error {
                    throw error
                } else {
                    return nil
                }
            }))
        }
    }
    
    private let supportedImageMIMETypes: [String] = {
        let utis = CGImageSourceCopyTypeIdentifiers() as! [CFString]
        return utis.flatMap({ (UTTypeCopyAllTagsWithClass($0, kUTTagClassMIMEType)?.takeRetainedValue() as? [String]) ?? [] })
    }()
    
    private extension UIImage {
        convenience init?(data: Data, scale: CGFloat, mimeType: String?) {
            // Use CGImageSource so we can provide the MIME type hint.
            // NB: CGImageSource will cache the decoded image data by default on 64-bit platforms.
            let options: NSDictionary?
            if let mimeType = mimeType {
                options = [kCGImageSourceTypeIdentifierHint: mimeType as CFString]
            } else {
                options = nil
            }
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, options),
                CGImageSourceGetCount(imageSource) >= 1,
                let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
                else { return nil }
            let imageProps = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as NSDictionary?
            let exifOrientation = (imageProps?[kCGImagePropertyOrientation] as? NSNumber)?.intValue
            let orientation = exifOrientation.map(UIImageOrientation.init(exifOrientation:)) ?? .up
            self.init(cgImage: cgImage, scale: scale, orientation: orientation)
        }
    }
    
    private extension UIImageOrientation {
        init(exifOrientation orientation: Int) {
            switch orientation {
            case 1: self = .up
            case 2: self = .upMirrored
            case 3: self = .down
            case 4: self = .downMirrored
            case 5: self = .leftMirrored
            case 6: self = .right
            case 7: self = .rightMirrored
            case 8: self = .left
            default: self = .up
            }
        }
    }

#elseif os(macOS)
    
#endif
