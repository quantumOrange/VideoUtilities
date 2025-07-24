//
//  File.swift
//  VideoUtilities
//
//  Created by David Crooks on 21/07/2025.
//

import Foundation
import Foundation
@preconcurrency import AVFoundation
import Metal
import UIKit
import VideoToolbox

public protocol MetalVideoFrameProvider {
    func start()
    func nextFrame() -> (MTLTexture?,CMTime)
}

@available(iOS 17.0, *)
public actor MetalVideoExporter {
    nonisolated public var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
      }
    
    private nonisolated let executor: Executor
    private  let queue:DispatchQueue

    var n = 0
    private static let timescale = Int32(600)
    private var writer: AVAssetWriter!
    private var input: AVAssetWriterInput!
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor!
    private var pixelBuffer: CVPixelBuffer?
    private var outputTextureCache: CVMetalTextureCache?
    private var stopped = false
    private let tempURL = FileManager.default.temporaryDirectory.appending(path: "tempVideo.mov")
    private let compositionURL = FileManager.default.temporaryDirectory.appending(path: "tempCompositionVideo.mov")
    private let expectedFPS:Int?
    private let size:CGSize
    
    var frameProvider:MetalVideoFrameProvider
    var sessionStarted = false
    
    enum VideoError : Error {
        case fileFormatNotSupported
        case writterNotWritting
        case artworkFailedToCreateOutputURL
        case frameMissingTexture
        case cannotAddInput
        case notSetupNoArtwork
    }
    
    //var artwork:Artwork!
    //private var iterator:Artwork.ArtworkIterator!
     private let texturePixelBufferAdaptor:TexturePixelBufferAdaptor!
    
    
    public init?(commandQueue:MTLCommandQueue,expectedFPS:Int?,size:CGSize,frameProvider:MetalVideoFrameProvider) {
    
        self.expectedFPS = expectedFPS
        self.frameProvider = frameProvider
        self.size = size
        
        self.texturePixelBufferAdaptor = TexturePixelBufferAdaptor(commandQueue:commandQueue,width: Int(size.width), height: Int(size.height))
        let videoQueue = DispatchQueue(label: "VideoCaptureQueue")
        self.executor = Executor(queue:videoQueue)
        self.queue = videoQueue
       
    }
    
    func setup() throws {
        
        
        let w = Int(size.width)
        let h = Int(size.height)
        
        try? FileManager.default.removeItem(at:tempURL)
        frameProvider.start()
        
       let writer = try AVAssetWriter(outputURL: tempURL, fileType: AVFileType.mov)
        
        self.writer = writer
       // hevc or
       // artwork.settings.quality
        
        //let videoFormatDescription = ??
        let settingsAssistant = AVOutputSettingsAssistant(preset: .hevc1920x1080) //??
       // settingsAssistant?.sourceVideoFormat =  videoFormatDescription
        
        let newVideoSettings = settingsAssistant?.videoSettings
       // self.textures = textures
        
        input = AVAssetWriterInput(
            mediaType: AVMediaType.video,
            outputSettings: [
                //AVVideo
                AVVideoWidthKey: w,
                AVVideoHeightKey: h,
                AVVideoCodecKey: AVVideoCodecType.h264]
            //AVVideoColorPropertiesKey:
            //sourceFormatHint:  videoFormatDescription
        )
      
            
            let hlgVideoOutputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
                ],
                AVVideoCompressionPropertiesKey: [
                    AVVideoExpectedSourceFrameRateKey: expectedFPS,
                    kVTCompressionPropertyKey_HDRMetadataInsertionMode: kVTHDRMetadataInsertionMode_Auto
                ]
            ]
        
        //AVVideoCodecType.h264 // not hdr ??
        //AVVideoCodecType.hevc // hvec is HDR
        //AVVideoCodecType.proRes422 // pro res is HDR
        
        // TODO :- depends on artwork??
       // input.transform = CGAffineTransform(rotationAngle: artwork.settings.rotationAngle)
        // input.expectsMediaDataInRealTime = true
        
        guard writer.canAdd(input) else { throw  VideoError.cannotAddInput }
        writer.add(input)
        
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)])
        
        //lastFrame = nil
    }
    
    func prepareToWrite() {
        if let label = String(validatingUTF8: __dispatch_queue_get_label(nil)) {
            print("\(#function) on queue: \(label)")
        }
        else {
            print("\(#function) on unkown queue")
        }
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
    }
    
    var isWriting:Bool {
        writer.status == .writing
    }
    
    var startSessionDate = Date.now
    var frameCount = 0
    
    func startSession(timestamp: Double) {
        assert(writer.status == .writing)
        startSessionDate = Date.now
        frameCount = 0
        
        writer.startSession(atSourceTime: CMTime(seconds: timestamp, preferredTimescale: MetalVideoExporter.timescale))
        sessionStarted = true
        print("start session \(timestamp)...")
    }

    
    public func export() async throws -> URL {
        try! setup()
        
        if let label = String(validatingUTF8: __dispatch_queue_get_label(nil)) {
            print("\(#function) on queue: \(label)")
        }
        else {
            print("\(#function) on unkown queue")
        }
        //let frame =  artwork.currentFrame!
        //let tex = try! metalManager.renderFrame(frame: frame, artwork: artwork, at: 0)
        
        print("got a texture!")
        prepareToWrite()
        startSession(timestamp:0)
        let result = await writeFramesToFile()
        
        switch result {
            
        case .success(let url):
            return url
        case .failure(let error):
            throw error
        }
    }
    
    func writeFramesToFile() async ->  Result<URL,Error> {
        print("***********")
        print("*** write to file ***")
      
        //texturePixelBufferAdaptor.prepare(width:Int(size.width), height: Int(size.height))
        
        if let label = String(validatingUTF8: __dispatch_queue_get_label(nil)) {
            print("\(#function) on queue: \(label)")
        }
        else {
            print("\(#function) on unkown queue")
        }
        
        return await withCheckedContinuation { continuation in
            if let label = String(validatingUTF8: __dispatch_queue_get_label(nil)) {
                print("call request when ready on queue: \(label)")
            }
            else {
                print("\(#function) on unkown queue")
            }
            adaptor.assetWriterInput.requestMediaDataWhenReady(on: queue) {
                if let label = String(validatingUTF8: __dispatch_queue_get_label(nil)) {
                    print("request media on queue: \(label)")
                }
                else {
                    print("\(#function) on unkown queue")
                }
                Task {
                    await self.addFramesWhileReady(continuation: continuation)
                }
            }
        }
    }
    
    func nextFrame() async throws -> (pixelBuffer:CVPixelBuffer,time:CMTime)? {
        print("--- Next Frame")
        if let label = String(validatingUTF8: __dispatch_queue_get_label(nil)) {
            print("\(#function) on queue: \(label)")
        }
        else {
            print("\(#function) on unkown queue")
        }
        let (frame,time) =  frameProvider.nextFrame()
        
        guard let frame else {
           
            writer.endSession(atSourceTime:time)
            print("End session")
            return nil }
       
        frameCount += 1
        
        let pixelBuffer = try texturePixelBufferAdaptor.makeCVPixelBuffer(from: frame)
        print("     -frame at time: \(time) ")
        return (pixelBuffer,time)
        
    }

    func addFramesWhileReady(continuation:CheckedContinuation<Result<URL, any Error>, Never>) async {
        print("*** add while ready ****")
        if let label = String(validatingUTF8: __dispatch_queue_get_label(nil)) {
            print("\(#function) on queue: \(label)")
        }
        else {
            print("\(#function) on unkown queue")
        }
        
        while adaptor.assetWriterInput.isReadyForMoreMediaData {
            if let label = String(validatingUTF8: __dispatch_queue_get_label(nil)) {
                print("\(#function) on queue: \(label)")
            }
            else {
                print("\(#function) on unkown queue")
            }
            // Copy the next sample buffer from your source media.
            var frame: (pixelBuffer: CVPixelBuffer,time: CMTime)?
            //
            
            do {
               frame = try await nextFrame()
            }
            catch {
                adaptor.assetWriterInput.markAsFinished()
                _ =  try? await finishWriting()
                continuation.resume(returning: .failure(error))
                return
            }
            
            guard let frame else {
                
            
                // Mark the input as finished.
                print("**** Finished ******")
                adaptor.assetWriterInput.markAsFinished()
                do {
                    let result = try await finishWriting()
                    continuation.resume(returning:.success(result))
                }
                catch {
                    continuation.resume(returning:.failure(error))
                }
                
            
                return
            }
            // Append the sample buffer to the input.
           
            adaptor.append(frame.pixelBuffer, withPresentationTime: frame.time)
        }
    }
    
    func finishWriting() async throws -> URL   {
        guard  writer.status == .writing else {
            writer.printStatus()
            let error = writer.error ?? VideoError.writterNotWritting
            throw error
        }
        //guard let output = try? artwork.videoURL else {
        //   // return Result.failure(VideoError.artworkFailedToCreateOutputURL)
        //    throw VideoError.artworkFailedToCreateOutputURL
        //}
        
        let tempURL = tempURL
    
        
        await writer.finishWriting()
        
        
        return tempURL
        /*
        if FileManager.default.fileExists(atPath: output.path()) {
            try FileManager.default.removeItem(at: output)
        }
        
        return output
        */
    }
}

@available(iOS 17.0, *)
extension MetalVideoExporter  {
    
    final class Executor: SerialExecutor {
    init(queue: DispatchQueue) {
      self.queue = queue
    }
    
    func enqueue(_ job: consuming ExecutorJob) {
      let unownedJob = UnownedJob(job)
      let unownedExecutor = asUnownedSerialExecutor()
      queue.async {
        unownedJob.runSynchronously(on: unownedExecutor)
      }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
      UnownedSerialExecutor(ordinary: self)
    }

    private let queue: DispatchQueue
  }
}
