//
//  VideoCapture.swift
//  HeartRate
//
//  Created by Alexey Ivanov on 22/12/2018.
//  Copyright © 2018 Alexey Ivanov. All rights reserved.
//

import Foundation
import AVFoundation


class VideoCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum CameraType : Int {
        case back
        case front
        case unspecified
        
        func captureDevice() -> AVCaptureDevice {
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: captureDevicePosition).devices
            print("capture devices:\(devices)")
            guard devices.count > 0 else {
                guard let defaultDevice = AVCaptureDevice.default(for: .video) else {
                    fatalError("Can't get a video device for capturing")
                }
                return defaultDevice
            }
            return devices.first!
        }
        
        var captureDevicePosition: AVCaptureDevice.Position {
            switch self {
            case .back: return .back
            case .front: return .front
            case .unspecified: return .unspecified
            }
        }
    }

    
    struct VideoSpec {
        var fps: Int32?
        var size: CGSize?
    }
    
    
    
    var captureAuthorizationStatus: AVAuthorizationStatus {
        //closed caption will crash
        return AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    let session = AVCaptureSession()
    private(set) var videoDevice: AVCaptureDevice!
    private(set) var videoConnection: AVCaptureConnection!
    private var audioConnection: AVCaptureConnection!
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    
    typealias SampleBufferClosure = ((_ imageBuffer: CMSampleBuffer) -> ())
    var outputBuffer: SampleBufferClosure?
    
    init(cameraType: CameraType, preferredSpec: VideoSpec?, previewContainer: CALayer?) {
        super.init()
        #if targetEnvironment(macCatalyst)
        //TODO:use UIImagePickerController
        //see https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture
        #else
        switch captureAuthorizationStatus {
        case .authorized:
            setupCaptureSession(for: cameraType, preferredSpec: preferredSpec, previewContainer: previewContainer)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.setupCaptureSession(for: cameraType, preferredSpec: preferredSpec, previewContainer: previewContainer)
                    }
                }
            }
        case .denied, .restricted:
            // show alert
            break
        @unknown default: break
        }
        #endif
    }
    
    func setupCaptureSession(for cameraType:CameraType, preferredSpec:VideoSpec?, previewContainer: CALayer?) {
        videoDevice = cameraType.captureDevice()
        setupVideoFormat(with: preferredSpec)
        setupDeviceInput()
        if let previewContainer = previewContainer {
            setup(previewContainer:previewContainer)
        }
        setupViewOuput()
    }
    

    
    func setupVideoFormat(with preferredSpec:VideoSpec?) {
//        captureSession.sessionPreset = .low
//        captureSession.sessionPreset = .vga640x480
        if let preferredSpec = preferredSpec {
            videoDevice.updateFormatWithPreferredVideoSpec(preferredSpec: preferredSpec)
        }
    }
    
    func setupDeviceInput() {
        let videoDeviceInput: AVCaptureDeviceInput
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            let device = videoDeviceInput.device
            device.toggleTorch(on: true)
        }
        catch {
            fatalError("Could not create AVCaptureDeviceInput instance with error: \(error).")
        }
        guard session.canAddInput(videoDeviceInput) else {
            fatalError("Can't add input device")
        }
        session.addInput(videoDeviceInput)
    }
    
    func setup(previewContainer: CALayer) {
        DispatchQueue.main.async {
            let previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
            previewLayer.frame = previewContainer.bounds
//            previewLayer.videoGravity = .resizeAspectFill
            previewContainer.insertSublayer(previewLayer, at: 0)
            self.previewLayer = previewLayer
        }
    }
    
    func setupViewOuput() {
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        // [kCVPixelBufferPixelFormatTypeKey as AnyHashable as! String: NSNumber(value: kCVPixelFormatType_32BGRA)]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        let queue = DispatchQueue(label: "com.queue.videosamplequeue")
        videoDataOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoDataOutput) else {
            fatalError()
        }
        session.addOutput(videoDataOutput)
        videoConnection = videoDataOutput.connection(with: .video)
        
        if videoConnection.isVideoOrientationSupported {
            videoConnection.videoOrientation = .portrait
        }
        print("videoConnection.isVideoMirrored: \(videoConnection.isVideoMirrored)")
    }
    
    func startCapture() {
        if session.isRunning {
            return
        }
        session.startRunning()
    }
    
    func stopCapture() {
        print("\(self.classForCoder)/" + #function)
        if !session.isRunning {
            print("already stopped")
            return
        }
        session.stopRunning()
    }
    
    func resizePreview() {
        if let previewLayer = previewLayer {
            guard let superlayer = previewLayer.superlayer else {return}
            previewLayer.frame = superlayer.bounds
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        if let imageBufferHandler = outputBuffer {
            imageBufferHandler(sampleBuffer)
        }
    }
}


extension AVCaptureDevice {
    func toggleTorch(on:Bool) {
        guard hasTorch, isTorchAvailable else {
            print("Torch is not available")
            return
        }
        do {
            try lockForConfiguration()
            torchMode = on ? AVCaptureDevice.TorchMode.on : AVCaptureDevice.TorchMode.off
            unlockForConfiguration()
        }catch {
            print("Torch could not be used \(error)")
        }
    }
}
