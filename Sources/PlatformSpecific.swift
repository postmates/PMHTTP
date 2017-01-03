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

#elseif os(macOS)

#endif
