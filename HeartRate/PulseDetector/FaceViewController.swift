//
//  FaceViewController.swift
//  HeartRate
//
//  Created by Alexey Ivanov on 09/01/2020.
//  Copyright © 2020 Alexey Ivanov. All rights reserved.
//

import UIKit
import AVFoundation
import CoreImage
import Vision

class FaceViewController: UIViewController {
    
    @IBOutlet weak var faceView: FaceView!
    @IBOutlet weak var previewView: UIView!
    
    lazy var videoCapture: VideoCapture = {
        let spec = VideoSpec(fps: 30, size: CGSize(width: 300, height: 300))
        let videoCapture = VideoCapture(cameraType: .front,
                                        preferredSpec: spec,
                                        previewContainer: self.previewView.layer)
        videoCapture.imageBufferHandler = { [unowned self] (imageBuffer) in
            self.handle(buffer: imageBuffer)
        }
        return videoCapture
    }()
    
    var sequenceHandler = VNSequenceRequestHandler()
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        videoCapture.startCapture()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }

    func handle(buffer:CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {return}
        let detectFaceRequest = VNDetectFaceRectanglesRequest(completionHandler: detectedFace)
        do {
            try sequenceHandler.perform([detectFaceRequest],
                                        on: imageBuffer,
                                        orientation: .leftMirrored)
        } catch {
            print(error.localizedDescription)
            return
        }
        
        var redmean:CGFloat = 0.0;
        var greenmean:CGFloat = 0.0;
        var bluemean:CGFloat = 0.0;
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(buffer)
        let cameraImage = CIImage(cvPixelBuffer: pixelBuffer!)
        
        let extent = cameraImage.extent
        let inputExtent = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height)
        let averageFilter = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: cameraImage, kCIInputExtentKey: inputExtent])!
        let outputImage = averageFilter.outputImage!
        
        let ctx = CIContext(options:nil)
        let cgImage = ctx.createCGImage(outputImage, from:outputImage.extent)!
        
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
        print(hsv)
    }

    func detectedFace(request: VNRequest, error: Error?) {
      guard
        let results = request.results as? [VNFaceObservation],
        let result = results.first
        else {
            faceView.clear()
            return
        }
        
      // 3
      let box = result.boundingBox
      faceView.boundingBox = convert(rect: box)
        
      // 4
      DispatchQueue.main.async {
        self.faceView.setNeedsDisplay()
      }
    }
    
    func convert(rect: CGRect) -> CGRect {
        
        let origin = videoCapture.previewLayer!.layerPointConverted(fromCaptureDevicePoint: rect.origin)
        let size = videoCapture.previewLayer!.layerPointConverted(fromCaptureDevicePoint: rect.size.cgPoint)
        return CGRect(origin: origin, size: size.cgSize)
    }
}

extension CGSize {
  var cgPoint: CGPoint {
    return CGPoint(x: width, y: height)
  }
}

extension CGPoint {
  var cgSize: CGSize {
    return CGSize(width: x, height: y)
  }
  
}

