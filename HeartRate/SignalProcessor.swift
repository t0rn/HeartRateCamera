//
//  SignalProcessor.swift
//  HeartRate
//
//  Created by Alexey Ivanov on 12.01.2020.
//  Copyright © 2020 Alexey Ivanov. All rights reserved.
//

import UIKit

class SignalProcessor {
    private let pulseDetector = PulseDetector()
    private(set) var validFrameCounter = 0
    private var hueFilter = Filter()
    private var inputs: [CGFloat] = []
    
    var pulse:Float {
        return 60.0/average
    }
    
    var average:Float {
        return pulseDetector.getAverage()
    }
    
    func handle(imageBuffer: CVImageBuffer, cropRect:CGRect? = nil) {
        
        var redmean:CGFloat = 0.0;
        var greenmean:CGFloat = 0.0;
        var bluemean:CGFloat = 0.0;
        
        let cameraImage = CIImage(cvPixelBuffer: imageBuffer)
        

        
        let extent = cameraImage.extent
        var inputExtent = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height)
        if let cropRect = cropRect {
            inputExtent = CIVector(cgRect: cropRect)
        }
        let averageFilter = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: cameraImage, kCIInputExtentKey: inputExtent])!
        guard let outputImage = averageFilter.outputImage else {
            fatalError("Can't apply CIAreaAverage filter")
        }
        
        let ctx = CIContext(options:nil)
        let cgImage = ctx.createCGImage(outputImage, from: outputImage.extent)!
        
        let rawData:NSData = cgImage.dataProvider!.data!
        let pixels = rawData.bytes.assumingMemoryBound(to: UInt8.self)
        let bytes = UnsafeBufferPointer<UInt8>(start:pixels, count:rawData.length)
        var BGRA_index = 0
        for pixel in UnsafeBufferPointer(start: bytes.baseAddress, count: bytes.count) {
            switch BGRA_index {
            case 0:
                bluemean = CGFloat (pixel)
            case 1:
                greenmean = CGFloat (pixel)
            case 2:
                redmean = CGFloat (pixel)
            case 3:
                break
            default:
                break
            }
            BGRA_index += 1
        }
        
        let hsv = rgb2hsv((red:redmean, green: greenmean,blue: bluemean,alpha: 1.0))
        // do a sanity check to see if a finger is placed over the camera
        if(hsv.1>0.5 && hsv.2>0.5) {
            print("finger on torch")
            validFrameCounter += 1
            inputs.append(hsv.0)
            // filter the hue value - the filter is a simple band pass filter that removes any DC component
            //and any high frequency noise
            let filtered = hueFilter.processValue(Float(hsv.0))
            // have we collected enough frames for the filter to settle?
            //TODO: use constant MIN_FRAMES_FOR_FILTER_TO_SETTLE for exameple
            if validFrameCounter > 10 {
                self.pulseDetector.addNewValue(filtered, atTime: CACurrentMediaTime())
            }
        } else {
            //uncomment for writing into txt file
            //            try? inputs.map{ String(describing: $0) }
            //                .joined(separator: "\n")
            //                .write()
            
            print("Put finger on camera!")
            //TODO: delegate!
            //                DispatchQueue.main.async {
            //                    self.pulseLabel.text = "Put your finger on camera!"
            //                }
            validFrameCounter = 0
            pulseDetector.reset()
        }
    }
}
