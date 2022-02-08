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
    
    let semaphore = DispatchSemaphore(value: 1)
    
    let commandQueue: MTLCommandQueue
    
    var sessionStarted = false
    
    public init?(size:CGSize,  commandQueue:MTLCommandQueue,   output:URL? = nil){
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
        // MTLDevice
        
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
        print(ProcessInfo.processInfo.systemUptime)
       
        
        writer.printStatus()
    }
    
    var lastTimestamp:Double?
    
    public func addFrame(texture:MTLTexture, timestamp: Double) {
        print("Time \(timestamp)");
       // writer.
        if(!sessionStarted){
            writer.startSession(atSourceTime: CMTime(seconds: timestamp, preferredTimescale: MetalVideoRecorder.timescale))
            sessionStarted = true
        }
        lastTimestamp = timestamp
        guard let pixelBuffer = pixelBuffer , let outputTextureCache = outputTextureCache else { return }
        semaphore.wait()
       
        var cvtexture: CVMetalTexture?
        
        _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, outputTextureCache, pixelBuffer, nil, .bgra8Unorm, texture.width, texture.height, 0, &cvtexture)
        
        guard let cvtexture = cvtexture,
              let targetTexture = CVMetalTextureGetTexture(cvtexture) else { return }
        
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()
            blitEncoder?.copy(from:texture, to: targetTexture)
            blitEncoder?.endEncoding()
            print("\(n)")
            n += 1
            commandBuffer.addCompletedHandler { (_ commandBuffer) -> Void in
                if let error = commandBuffer.error {
                    print("*---!!---*")
                    print(error)
                }
                self.adaptor.append(pixelBuffer, withPresentationTime: CMTime(seconds: timestamp, preferredTimescale: MetalVideoRecorder.timescale))
                self.semaphore.signal()
            }
            
            commandBuffer.commit()
        }
        else {
            self.semaphore.signal()
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
            //let time = lastTimestamp ?? 0.0
           // writer.endSession(atSourceTime: CMTime(seconds: time, preferredTimescale: <#T##CMTimeScale#>))
            //writer.
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

extension MTLCommandBuffer {
    func commitAndComplete() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            addCompletedHandler { (_ commandBuffer) -> Void in
                if let err = commandBuffer.error {
                    print(err)
                }
                continuation.resume()
            }
            commit()
        }
    }
}
