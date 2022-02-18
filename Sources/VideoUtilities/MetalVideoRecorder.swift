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
    
    var sessionStarted = false
    
    public init?(size:CGSize,  commandQueue:MTLCommandQueue,   output:URL? = nil) async {
        guard let output = output ?? Files.createVideosURL()  else { return nil }
        self.output = output
        self.commandQueue = commandQueue
        self.size = size
        
        let w = Int(size.width )
        let h = Int(size.height )
        
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
        if(!sessionStarted){
            writer.startSession(atSourceTime: CMTime(seconds: timestamp, preferredTimescale: MetalVideoRecorder.timescale))
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
            
            if adaptor.assetWriterInput.waitForReady() {
                adaptor.append(pixelBuffer, withPresentationTime:CMTime(seconds: timestamp, preferredTimescale: MetalVideoRecorder.timescale))
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

enum VideoRecorderError:Error {
    case unknown
}

extension MTLCommandBuffer {
    func commitAndComplete() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            commit()
            waitUntilCompleted()
            continuation.resume()
        }
    }
}

extension  AVAssetWriterInput {
    func waitForReady(timeOut:TimeInterval = 1.0)  -> Bool {
        
        let waitStep:TimeInterval = 0.0001
        var waitTime:TimeInterval = 0.0
        
        while !isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval:waitStep)
            
            waitTime += waitStep
            
            if waitTime > timeOut {
                return false
            }
        }
        
        if waitTime > 0 {
            print("Slept for \(waitTime) waiting for asset writer input to be ready")
        }
        
        return true
    }
}
