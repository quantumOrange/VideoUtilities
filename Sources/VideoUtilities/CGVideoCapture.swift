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
/*
public final class CGVideoCapture: ObservableObject {
    public var videoCapture:VideoCapture?
    
    @Published public var image:CGImage?
    
    public init(){}
    
    public func start() async {
        
        if(videoCapture == nil ) {
            videoCapture =  await VideoCapture()
        }
            
        guard let videoCapture =  videoCapture else { return }
        
        let result = await videoCapture.setUpAVCapture()
        
        switch result {
            
        case .success():
            await videoCapture.startCapturing()
        case .failure(let error):
            print(error)
        }
        
        Task {
            await publishImages()
        }
    }
    
    public func stop() {
        Task {
            await videoCapture?.stopCapturing()
        }
    }
    
    public func flipCamera() {
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
    
    private func publishImages() async {
        guard let videoCapture =  videoCapture else { return }
       
        let cgImages = await videoCapture
                                .imageStream
                                .map(createCGImage)
                
        for await cgImage in cgImages {
            image = cgImage
        }
        
    }
}
*/
