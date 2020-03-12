//
//  SignalProcessor.swift
//  HeartRate
//
//  Created by Alexey Ivanov on 12.01.2020.
//  Copyright © 2020 Alexey Ivanov. All rights reserved.
//

import UIKit

class SignalProcessor {
    private let pulseDetector = PulseDetector()
    private(set) var validFrameCounter = 0
    private var hueFilter = Filter()
    private var inputs: [CGFloat] = []
    private(set) var colors: [UIColor] = []
    
    private let ciContext = CIContext(options: [.workingColorSpace: kCFNull])
    
    var pulse:Float {
        return 60.0/average
    }
    
    var average:Float {
        return pulseDetector.getAverage()
    }
    
    func handle(imageBuffer: CVImageBuffer, cropRect:CGRect? = nil) {

        guard let inputCGImage = CIImage(cvImageBuffer: imageBuffer).cgImage() else {return}
        var inputImage = CIImage(cgImage: inputCGImage)
        
        if let cropRect = cropRect {
            inputImage = inputImage.cropped(to: cropRect)
        }
        print("inputImage after crop \(inputImage)")
        
        guard inputImage.extent.isEmpty == false,
            let averageColor = inputImage.averageColor(in:ciContext) else {
                print("Cant create averageColor!")
                return
        }
        guard let cgImage = averageColor.cgImage() else {
            print("Cant create cgImage!")
            return
        }
        print(cgImage)
        var redmean:CGFloat = 0.0;
        var greenmean:CGFloat = 0.0;
        var bluemean:CGFloat = 0.0;

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
        print("hsv: \(hsv)")

////        let color = UIColor(red: redmean/255.0, green: greenmean/255.0, blue: bluemean/255.0, alpha: 1.0)
        colors.append(averageColor)
        print("averageColor \(averageColor)" )
        
        // do a sanity check to see if a finger is placed over the camera
        if(hsv.1>0.01  && hsv.2>50) {
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
        } else {
            //uncomment for writing into txt file
            //            try? inputs.map{ String(describing: $0) }
            //                .joined(separator: "\n")
            //                .write()
            
            print("Put finger on camera!")
            //TODO: delegate!
            //                DispatchQueue.main.async {
            //                    self.pulseLabel.text = "Put your finger on camera!"
            //                }
            validFrameCounter = 0
            pulseDetector.reset()
        }
    }
}

extension CIImage {
    func averageColor(in context:CIContext = CIContext(options: [.workingColorSpace: kCFNull])) -> UIColor? {
        let inputImage = self
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else {
            return nil
        }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        return UIColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, alpha: CGFloat(bitmap[3]) / 255)
    }
}
extension UIColor {
    
    ///returns solid color image
    func cgImage(size:CGSize = CGSize(width: 1, height: 1)) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0.0)
        self.setFill()
        UIRectFill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = image?.cgImage else { return nil }
        return cgImage
    }
    
    func image(size:CGSize = CGSize(width: 1, height: 1)) -> UIImage? {
        guard let cgImage = self.cgImage() else {return nil}
        return UIImage(cgImage: cgImage)
    }
}

extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        return inputImage.averageColor()
    }
}


public extension UIImage {
    
    func getPixelColor(at point: CGPoint) -> UIColor {
        guard
            let cgImage = cgImage,
            let cgData = cgImage.dataProvider?.data,
            let pixelData = CGDataProvider(data: cgData)?.data,
            let data = CFDataGetBytePtr(pixelData)
            else { return UIColor.clear }
        
        let x = Int(point.x)
        let y = Int(point.y)
        let index = Int(size.width) * y + x
        let expectedLengthA = Int(size.width * size.height)
        let expectedLengthGrayScale = 2 * expectedLengthA
        let expectedLengthRGB = 3 * expectedLengthA
        let expectedLengthRGBA = 4 * expectedLengthA
        let numBytes = CFDataGetLength(pixelData)
        switch numBytes {
        case expectedLengthA:
            return UIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(data[index])/255.0)
        case expectedLengthGrayScale:
            return UIColor(white: CGFloat(data[2 * index]) / 255.0, alpha: CGFloat(data[2 * index + 1]) / 255.0)
        case expectedLengthRGB:
            return UIColor(red: CGFloat(data[3*index])/255.0, green: CGFloat(data[3*index+1])/255.0, blue: CGFloat(data[3*index+2])/255.0, alpha: 1.0)
        case expectedLengthRGBA:
            return UIColor(red: CGFloat(data[4*index])/255.0, green: CGFloat(data[4*index+1])/255.0, blue: CGFloat(data[4*index+2])/255.0, alpha: CGFloat(data[4*index+3])/255.0)
        default:
            // unsupported format
            return UIColor.clear
        }
    }
}

import CoreImage

extension CIImage {
  func cgImage() -> CGImage? {
    if cgImage != nil {
      return cgImage
    }
    return CIContext().createCGImage(self, from: extent)
  }
}
