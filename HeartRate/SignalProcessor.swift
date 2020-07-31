//
//  SignalProcessor.swift
//  HeartRate
//
//  Created by Alexey Ivanov on 12.01.2020.
//  Copyright © 2020 Alexey Ivanov. All rights reserved.
//

import UIKit
import ClibICA


class SignalProcessor {
    struct ColorSignal: CustomStringConvertible {
        let red: Float
        let green: Float
        let blue: Float
        
        var description: String {
            "\(red);\(green);\(blue)"
        }
    }
    
    let windowSize = 256
    let sampleRate: Float = 30.0
    
    private(set) var inputSignal = [ColorSignal]()
    
    //for debugging mode
    //after fastICA
    private(set) var filteredSignal = [ColorSignal]()
    //pr power?
    private(set) var filteredSpectrum:[[Float]] = {
        let red = [Float]()
        let green = [Float]()
        let blue = [Float]()
        return [red,green,blue]
    }()  //R G B
 
    private lazy var buffer: RingBuffer<ColorSignal> = {
        return RingBuffer<ColorSignal>(count: windowSize)
    }()
    
    private(set) var hrBuffer = RingBuffer<Float>(count:10)
    private(set) var colors: [UIColor] = []
        
    var averageHR: Float {
        return hrBuffer.average()
    }
    
    private let ciContext = CIContext(options: [.workingColorSpace: kCFNull])
            
    func handle(imageBuffer: CVImageBuffer, cropRect:CGRect? = nil) {
        guard let inputCGImage = CIImage(cvImageBuffer: imageBuffer).cgImage() else {return}
        var inputImage = CIImage(cgImage: inputCGImage)
        
        if let cropRect = cropRect {
            inputImage = inputImage.cropped(to: cropRect)
        }
//        print("inputImage after crop \(inputImage)")
        
        guard inputImage.extent.isEmpty == false,
            let averageColor = inputImage.averageColor(in:ciContext) else {
                print("Cant create averageColor!")
                return
        }
        guard let averateColorCGImage = averageColor.cgImage() else {
            print("Cant create cgImage!")
            return
        }
        
        colors.append(averageColor)
        
        var redmean:CGFloat = 0.0
        var greenmean:CGFloat = 0.0
        var bluemean:CGFloat = 0.0

        let rawData:NSData = averateColorCGImage.dataProvider!.data!
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
        
        let colorSignal = ColorSignal(red: Float(redmean),
                                      green: Float(greenmean),
                                      blue: Float(bluemean))
        inputSignal.append(colorSignal)
        buffer.write(colorSignal)
        //estimate color signal every second
        if buffer.isFull {
            calcICA(inputSignal.suffix(windowSize), componentsCount: 3)
            //remove elements (sampleRate)
            _ = (0...Int(sampleRate)).map{_ in buffer.read()}
        }
////        let color = UIColor(red: redmean/255.0, green: greenmean/255.0, blue: bluemean/255.0, alpha: 1.0)
        
    }
    
