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
