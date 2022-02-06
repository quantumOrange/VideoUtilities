import AVFoundation
import CoreVideo
import UIKit
import VideoToolbox

public actor VideoCapture {
    
    enum VideoCaptureError: Error {
        case captureSessionIsMissing
        case invalidInput
        case invalidOutput
        case unknown
    }
    
    private var sampleBufferDelegate:SampleBufferDelegate!
    
     init() async {
        self.imageStream = AsyncStream(CVImageBuffer.self) { continuation in
            sampleBufferDelegate =  SampleBufferDelegate(continuation: continuation)
            self.continuation = continuation
        }
    }

     public var imageStream: AsyncStream<CVImageBuffer>!
     private var continuation: AsyncStream<CVImageBuffer>.Continuation?
    
    /// A capture session used to coordinate the flow of data from input devices to capture outputs.
    let captureSession = AVCaptureSession()

    /// A capture output that records video and provides access to video frames. Captured frames are passed to the
    /// delegate via the `captureOutput()` method.
    let videoOutput = AVCaptureVideoDataOutput()

    /// The current camera's position.
    private(set) var cameraPostion = AVCaptureDevice.Position.front

    /// Toggles between the front and back camera.
    public func  flipCamera() -> Result<Void,Error>  {
        do {
            self.cameraPostion = self.cameraPostion == .back ? .front : .back

            // Indicate the start of a set of configuration changes to the capture session.
            self.captureSession.beginConfiguration()

            try self.setCaptureSessionInput()
            try self.setCaptureSessionOutput()

            // Commit configuration changes.
            self.captureSession.commitConfiguration()

            return .success(())
           
        } catch {
            return .failure(error)
        }
    }

   public func setUpAVCapture() async  -> Result<Void,Error> {
       await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void,Error>, Never>) in
         
               do {
                   try self.setUpAVCapture()
                   continuation.resume(returning: Result.success(()))
               } catch {
                   continuation.resume(returning: Result.failure(error))
               }
         
       }
   }

    private func setUpAVCapture() throws {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        captureSession.beginConfiguration()

        captureSession.sessionPreset = .vga640x480

        try setCaptureSessionInput()

        try setCaptureSessionOutput()

        captureSession.commitConfiguration()
    }
   
    private func setCaptureSessionInput() throws {
        // Use the default capture device to obtain access to the physical device
        // and associated properties.
        guard let captureDevice = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: AVMediaType.video,
            position: cameraPostion) else {
                throw VideoCaptureError.invalidInput
        }

        // Remove any existing inputs.
        captureSession.inputs.forEach { input in
            captureSession.removeInput(input)
        }

        // Create an instance of AVCaptureDeviceInput to capture the data from
        // the capture device.
        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            throw VideoCaptureError.invalidInput
        }

        guard captureSession.canAddInput(videoInput) else {
            throw VideoCaptureError.invalidInput
        }

        captureSession.addInput(videoInput)
    }

    private func setCaptureSessionOutput() throws {
        // Remove any previous outputs.
        captureSession.outputs.forEach { output in
            captureSession.removeOutput(output)
        }

        // Set the pixel type.
        let settings: [String: Any] = [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        videoOutput.videoSettings = settings

        // Discard newer frames that arrive while the dispatch queue is already busy with
        // an older frame.
        videoOutput.alwaysDiscardsLateVideoFrames = true

        videoOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: sampleBufferDelegate.queue)
        
        guard captureSession.canAddOutput(videoOutput) else {
            throw VideoCaptureError.invalidOutput
        }

        captureSession.addOutput(videoOutput)

        // Update the video orientation
        if let connection = videoOutput.connection(with: .video),
            connection.isVideoOrientationSupported {
            
            Task {
                connection.videoOrientation =
                    await AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation)
                
                connection.isVideoMirrored = cameraPostion == .front

                // Inverse the landscape orientation to force the image in the upward
                // orientation.
                if connection.videoOrientation == .landscapeLeft {
                    connection.videoOrientation = .landscapeRight
                } else if connection.videoOrientation == .landscapeRight {
                    connection.videoOrientation = .landscapeLeft
                }
            }
        }
    }

    /// Begin capturing frames.
    public func startCapturing() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if !self.captureSession.isRunning {
                // Invoke the startRunning method of the captureSession to start the
                // flow of data from the inputs to the outputs.
                self.captureSession.startRunning()
            }
            continuation.resume()
        }
    }

    /// End capturing frames
    public func stopCapturing() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            continuation.resume()
        }
    }
}

fileprivate final class SampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var continuation: AsyncStream<CVImageBuffer>.Continuation
    
    let queue = DispatchQueue(
        label: "av-capture-video-data-output-sample-buffer-delegate-queue")
    
    init(continuation:AsyncStream<CVImageBuffer>.Continuation) {
        self.continuation = continuation
        super.init()
    }
    
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
      
        if let pixelBuffer = sampleBuffer.imageBuffer {
            // Attempt to lock the image buffer to gain access to its memory.
            guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess
                else {
                    return
            }
            
            continuation.yield(pixelBuffer)
            
            // Release the image buffer.
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
    }
}

