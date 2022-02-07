//
//  VideoRecorder.swift
//  SimpleMetalComputeExample
//
//  Created by David Crooks on 19/09/2021.
//

import Foundation
import AVFoundation
import Metal
import UIKit

public actor MetalVideoRecorder {
    
    private static let timescale = Int32(600)
    private var writer: AVAssetWriter
    private var input: AVAssetWriterInput
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var pixelBuffer: CVPixelBuffer?
    private var outputTextureCache: CVMetalTextureCache?
    private var output:URL

    private var size:CGSize;
    
    let semaphore = DispatchSemaphore(value: 1)
    
    let commandQueue: MTLCommandQueue
    
    public init?(size:CGSize, commandQueue:MTLCommandQueue,  output:URL? = nil){
        guard let output = output ?? Files.createVideosURL()  else { return nil }
        self.output = output
        self.commandQueue = commandQueue
        self.size = size
        
        let w = Int(size.width * 2)
        let h = Int(size.height * 2)
        
        try? FileManager.default.removeItem(at:output)
        
        guard let writer = try? AVAssetWriter(outputURL: output, fileType: AVFileType.mov) else { return nil }
        
        self.writer = writer
        
        input = AVAssetWriterInput(
            mediaType: AVMediaType.video,
            outputSettings: [
                AVVideoWidthKey: w,
                AVVideoHeightKey: h,
                AVVideoCodecKey: AVVideoCodecType.h264])
        
        input.expectsMediaDataInRealTime = true
        
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height])
        
        
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, commandQueue.device, nil, &outputTextureCache) == kCVReturnSuccess  else {
          return nil
        }
    
    }
    
    public func start() {
        
        let options = [ kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue ]
       
        CVPixelBufferCreate(kCFAllocatorDefault,
                            Int(size.width * 2),
                            Int(size.height * 2),
                            kCVPixelFormatType_32BGRA,
                            options as CFDictionary,
                            &pixelBuffer)
        
        let result = writer.startWriting()
        
        if !result {
            writer.printStatus()
            
            if writer.status == .failed, let error = writer.error {
                print(error)
            }
        }
        
        writer.startSession(atSourceTime: CMTime(seconds: ProcessInfo.processInfo.systemUptime, preferredTimescale: MetalVideoRecorder.timescale))
        
        writer.printStatus()
    }
    
    public func addFrame(texture:MTLTexture, timestamp: Double) {
        guard let pixelBuffer = pixelBuffer , let outputTextureCache = outputTextureCache else { return }
        
        var cvtexture: CVMetalTexture?
        
        _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, outputTextureCache, pixelBuffer, nil, .bgra8Unorm, texture.width, texture.height, 0, &cvtexture)
        
        guard let cvtexture = cvtexture,
              let targetTexture = CVMetalTextureGetTexture(cvtexture) else { return }
        
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            semaphore.wait()
            commandBuffer.addCompletedHandler { (_ commandBuffer) -> Void in
                self.adaptor.append(pixelBuffer, withPresentationTime: CMTime(seconds: timestamp, preferredTimescale: MetalVideoRecorder.timescale))
                self.semaphore.signal()
            }
            
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()
            blitEncoder?.copy(from:texture, to: targetTexture)
            blitEncoder?.endEncoding()
            
            commandBuffer.commit()
        }
    }
    
    public func finishWritingAndSaveToPhotos() async  -> Bool {
        let result =  await finishWritingVideo()
        
        switch result {
        case .success(let url):
            if UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path) {
                UISaveVideoAtPathToSavedPhotosAlbum(url.path,nil,nil,nil)
                return true
            }
            else {
                print("ERROR: file format not supported!")
                return false
            }
        case .failure(_):
            return false
        }
    }
    
    public func finishWritingVideo() async  ->  Result<URL,Error> {
        semaphore.wait()
        if writer.status == .writing {
            await writer.finishWriting()
            semaphore.signal()
            return Result.success(output)
        }
        else {
            semaphore.signal()
            writer.printStatus()
            let error = writer.error ?? VideoRecorderError.unknown
            return Result.failure(error)
        }
    }
}

enum VideoRecorderError:Error {
    case unknown
}
