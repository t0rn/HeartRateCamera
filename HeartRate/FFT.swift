//
//  FFT.swift
//  FastICA_CLI
//
//  Created by Alexey Ivanov on 03.06.2020.
//  Copyright © 2020 Alexey Ivanov. All rights reserved.
//

import Foundation
import Accelerate


class FFT {
    enum TransformationType {
        case forward
    }
    
    let length: Int
    let fftSetUp: vDSP.FFT<DSPSplitComplex>
    
    init(length: Int){
        self.length = length
        let log2n = vDSP_Length(log2(Float(length)))
        self.fftSetUp = vDSP.FFT(log2n: log2n,
                                 radix: .radix2,
                                 ofType: DSPSplitComplex.self)!
    }
    
    func caltHR(signal:[Float], fps: Float) -> Float {
        //Create the Source and Destination Arrays for the Forward FFT
        //The FFT operates on complex numbers, that is numbers that contain a real part and an imaginary part. Create two arrays—one for the real parts and one for the imaginary parts—for the input and output to the FFT operation:
        let N = signal.count
        let halfN = N / 2
        
        var forwardInputReal = [Float](repeating: 0,
                                       count: halfN)
        var forwardInputImag = [Float](repeating: 0,
                                       count: halfN)
        var forwardOutputReal = [Float](repeating: 0,
                                        count: halfN)
        var forwardOutputImag = [Float](repeating: 0,
                                        count: halfN)
        
        // For polar coordinates
        var magnitudes = [Float](repeating: 0, count: halfN)
        
        var mag = [Float](repeating: 0, count: halfN)
        var phase = [Float](repeating: 0, count: halfN)
        
        
        var fftMagnitudes = [Float](repeating: 0.0, count: halfN)
        
        var fullSpectrum = [Float](repeating: 0.0, count: halfN)
        
        forwardInputReal.withUnsafeMutableBufferPointer { forwardInputRealPtr in
            forwardInputImag.withUnsafeMutableBufferPointer { forwardInputImagPtr in
                forwardOutputReal.withUnsafeMutableBufferPointer { forwardOutputRealPtr in
                    forwardOutputImag.withUnsafeMutableBufferPointer { forwardOutputImagPtr in
                        
                        // 1: Create a `DSPSplitComplex` to contain the signal.
                        var forwardInput = DSPSplitComplex(realp: forwardInputRealPtr.baseAddress!,
                                                           imagp: forwardInputImagPtr.baseAddress!)
                        
                        // 2: Convert the real values in `signal` to complex numbers.
                        signal.withUnsafeBytes {
                            vDSP.convert(interleavedComplexVector: [DSPComplex]($0.bindMemory(to: DSPComplex.self)),
                                         toSplitComplexVector: &forwardInput)
                        }
                        
                        // 3: Create a `DSPSplitComplex` to receive the FFT result.
                        var forwardOutput = DSPSplitComplex(realp: forwardOutputRealPtr.baseAddress!,
                                                            imagp: forwardOutputImagPtr.baseAddress!)
                        
                        // 4: Perform the forward FFT.
                        fftSetUp.forward(input: forwardInput,
                                         output: &forwardOutput)
                        
                        vDSP.absolute(forwardOutput, result: &magnitudes)
                        
                        
                        // ----------------------------------------------------------------
                        // Get the Frequency Spectrum
                        // ----------------------------------------------------------------
                        
                        vDSP_zvmags(&forwardOutput, 1, &fftMagnitudes, 1, vDSP_Length(halfN))
                        
                        //vDSP_zvmags returns squares of the FFT magnitudes, so take the root here
                        let roots = sqrt(fftMagnitudes)
                        // Normalize the Amplitudes
                        
                        vDSP_vsmul(roots, vDSP_Stride(1), [1.0 / Float(N)], &fullSpectrum, 1, vDSP_Length(halfN))
                        // ----------------------------------------------------------------
                        // Convert from complex/rectangular (real, imaginary) coordinates
                        // to polar (magnitude and phase) coordinates.
                        // ----------------------------------------------------------------
                        vDSP_zvabs(&forwardOutput, 1, &mag, 1, vDSP_Length(halfN))
                        
                        // Beware: Outputted phase here between -PI and +PI
                        // https://developer.apple.com/library/prerelease/ios/documentation/Accelerate/Reference/vDSPRef/index.html#//apple_ref/c/func/vDSP_zvphasD
                        vDSP_zvphas(&forwardOutput, 1, &phase, 1, vDSP_Length(halfN))
                        
                    }
                }
            }
        }
        
        // ----------------------------------------------------------------
        // Bandpass Filtering
        // ----------------------------------------------------------------
        
        // Get the Frequencies for the current Framerate
        let freqs = getFrequencies(N,fps: fps)
        // Get a Bandpass Filter
        let bandPassFilter = generateBandPassFilter(freqs)
        
        // Multiply phase and magnitude with the bandpass filter
        mag = mul(mag, y: bandPassFilter.filter)
        phase = mul(phase, y: bandPassFilter.filter)
        
        // Output Variables
        let filteredSpectrum = mul(fullSpectrum, y: bandPassFilter.filter)
        let filteredPhase = phase
        
        // ----------------------------------------------------------------
        // Determine Maximum Frequency
        // ----------------------------------------------------------------
        let maxFrequencyResult = max(filteredSpectrum)
        let maxFrequency = freqs[maxFrequencyResult.index]
        let maxPhase = filteredPhase[maxFrequencyResult.index]
        
        print("Amplitude: \(maxFrequencyResult.value)")
        print("Frequency: \(maxFrequency)")
        print("Phase: \(maxPhase + .pi / 2)")
        
        let hr = maxFrequency * 60.0
        return hr
    }
        
