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
    @IBOutlet weak var pulseLabel: UILabel!
    private let signalProcessor = SignalProcessor()
    
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
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] (timer) in
            guard let self = self else {return}
            //print valid frames
            //            let validFrames = min(100, (100*self.hrBuffer.validFrameCounter)/10) //10 is a MIN_FRAMES_FOR_FILTER_TO_SETTLE
            print("pulse \(self.signalProcessor.pulse)")
            DispatchQueue.main.async {
                self.pulseLabel.text = String(describing:self.signalProcessor.pulse)
            }
        }

    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }

    func handle(buffer:CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {return}
        //crop image buffer to ROI (forehead) size
        let detectFaceRequest = VNDetectFaceLandmarksRequest(completionHandler: detectedFace)
        do {
            try sequenceHandler.perform([detectFaceRequest],
                                        on: imageBuffer,
                                        orientation: .leftMirrored)
            if false == faceView.forehead.isEmpty,
                let topMostPoint = faceView.forehead.point(for: .topMost),
                let bottomMostPoint = faceView.forehead.point(for: .bottomMost),
                let rightMostPoint = faceView.forehead.point(for: .rightMost),
                let leftMostPoint = faceView.forehead.point(for: .leftMost) {
                let origin = CGPoint(x: leftMostPoint.x,
                                     y: topMostPoint.y)
                let foreheadRect = CGRect(x: origin.x,
                                          y: origin.y,
                                          width: rightMostPoint.x - leftMostPoint.x,
                                          height: bottomMostPoint.y - topMostPoint.y)
                signalProcessor.handle(imageBuffer: imageBuffer, cropRect: foreheadRect)
            }
        } catch {
            print(error.localizedDescription)
            return
        }
        
        
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
                
        if let leftEyebrow = landmark(points: landmarks.leftEyebrow?.normalizedPoints, to: result.boundingBox) {
            faceView.leftEyebrow = leftEyebrow
        }
        
        if let rightEyebrow = landmark( points: landmarks.rightEyebrow?.normalizedPoints, to: result.boundingBox) {
            faceView.rightEyebrow = rightEyebrow
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

