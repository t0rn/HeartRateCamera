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
        
    func handle(buffer:CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {return}
        //crop image buffer to ROI (forehead) size
        let detectFaceRequest = VNDetectFaceLandmarksRequest { (request, error) in
            self.detectedFace(request: request, error: error, imageBuffer: imageBuffer)
        }
        let imageOrientation = UIDevice.current.imageOrientation(by: videoCapture.videoDevice.position) ?? .up
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
            //https://nacho4d-nacho4d.blogspot.com/2012/03/coreimage-and-uikit-coordinates.html
            //TODO: make it relative in coordinates
            let imageBufer = CIImage(cvImageBuffer: imageBuffer)
//            let transform = CGAffineTransform(scaleX: 1, y: -1)
//                .translatedBy(x: 0, y: -imageBufer.extent.size.height)
//                .translatedBy(x: 0, y: -faceViewFrame.size.height)
            
            //notice that preview layer is scaled
            
//            let screenScale = UIScreen.main.scale
            
            ///works fine with default videoGravity = rizesAspect
            let wScaleFactor = faceViewFrame.width / imageBufer.extent.width
            let hScaleFactor = faceViewFrame.height / imageBufer.extent.height
            let foreheadImageWidth = foreheadRect.width / wScaleFactor
            let foreheadImageHeight = foreheadRect.height / hScaleFactor
            let foreheadImageX = foreheadRect.origin.x / wScaleFactor
            let foreheadImageY = (imageBufer.extent.height - (foreheadRect.maxY / hScaleFactor))
            ///
            
            
//            let foreheadImageWidth = foreheadRect.width * imageBufer.extent.width / faceViewFrame.width
//            let foreheadImageHeight = foreheadRect.height * imageBufer.extent.height / faceViewFrame.height
//            let foreheadImageX = foreheadRect.origin.x * imageBufer.extent.width / faceViewFrame.width
//
//            let foreheadImageMaxY = imageBufer.extent.height - (foreheadRect.origin.y * imageBufer.extent.height / faceViewFrame.height)
//            let foreheadImageY = foreheadImageMaxY - (foreheadRect.height * imageBufer.extent.height / faceViewFrame.height)
            
            // CoreImage coordinate system origin is at the bottom left corner
            // and UIKit is at the top left corner. So we need to translate
            // features positions before drawing them to screen. In order to do
            // so we make an affine transform
//            let foreheadImageY = foreheadRect.origin.y * imageBufer.extent.height / faceViewFrame.height
//            var transform = CGAffineTransform(scaleX: 1, y: -1);
//            transform = transform.translatedBy(x: 0, y: -faceViewFrame.size.height)
//            transform = transform.translatedBy(x: 0, y: -imageBufer.extent.height)
            
//            let foreheadImageFrame = face.convertWith(previewLayerFrame: foreheadRect)
            let foreheadImageFrame = CGRect(x: foreheadImageX, y: foreheadImageY,
                                            width: foreheadImageWidth, height: foreheadImageHeight)

//                .applying(transform)
            print("foreheadImageFrame \(foreheadImageFrame)")
            //normalized from 0 to 1
//            let foreheadImageFrame = videoCapture.previewLayer!.metadataOutputRectConverted(fromLayerRect: foreheadRect) // какая то херня
            //NOTE: foreheadImageFrame with < than height!
            //video is mirrored by width with portrait orientation
//            let cropRect = CGRect(origin: .init(x: foreheadImageFrame.minX * image.extent.maxX, y: foreheadImageFrame.minY * image.extent.maxY),
//                                  size: .init(width: foreheadImageFrame.maxX * image.extent.maxX, height: foreheadImageFrame.maxY * image.extent.maxY))
            //rotated
//            let cropRect = CGRect(origin: .init(x: foreheadImageFrame.minX * image.extent.maxX, y: foreheadImageFrame.minY * image.extent.maxY),
//                                  size: .init(width: foreheadImageFrame.maxY * image.extent.maxY, height: foreheadImageFrame.maxX * image.extent.maxX))
//            let cropRect = CGRect(origin: o, size: size).applying(transform)
            
            let foreheadImage = imageBufer.cropped(to: foreheadImageFrame)
            signalProcessor.processROI(image: foreheadImage)
//            let fhImg = foreheadImage.cgImage()
            
            
            //see https://developer.apple.com/documentation/vision/cropping_images_using_saliency
//            let rec = VNImageRectForNormalizedRect(foreheadImageFrame,Int(image.extent.size.width),Int(image.extent.size.height))
//            //see https://stackoverflow.com/questions/55132517/incorrect-frame-of-boundingbox-with-vnrecognizedobjectobservation
//            let viewRect = faceViewFrame!
//            let scale = CGAffineTransform.identity.scaledBy(x: viewRect.width, y: viewRect.height)
//            let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -viewRect.height)
//            let observationRect = face.boundingBox.applying(scale).applying(transform)
//
        
//            signalProcessor.handle(imageBuffer: imageBuffer, cropRect: observationRect)
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
        //sizse wuth y with negative value!
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