    fileprivate func getFrequencies(_ N: Int, fps: Float) -> [Float] {
        // Create an Array with the Frequencies
        let freqs = (0..<N/2).map {
            fps/Float(N) * Float($0)
        }
        return freqs
    }
    
    
    
    // Some Math functions on Arrays
    func mul(_ x: [Float], y: [Float]) -> [Float] {
        var results = [Float](repeating: 0.0, count: x.count)
        vDSP_vmul(x, 1, y, 1, &results, 1, vDSP_Length(x.count))

        return results
    }
    
    func sqrt(_ x: [Float]) -> [Float] {
        var results = [Float](repeating: 0.0, count: x.count)
        vvsqrtf(&results, x, [Int32(x.count)])

        return results
    }
    
    func max(_ x: [Float]) -> (value:Float, index:Int) {
        var result: Float = 0.0
        var idx : vDSP_Length = vDSP_Length(0)
        vDSP_maxvi(x, 1, &result, &idx, vDSP_Length(x.count))

        return (result, Int(idx))
    }
    
    // The bandpass frequencies
    let lowerFreq : Float = 0.33
    let higherFreq: Float = 4
    
    fileprivate func generateBandPassFilter(_ freqs: [Float]) -> (filter: [Float], minIdx: Int, maxIdx: Int) {
        var minIdx = freqs.count+1
        var maxIdx = -1
        
        let bandPassFilter: [Float] = freqs.map {
            if ($0 >= self.lowerFreq && $0 <= self.higherFreq) {
                return 1.0
            } else {
                return 0.0
            }
        }
        
        for (i, element) in bandPassFilter.enumerated() {
            if (element == 1.0) {
                if(i<minIdx || minIdx == freqs.count+1) {
                    minIdx=i
                }
                if(i>maxIdx || maxIdx == -1) {
                    maxIdx=i
                }
            }
        }
        
        assert(maxIdx != -1)
        assert(minIdx != freqs.count+1)
        
        return (bandPassFilter, minIdx, maxIdx)
    }
}

func fftfreq(windowSize n:Int, timestep d:Float) -> [Float] {
    let val = 1.0/(Float(n) * d)
    let N = (n-1)/2 + 1
    var result = Array(0...N).map{Float($0)}
    //fill half of results p1 and p2
    let p2 = -(n/2)...0
    result.append(contentsOf: p2.map{Float($0)})
    return result.map{$0 * val}
}


