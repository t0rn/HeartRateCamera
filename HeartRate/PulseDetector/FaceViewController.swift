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
    @IBOutlet weak var colorView: UIView!
        
    private let signalProcessor = SignalProcessor()
    
    lazy var videoCapture: VideoCaptureService = {
        let spec = VideoCaptureService.VideoSpec(fps: 30, size:CGSize(width: 1280, height: 720))
        let videoCapture = VideoCaptureService(cameraType: .front,
                                        preferredSpec: spec,
                                        previewContainer: self.previewView.layer)
        videoCapture.outputBuffer = { [weak self] (imageBuffer) in
            self?.handle(buffer: imageBuffer)
        }
        return videoCapture
    }()
    
    var sequenceHandler = VNSequenceRequestHandler()
    
    
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        faceViewFrame = faceView.frame
    }
    
    var faceViewFrame: CGRect!
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        videoCapture.startCapture()

        UIApplication.shared.isIdleTimerDisabled = true
        
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
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
        
    func handle(buffer: CMSampleBuffer) {
//        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {return}
        guard let imageBuffer = buffer.imageBuffer else {return}
        let detectFaceRequest = VNDetectFaceLandmarksRequest { (request, error) in
            self.detectedFace(request: request, error: error, imageBuffer: imageBuffer)
        }

        do {
            try sequenceHandler.perform([detectFaceRequest],
                                        on: imageBuffer,
                                        orientation: .leftMirrored) //leftMirrored works fine
        } catch {
            print(error.localizedDescription)
            return
        }
    }

    func detectedFace(request: VNRequest, error: Error?, imageBuffer:CVImageBuffer) {
        guard
            let faces = request.results as? [VNFaceObservation],
            let face = faces.first
            else {
                faceView.clear()
                signalProcessor.stop()
                return
        }
        
        updateFaceView(for: face)
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
            let imageBufer = CIImage(cvImageBuffer: imageBuffer)
            //for resizeAspectFill videoGravity
            imageBufer.transformed(by: .init(scaleX: 1, y: -1))
            let imageSize = imageBufer.extent.size
            let faceViewSize = faceViewFrame.size

            var scaleFactor : CGFloat = faceViewSize.width / imageSize.width
            if imageSize.height * scaleFactor < faceViewSize.height {
                scaleFactor = faceViewSize.height / imageSize.height
            }
            let visibleImageSize = CGSize(width:faceViewSize.width/scaleFactor, height:faceViewSize.height/scaleFactor)

            let visibleImageHeight = (imageSize.height - visibleImageSize.height) / 2.0
//            let visibleImageWidth = (imageSize.width - visibleImageSize.width) / 2.0
//            let visibleImageRect = CGRect(origin: .init(x: visibleImageWidth,
//                                                        y: visibleImageHeight),
//                                          size: visibleImageSize)
            
            let foreheadImageWidth = foreheadRect.width / scaleFactor
            let foreheadImageHeight = foreheadRect.height / scaleFactor
            
            let foreheadImageX = foreheadRect.minX / scaleFactor //mirrored for front camera
            
            let foreheadImageY = (imageSize.height - visibleImageHeight) - (foreheadRect.maxY / scaleFactor)

            let foreheadImageFrame = CGRect(x: foreheadImageX, y: foreheadImageY,
                                            width: foreheadImageWidth, height: foreheadImageHeight)

            //apply x axis transformation for front camera imageBuffer (.leftMirrored)
            let foreheadImage = imageBufer
                .transformed(by: .init(translationX: -imageBufer.extent.width, y: 1))
                .transformed(by: .init(scaleX: -1, y: 1))
                .cropped(to: foreheadImageFrame)

            signalProcessor.processROI(image: foreheadImage)
        }
    }
    
    func updateFaceView(for face: VNFaceObservation) {
        defer {
            DispatchQueue.main.async {
                self.faceView.setNeedsDisplay()
            }
        }
        guard
            let landmarks = face.landmarks,
            let previewLayer = videoCapture.previewLayer
            else {return}

        faceView.boundingBox = previewLayer.layerRectConverted(fromMetadataOutputRect: face.boundingBox)

        if let leftEyebrow = landmark(points: landmarks.leftEyebrow?.normalizedPoints, to: face.boundingBox) {
            faceView.leftEyebrow = leftEyebrow
        }
        
        if let rightEyebrow = landmark(points: landmarks.rightEyebrow?.normalizedPoints, to: face.boundingBox) {
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

extension VNFaceObservation {
    func convertedBoundingBox(for frame:CGRect) -> CGRect {
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -frame.height)
        let translate = CGAffineTransform.identity.scaledBy(x: frame.width, y: frame.height)
        // The coordinates are normalized to the dimensions of the processed image, with the origin at the image's lower-left corner.
        let facebounds = boundingBox.applying(translate).applying(transform)
        return facebounds
    }
    func covertedBoundingBoxIn(previewLayer: AVCaptureVideoPreviewLayer) -> CGRect {
        let origin = previewLayer.layerPointConverted(fromCaptureDevicePoint: boundingBox.origin)
        let size = previewLayer.layerPointConverted(fromCaptureDevicePoint: boundingBox.size.cgPoint)//?
        return .init(origin: origin, size: size.cgSize)
    }
}

extension UIDevice {
    func imageOrientation(by position: AVCaptureDevice.Position) -> CGImagePropertyOrientation? {
        switch (orientation, position) {
        case (.portrait, .front):
            return .upMirrored
        case (.portrait, .back):
            return .up

        default:
            //TODO: handle later
            return nil
        }
    }
}
extension VNFaceObservation {
  //see https://stackoverflow.com/questions/45151218/vnfaceobservation-boundingbox-not-scaling-in-portrait-mode
  func convertWith(previewLayerFrame: CGRect) -> CGRect {
    let size = CGSize(width: boundingBox.width * previewLayerFrame.width,
                      height: boundingBox.height * previewLayerFrame.height)
    let origin = CGPoint(x: boundingBox.minX * previewLayerFrame.width,
                         y: (1 - boundingBox.minY) * previewLayerFrame.height)
    let result = CGRect(origin: origin, size: size)
    print(result)
    return result
  }
}
