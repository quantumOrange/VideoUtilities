//
//  AVAssetWriter+Extensions.swift
//  SimpleMetalComputeExample
//
//  Created by David Crooks on 25/09/2021.
//

import Foundation
import AVFoundation

extension AVAssetWriter {
    func printStatus() {
        switch status {
        case .unknown:
            print("unkown")
        case .writing:
            print("writing")
        case .completed:
            print("completed")
        case .failed:
            print("failed")
        case .cancelled:
            print("cancelled")
        @unknown default:
            print("wtf?")
        }
    }
}
