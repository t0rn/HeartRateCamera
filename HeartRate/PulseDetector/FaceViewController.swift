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
        let detectFaceRequest = VNDetectFaceLandmarksRequest(completionHandler: detectedFace)
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
        
        
        //      let box = result.boundingBox
        //      faceView.boundingBox = convert(rect: box)
        //      DispatchQueue.main.async {
        //        self.faceView.setNeedsDisplay()
        //      }
        
        updateFaceView(for: result)
    }
    
    func updateFaceView(for result: VNFaceObservation) {
        defer {
            DispatchQueue.main.async {
                self.faceView.setNeedsDisplay()
            }
        }
        
        let box = result.boundingBox
        faceView.boundingBox = convert(rect: box)
        
        guard let landmarks = result.landmarks else {return}
                
        if let leftEye = landmark(points: landmarks.leftEye?.normalizedPoints, to: result.boundingBox) {
            faceView.leftEye = leftEye
        }
        
        if let rightEye = landmark( points: landmarks.rightEye?.normalizedPoints, to: result.boundingBox) {
            faceView.rightEye = rightEye
        }
        
        if let leftEyebrow = landmark(points: landmarks.leftEyebrow?.normalizedPoints, to: result.boundingBox) {
            faceView.leftEyebrow = leftEyebrow
        }
        
        if let rightEyebrow = landmark( points: landmarks.rightEyebrow?.normalizedPoints, to: result.boundingBox) {
            faceView.rightEyebrow = rightEyebrow
        }
        
        if let nose = landmark(points: landmarks.nose?.normalizedPoints, to: result.boundingBox) {
            faceView.nose = nose
        }
        
        if let outerLips = landmark(points: landmarks.outerLips?.normalizedPoints, to: result.boundingBox) {
            faceView.outerLips = outerLips
        }
        
        if let innerLips = landmark(points: landmarks.innerLips?.normalizedPoints, to: result.boundingBox) {
            faceView.innerLips = innerLips
        }
        
        if let faceContour = landmark(points: landmarks.faceContour?.normalizedPoints, to: result.boundingBox) {
            faceView.faceContour = faceContour
        }
        
        if !faceView.leftEyebrow.isEmpty,
            !faceView.rightEyebrow.isEmpty,
            !faceView.boundingBox.isEmpty,
            let leftBrowTopMost = faceView.leftEyebrow.point(for: .topMost),
            let rightBrowTopMost = faceView.rightEyebrow.point(for: .topMost) {
            
            faceView.forehead = [leftBrowTopMost,
                                 CGPoint(x: leftBrowTopMost.x, y: faceView.boundingBox.minY),
                                 CGPoint(x: rightBrowTopMost.x, y: faceView.boundingBox.minY),
                                 rightBrowTopMost]
        }
    }
    
    func convert(rect: CGRect) -> CGRect {
        let origin = videoCapture.previewLayer!.layerPointConverted(fromCaptureDevicePoint: rect.origin)
        let size = videoCapture.previewLayer!.layerPointConverted(fromCaptureDevicePoint: rect.size.cgPoint)
        return CGRect(origin: origin, size: size.cgSize)
    }
    
    func landmark(point: CGPoint, to rect: CGRect) -> CGPoint {
        let absolute = point.absolutePoint(in: rect)
        let converted = videoCapture.previewLayer!.layerPointConverted(fromCaptureDevicePoint: absolute)
        return converted
    }
    
    func landmark(points: [CGPoint]?, to rect: CGRect) -> [CGPoint]? {
        guard let points = points else {return nil}
        
        return points.compactMap { landmark(point: $0, to: rect) }
    }
}

