//
//  TexturePixelBufferAdaptor.swift
//  StopMotionPro
//
//  Created by David Crooks on 10/10/2024.
//

import Foundation
import AVFoundation
import Metal

class TexturePixelBufferAdaptor {
    
    private var device:MTLDevice!
    private var textureCache: CVMetalTextureCache!
    
    private var outputPixelBuffer: CVPixelBuffer?
    private let commandQueue:MTLCommandQueue
   
    init(commandQueue:MTLCommandQueue) {
        self.commandQueue = commandQueue
        self.device = commandQueue.device
        
        var metalTextureCache: CVMetalTextureCache?
        
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &metalTextureCache) != kCVReturnSuccess {
            assertionFailure("Unable to allocate texture cache")
        } else {
            textureCache = metalTextureCache
        }
    }
    

    func makeTexture(from pixelBuffer: CVPixelBuffer, textureFormat: MTLPixelFormat) -> MTLTexture? {
        
       
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Create a Metal texture from the image buffer.
        var cvTextureOut: CVMetalTexture?
        
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, textureFormat, width, height, 0, &cvTextureOut)
        
        guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
            CVMetalTextureCacheFlush(textureCache, 0)
            return nil
        }
        
        let targetTexture = makeTexture(width: texture.width, height: texture.height,pixelFormat: textureFormat)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()
            blitEncoder?.copy(from:texture, to: targetTexture)
            blitEncoder?.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            return targetTexture
        }
        return nil
    }
    
    var outputWidth:Int = -1
    var outputHeight:Int = -1
    
    public func prepare(width:Int, height:Int) {
        assert(width>0)
        assert(height>0)

        let options = [ kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue ]
        
        CVPixelBufferCreate(kCFAllocatorDefault,
                            width,
                            height,
                            kCVPixelFormatType_32BGRA,
                            options as CFDictionary,
                            &outputPixelBuffer)
        
        outputWidth = width
        outputHeight = height
    }
    
    enum TextureAdaptorError : Error {
        case notPrepared
        case noOutputPixelBuffer
        case noTextureCache
        case failedToCreateCVTexture
        case failedToCreateTargetTexture
        case texturePixelBufferSizeMismatch(Int,Int,Int,Int)
    }
    
    func makeCVPixelBuffer(from texture:MTLTexture) throws -> CVPixelBuffer {
        guard outputWidth>0 else { throw TextureAdaptorError.notPrepared }
        guard let pixelBuffer = outputPixelBuffer else { throw TextureAdaptorError.noOutputPixelBuffer }
        guard outputWidth == texture.width, outputHeight == texture.height else { throw TextureAdaptorError.texturePixelBufferSizeMismatch(outputWidth,outputHeight,texture.width,texture.height) }
        guard let textureCache = textureCache else { throw TextureAdaptorError.noTextureCache }
        
        var cvtexture: CVMetalTexture?
        
        _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, texture.pixelFormat, texture.width, texture.height, 0, &cvtexture)
        
        guard let cvtexture = cvtexture else { throw TextureAdaptorError.failedToCreateCVTexture}
        guard let targetTexture = CVMetalTextureGetTexture(cvtexture) else { throw TextureAdaptorError.failedToCreateTargetTexture }
    
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()
            blitEncoder?.copy(from:texture, to: targetTexture)
            blitEncoder?.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        return pixelBuffer
    }
    
    func makeTexture(width:Int,height:Int,pixelFormat:MTLPixelFormat) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:pixelFormat, width: width, height:height, mipmapped: false)
        
        descriptor.usage =   MTLTextureUsage(rawValue: MTLTextureUsage.shaderWrite.rawValue | MTLTextureUsage.shaderRead.rawValue)

        return device.makeTexture(descriptor: descriptor)!
    }
     
}
