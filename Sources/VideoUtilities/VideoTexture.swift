//
//  VideoTexture.swift
//  VideoUtilities
//
//  Created by David Crooks on 20/07/2025.
//

import AVFoundation
import Metal
import MetalKit

public class VideoTexture {
    let url: URL
    private let playerItem: AVPlayerItem
    private let videoOutput: AVPlayerItemVideoOutput
    private var textureCache: CVMetalTextureCache?
    private let device: MTLDevice
    
    public init?(url: URL, device: MTLDevice) {
        self.url = url
        self.device = device
        
        // Set up AVPlayerItem
        let asset = AVAsset(url: url)
        self.playerItem = AVPlayerItem(asset: asset)
        
        // Pixel buffer attributes
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        
        // Set up AVPlayerItemVideoOutput
        self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        self.playerItem.add(self.videoOutput)
        
        // Set up Metal texture cache
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess else {
            return nil
        }
        self.textureCache = cache
    }

    public func texture(at time: CMTime) -> MTLTexture? {
        guard let textureCache = textureCache else { return nil }

        // Ensure the output has the frame for the requested time
        if videoOutput.hasNewPixelBuffer(forItemTime: time),
           let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {

            var cvTextureOut: CVMetalTexture?
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            
            let status = CVMetalTextureCacheCreateTextureFromImage(
                nil,
                textureCache,
                pixelBuffer,
                nil,
                .bgra8Unorm,
                width,
                height,
                0,
                &cvTextureOut
            )

            if status == kCVReturnSuccess, let cvTexture = cvTextureOut {
                return CVMetalTextureGetTexture(cvTexture)
            }
        }
        return nil
    }
}
