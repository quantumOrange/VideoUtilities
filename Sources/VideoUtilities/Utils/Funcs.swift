//
//  File.swift
//  
//
//  Created by David Crooks on 07/02/2022.
//

import Foundation
import CoreImage
import VideoToolbox

public func createCGImage(pixelBuffer:CVPixelBuffer) ->  CGImage? {
    /*
    guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess
        else {
            return nil
    }
    */
    
    var newImage: CGImage?

    // Create a Core Graphics bitmap image from the pixel buffer.
    VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &newImage)

    // Release the image buffer.
    // CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    
    return newImage
}
