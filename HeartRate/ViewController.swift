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
        let spec = VideoSpec(fps: 10, size: CGSize(width: 299, height: 299))
        videoCapture = VideoCapture(cameraType: .back,
                                    preferredSpec: spec,
                                    previewContainer: previewView.layer)
        
        videoCapture.imageBufferHandler = { [unowned self] (imageBuffer) in
            //TODO: handle image buffer
            //TODO: increment counter
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
        print("R:\(redmean) G:\(greenmean) B:\(bluemean)")
        
        let hsv = rgb2hsv((red:redmean, green: greenmean,blue: bluemean,alpha: 1.0))
        print("H:\(hsv.0) S:\(hsv.1) V:\(hsv.2)")
        
        // do a sanity check to see if a finger is placed over the camera
        if(hsv.1>0.5 && hsv.2>0.5) {
            print("finger on torch")
            validFrameCounter += 1
            inputs.append(hsv.0)
            // filter the hue value - the filter is a simple band pass filter that removes any DC component
            //and any high frequency noise
            let filtered = hueFilter.processValue(Float(hsv.0))
            print("fitered: \(filtered)")
            // have we collected enough frames for the filter to settle?
            //TODO: use constant MIN_FRAMES_FOR_FILTER_TO_SETTLE for exameple
            if validFrameCounter > 10 {
                self.pulseDetector.addNewValue(filtered, atTime: CACurrentMediaTime())
            }
        }else {
            try? inputs.map{ String(describing: $0) }
                .joined(separator: "\n")
                .write()
            
            print("Put finger on camera!")
            validFrameCounter = 0
            pulseDetector.reset()
        }
    }
    /*
    func handleBuffer(_ buffer:CMSampleBuffer) {
        // only run if we're not already processing an image
        // this is the image buffer
        guard let cvimgRef =  CMSampleBufferGetImageBuffer(imageBuffer) else {return}
        // Lock the image buffer
        CVPixelBufferLockBaseAddress(cvimgRef,[])
        // access the data
        let width = CVPixelBufferGetWidth(cvimgRef)
        let height = CVPixelBufferGetHeight(cvimgRef)
        // get the raw image bytes
        let buf = CVPixelBufferGetBaseAddress(cvimgRef)
        //bytes per row
        let bprow = CVPixelBufferGetBytesPerRow(cvimgRef)
        var r:Float = 0
        var g:Float = 0
        var b:Float = 0
        
        let widthScaleFactor = width/192
        let heightScaleFactor = height/144
        // Get the average rgb values for the entire image.
        //            (0..<height).forEach({ (y) in
        //                (0..<width*4).forEach({ (x) in
        //                    //
        //                })
        //            })
        // Get the average rgb values for the entire image.
        for var y = 0; y < height; y+=heightScaleFactor {
            for var x=0; x < width*4; x+=(4*widthScaleFactor) {
                b+=buf[x];
                g+=buf[x+1];
                r+=buf[x+2];
                // a+=buf[x+3];
            }
            buf+=bprow;
        }
        r/=255*(float) (width*height/widthScaleFactor/heightScaleFactor);
        g/=255*(float) (width*height/widthScaleFactor/heightScaleFactor);
        b/=255*(float) (width*height/widthScaleFactor/heightScaleFactor);
    }
 */
}



extension CustomStringConvertible {
    func write(fileName:String = "tmp.txt", directory: URL = URL(fileURLWithPath:NSTemporaryDirectory()) ) throws {
        let url =  directory.appendingPathComponent(fileName, isDirectory: false)
        let toWrite = description + "\r\n"
        print("Writing \(toWrite) into url: \(url)")
        
        guard true == FileManager.default.fileExists(atPath: url.path) else {
            return try toWrite.write(to: url, atomically: true, encoding: .utf8)
        }
        var content = try String(contentsOf: url)
        content.append(toWrite)
        return try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
