//
//  CGVideoCapture.swift
//  Poser
//
//  Created by David Crooks on 06/02/2022.
//

import Foundation
import Combine
import CoreImage
import CoreVideo
import VideoToolbox

class CGVideoCapture: ObservableObject {
    var videoCapture:VideoCapture?
    // 
    @Published var image:CGImage?
    
    func start() {
        Task {
            if(videoCapture == nil ) {
                videoCapture =  await VideoCapture()
            }
                
            guard let videoCapture =  videoCapture else { fatalError() }
            
            let result = await videoCapture.setUpAVCapture()
            
            switch result {
                
            case .success():
                await videoCapture.startCapturing()
            case .failure(let error):
                print(error)
            }
            
            await listenForImages()
        }
    }
    
    func stop() {
        Task {
            await videoCapture?.stopCapturing()
        }
    }
    
    func flipCamera() {
        Task {
            if let result = await videoCapture?.flipCamera() {
                switch result {
                case .success():
                    print("woopeeee!")
                case .failure(let error):
                    print(error)
                }
            }
        }
    }
    
    private func listenForImages() async {
        guard let videoCapture =  videoCapture else { fatalError()}
       
        for await pixelBuffer in await videoCapture.imageStream {
            // Create Core Graphics image placeholder.
            var newImage: CGImage?

            // Create a Core Graphics bitmap image from the pixel buffer.
            VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &newImage)

            // Release the image buffer.
            // CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            
            image = newImage
        }
        
    }
}
