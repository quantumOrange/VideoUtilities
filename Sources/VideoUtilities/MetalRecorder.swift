//
//  File.swift
//  
//
//  Created by David Crooks on 30/03/2023.
//

import Foundation
import AVFoundation
import Metal
import UIKit

public final class MetalRecorder {
    var n = 0
    private static let timescale = Int32(600)
    private var writer: AVAssetWriter
    private var input: AVAssetWriterInput
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var pixelBuffer: CVPixelBuffer?
    private var outputTextureCache: CVMetalTextureCache?
    private var output:URL

    private var size:CGSize;
    private var stopped = false
    let commandQueue: MTLCommandQueue
    let inFlightSemaphore = DispatchSemaphore(value: 1)
    var sessionStarted = false
    
    public init?(size:CGSize,  commandQueue:MTLCommandQueue,   output:URL? = nil) {
        //private let tempURL = FileManager.default.temporaryDirectory.appending(path: "tempVideo.mov")
        //private let compositionURL = FileManager.default.temporaryDirectory.appending(path: "tempCompositionVideo.mov")
        let tempURL = FileManager.default.temporaryDirectory.appending(path: "tempVideo.mov")
      
        self.output = output ?? tempURL
        self.commandQueue = commandQueue
        self.size = size
        
        let w = Int(size.width )
        let h = Int(size.height )
        
        try? FileManager.default.removeItem(at:self.output)
        
        guard let writer = try? AVAssetWriter(outputURL: self.output, fileType: AVFileType.mov) else { return nil }
        
        self.writer = writer
        
        input = AVAssetWriterInput(
            mediaType: AVMediaType.video,
            outputSettings: [
                AVVideoWidthKey: w,
                AVVideoHeightKey: h,
               // AVVideoFr
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
                            Int(size.width),
                            Int(size.height),
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
        print(ProcessInfo.processInfo.systemUptime)
       
        
        writer.printStatus()
    }
    
    var lastTimestamp:Double?
    
    public func addFrame(texture:MTLTexture, timestamp: Double)   {
        guard stopped == false else { print("Already stopped recording. Frame at \(timestamp) will not be added. ") ; return }
        guard writer.status == .writing else { print("Not writing - call start first"); return }
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        if(!sessionStarted){
            writer.startSession(atSourceTime: CMTime(seconds: timestamp, preferredTimescale: MetalRecorder.timescale))
            sessionStarted = true
        }
        
        lastTimestamp = timestamp
        guard let pixelBuffer = pixelBuffer , let outputTextureCache = outputTextureCache else { return }
      
        var cvtexture: CVMetalTexture?
        
        _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, outputTextureCache, pixelBuffer, nil, .bgra8Unorm, texture.width, texture.height, 0, &cvtexture)
        
        guard let cvtexture = cvtexture,
              let targetTexture = CVMetalTextureGetTexture(cvtexture) else {
                  return }
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()
            blitEncoder?.copy(from:texture, to: targetTexture)
            blitEncoder?.endEncoding()
            print("\(n)")
            n += 1
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            if let error = commandBuffer.error {
                print(error)
                return
            }
            inFlightSemaphore.signal()
            
            
            if adaptor.assetWriterInput.waitForReady() {
                adaptor.append(pixelBuffer, withPresentationTime:CMTime(seconds: timestamp, preferredTimescale: MetalRecorder.timescale))
            }
            else {
                print("Error: Timed-out waiting for assetWriterInput to be ready for data")
            }
        }
        
    }
    
    public func finishWritingAndSaveToPhotos() async -> Bool {
        guard stopped == false else { print("Finish already called."); return false}
        stopped = true
        
        let result =  await finishWritingVideo()
      
        switch result {
        case .success(let url):
            print("VIDEO RECORDING SUCCESS")
            if UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path) {
                print("VIDEO RECORDING SAVED")
                UISaveVideoAtPathToSavedPhotosAlbum(url.path,nil,nil,nil)
                return true
            }
            else {
                print("ERROR: file format not supported!")
                return false
            }
        case .failure(let error):
            print(error)
            return false
        }
    }
    
    
    public func finishWritingVideo() async ->  Result<URL,Error> {
        if writer.status == .writing {
            print("Finish writtting...")
            await writer.finishWriting()
            return Result.success(output)
        }
        else {
            writer.printStatus()
            let error = writer.error ?? VideoRecorderError.unknown
            return Result.failure(error)
        }
    }
}

