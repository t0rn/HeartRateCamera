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
import ClibICA

class FaceViewController: UIViewController {
    
    @IBOutlet weak var faceView: FaceView!
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var pulseLabel: UILabel!
    @IBOutlet weak var ROIView: UIImageView!
    
    private let signalProcessor = SignalProcessor()
    
    @IBOutlet weak var colorView: UIView!
    
    lazy var videoCapture: VideoCaptureService = {
        let spec = VideoCaptureService.VideoSpec(fps: 30, size:CGSize(width: 1280, height: 720))
        let videoCapture = VideoCaptureService(cameraType: .front,
                                        preferredSpec: spec,
                                        previewContainer: self.previewView.layer)
        videoCapture.imageBufferHandler = { [weak self] (imageBuffer) in
            self?.handle(buffer: imageBuffer)
        }
        return videoCapture
    }()
    
    var sequenceHandler = VNSequenceRequestHandler()
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        videoCapture.startCapture()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] (timer) in
            guard let self = self else {return}
            //print valid frames
//            let validFrames = min(100, (100*self.hrBuffer.validFrameCounter)/10) //10 is a MIN_FRAMES_FOR_FILTER_TO_SETTLE
            
            DispatchQueue.main.async {
                let hr = self.signalProcessor.averageHR
                self.pulseLabel.text = String(format: "%.f", hr)
                self.colorView.backgroundColor = self.signalProcessor.colors.last ?? UIColor.black
                if let image = self.signalProcessor.inputImages.last {
                    let uiImg = UIImage(cgImage: image)
                    self.ROIView.image = uiImg
                }
            }
        }

    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    var faceViewBounds: CGRect?
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        faceViewBounds = faceView.bounds
    }
    
    func handle(buffer:CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {return}
        //crop image buffer to ROI (forehead) size
        let detectFaceRequest = VNDetectFaceLandmarksRequest { (request, error) in
            self.detectedFace(request: request, error: error, imageBuffer: imageBuffer)
        }
        do {
            try sequenceHandler.perform([detectFaceRequest],
                                        on: imageBuffer,
                                        orientation: .leftMirrored)
        } catch {
            print(error.localizedDescription)
            return
        }
    }

    func detectedFace(request: VNRequest, error: Error?, imageBuffer:CVImageBuffer) {
        guard
            let results = request.results as? [VNFaceObservation],
            let result = results.first
            else {
                faceView.clear()
                signalProcessor.stop()
                return
        }
        updateFaceView(for: result)
        //define rect of ROI (forehead) from imagebuffer
        if false == faceView.forehead.isEmpty,
            let topMostPoint = faceView.forehead.point(for: .topMost),
            let bottomMostPoint = faceView.forehead.point(for: .bottomMost),
            let rightMostPoint = faceView.forehead.point(for: .rightMost),
            let leftMostPoint = faceView.forehead.point(for: .leftMost) {

            let foreheadOrigin = CGPoint(x: leftMostPoint.x,
                                         y: topMostPoint.y)
            let foreheadRect = CGRect(x: foreheadOrigin.x,
                                      y: foreheadOrigin.y,
                                      width: rightMostPoint.x - leftMostPoint.x,
                                      height: bottomMostPoint.y - topMostPoint.y)
            //https://nacho4d-nacho4d.blogspot.com/2012/03/coreimage-and-uikit-coordinates.html
            //TODO: make it relative in coordinates
            let image = CIImage(cvImageBuffer: imageBuffer)
            
            var transform = CGAffineTransform(scaleX: 1, y: -1)
            transform = transform.translatedBy(x: 0, y: -image.extent.size.height)
            
            let wFactor = image.extent.width / faceViewBounds!.width
            let hFactor = image.extent.height / faceViewBounds!.height
            let o = CGPoint(x: foreheadOrigin.x * wFactor,
                            y: foreheadOrigin.y * hFactor)
            let size = CGSize(width: foreheadRect.width * wFactor,
                              height: foreheadRect.height * hFactor)
//            let cropRect = CGRect(origin: o, size: size)
            let cropRect = CGRect(origin: o, size: size).applying(transform)
            signalProcessor.handle(imageBuffer: imageBuffer, cropRect: cropRect)
        }
    }
    
    func updateFaceView(for face: VNFaceObservation) {
        defer {
            DispatchQueue.main.async {
                self.faceView.setNeedsDisplay()
            }
        }
        //bounding box are normalized between 0.0 and 1.0 to the input image, with the origin at the bottom left corner
        let box = face.boundingBox
        faceView.boundingBox = convert(rect: box)
        
        guard let landmarks = face.landmarks else {return}
                
        if let leftEyebrow = landmark(points: landmarks.leftEyebrow?.normalizedPoints, to: face.boundingBox) {
            faceView.leftEyebrow = leftEyebrow
        }
        
        if let rightEyebrow = landmark( points: landmarks.rightEyebrow?.normalizedPoints, to: face.boundingBox) {
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
    
    func normalize(rect:CGRect, from parent:CGRect) -> CGRect {
        var result = parent
        result.origin.x /= parent.width
        result.origin.y /= parent.height
        result.size.width /= parent.width
        result.size.height /= parent.height
        return result
    }
    
    //from normalized
    func convert(rect: CGRect) -> CGRect {
        let origin = videoCapture.previewLayer!.layerPointConverted(fromCaptureDevicePoint: rect.origin)
        let size = videoCapture.previewLayer!.layerPointConverted(fromCaptureDevicePoint: rect.size.cgPoint)
        return CGRect(origin: origin, size: size.cgSize)
    }
    
    //normalized point + normalized rect
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

