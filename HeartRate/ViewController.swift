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
    
    private var validFrameCounter = 0
    private var videoCapture: VideoCapture!
    @IBOutlet private weak var previewView: UIView!
    private var hueFilter = Filter()
    private var pulseDetector = PulseDetector()
    private var inputs: [CGFloat] = []
    
    @IBOutlet private weak var pulseLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let spec = VideoSpec(fps: 10, size: CGSize(width: 300, height: 300))
        videoCapture = VideoCapture(cameraType: .back,
                                    preferredSpec: spec,
                                    previewContainer: previewView.layer)
        
        videoCapture.imageBufferHandler = { [unowned self] (imageBuffer) in
            self.handle(buffer: imageBuffer)
        }
        
    
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        videoCapture.startCapture()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] (timer) in
            guard let self = self else {return}
            //print valid frames
            let validFrames = min(100, (100*self.validFrameCounter)/10) //10 is a MIN_FRAMES_FOR_FILTER_TO_SETTLE
            print("validFrames \(validFrames)")
            let average = self.pulseDetector.getAverage()
            print("average \(average)")
            let pulse = 60.0/average
            
            self.pulseLabel.text = String(describing:pulse)
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

extension ViewController {
    func handle(buffer:CMSampleBuffer) {
        
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
        }else {
            //uncomment for writing into txt file
//            try? inputs.map{ String(describing: $0) }
//                .joined(separator: "\n")
//                .write()
            
            print("Put finger on camera!")
            self.pulseLabel.text = "Put your finger on camera!"
            validFrameCounter = 0
            pulseDetector.reset()
        }
    }
}
