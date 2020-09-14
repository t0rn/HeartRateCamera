//
//  ViewController.swift
//  HeartRate
//
//  Created by Alexey Ivanov on 22/12/2018.
//  Copyright © 2018 Alexey Ivanov. All rights reserved.
//

import UIKit
import AVFoundation
import CoreImage

class ViewController: UIViewController {
    
    private var videoCapture: VideoCaptureService!
    @IBOutlet private weak var previewView: UIView!
    
    private let hrBuffer = SignalProcessor()
    
    @IBOutlet private weak var pulseLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let spec = VideoCaptureService.VideoSpec(fps: 10, size: CGSize(width: 300, height: 300))
        videoCapture = VideoCaptureService(cameraType: .back,
                                    preferredSpec: spec,
                                    previewContainer: previewView.layer)
        
        videoCapture.imageBufferHandler = { [unowned self] (buffer) in
            guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {return}
            self.hrBuffer.handle(imageBuffer: imageBuffer)
        }
        
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        videoCapture.startCapture()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] (timer) in
            guard let self = self else {return}
            //print valid frames
            //            let validFrames = min(100, (100*self.hrBuffer.validFrameCounter)/10) //10 is a MIN_FRAMES_FOR_FILTER_TO_SETTLE
            //            print("validFrames \(validFrames)")
            DispatchQueue.main.async {
                self.pulseLabel.text = String(describing:self.hrBuffer.pulse)
            }
        }
        toggleTorch()
    }
    
    @IBAction func buttonPressed(_ sender: Any) {
        toggleTorch()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        videoCapture.stopCapture()
    }
    
    func toggleTorch(){
        guard let device = AVCaptureDevice.default(for: .video) else {return}
        if device.isTorchActive {
            device.toggleTorch(on: false)
        }else {
            device.toggleTorch(on: true)
        }
    }
}