    //TODO: float vs double
    func calcICA(_ input: [ColorSignal], componentsCount: Int) {
        let signal = input.map{ colorSignal -> [Double] in
            [Double(colorSignal.red), Double(colorSignal.green), Double(colorSignal.blue)]
        }
        let rows = signal.count
        let columns = signal.first!.count
        
        let X = UnsafeMutablePointer<UnsafeMutablePointer<Double>?>.allocate(capacity: rows)
        X.initialize(repeating: nil, count: rows)
        
        var rowPointers = [UnsafeMutablePointer<Double>]()
                
        for (rowIndex, rowValue) in signal.enumerated() {
            let p = UnsafeMutablePointer<Double>.allocate(capacity: columns)
            p.initialize(repeating: 0, count: columns)
            rowPointers.append(p)
            rowValue.enumerated().forEach { (colIndex, colValue) in
                X[rowIndex] = p
                X[rowIndex]?[colIndex] = colValue
            }
        }
        
        defer {
            rowPointers.forEach{ pointer in
                pointer.deinitialize(count: columns)
                pointer.deallocate()
            }
            S?.deinitialize(count: columns)
            S?.deallocate()
        }
        
        let S = calcFastICA(X, Int32(rows), Int32(columns), Int32(componentsCount))
        //convert to matrix
        guard let pointer = S else {return}
        var components = [[Double]]()
        for r in 0..<rows {
            var cols = [Double]()
            for c in 0..<columns {
                let value = pointer[r]![c]
                cols.append(value)
            }
            components.append(cols)
        }
        let M = Matrix<Double>(components)
        
        //find frequiency with max power
        
        var redFreqs = [Float](repeating: 0.0, count: windowSize)
        var greenFreq = [Float](repeating: 0.0, count: windowSize)
        var blueFreqs = [Float](repeating: 0.0, count: windowSize)
        
        
        for c in 0..<M.columns {
            let col = M[column:c]
            let signal = Array(col.map{Float($0)})
            let detector = FrequencyCalculator(signal: signal, windowSize: windowSize, sampleRate: sampleRate)
            if c == 0 {
                print("Red signal")
                let (_, phase, spectrum) = detector.filter(signal: signal)
                filteredSpectrum[0] = spectrum
                redFreqs.append(detector.maxFrequency(phase: phase, spectrum: spectrum))
            }
            if  c == 1 {
                print("Green signal")
                let (_, phase, spectrum) = detector.filter(signal: signal)
                filteredSpectrum[1] = spectrum
                greenFreq.append(detector.maxFrequency(phase: phase, spectrum: spectrum))
            }
            if c == 2 {
                print("Blue signal")
                let (_, phase, spectrum) = detector.filter(signal: signal)
                filteredSpectrum[2] = spectrum
                blueFreqs.append(detector.maxFrequency(phase: phase, spectrum: spectrum))
            }
        }
//        guard let maxFreq = freqs.max() else { return }
        if let rMax = redFreqs.max(),
            let gMax = greenFreq.max(),
            let bMax = blueFreqs.max() {
            let rHR = rMax * 60.0
            print("Red HR: \(rHR)")
            let gHR = gMax * 60.0
            print("Green HR: \(gHR)")
            let bHR = bMax * 60.0
            print("Blue HR: \(bHR)")
            
            let hr = [rMax,gMax,bMax].max()! * 60.0
            print("max HR: \(hr)")
            
            filter(hrValue: hr)
        }
    }
    
    
    func filter(hrValue:Float, hrThreshold:Float = 10 ) {
        if hrBuffer.isFull {
            if let lastHr = hrBuffer.last {
                if abs(hrValue - lastHr) > hrThreshold {
                    print("do not write new HR value!")
                    return
                }
            }
        }
        hrBuffer.write(hrValue)
    }
    
    
    func stop() {
        
        //TODO: delegate!
        //                DispatchQueue.main.async {
        //                    self.pulseLabel.text = "Put your finger on camera!"
        //                }
        
        if inputSignal.count > 0 {
            try? inputSignal.map{ String(describing: $0) }
                .joined(separator: "\n")
                .write(fileName:"colorSignal.txt")
        }
        
        try? hrBuffer
            .map{ String(describing: $0) }
            .write(fileName: "hrBuffer.txt")
        
        try? buffer
            .map{ String(describing: $0) }
            .joined(separator: "\n")
            .write(fileName: "SignalBuffer.txt")
        
        try? filteredSpectrum
            .map{ String(describing: $0) }
            .write(fileName: "FilteredSpectrum.txt")
        
        inputSignal.removeAll()
        buffer.removeAll()
        hrBuffer.removeAll()
//        if red.count > 0 {
//            try? red.map{ String(describing: $0) }
//            .joined(separator: "\n")
//            .write(fileName:"red.txt")
//        }
                
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
