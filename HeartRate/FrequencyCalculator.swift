//
//  HRDetector.swift
//  FastICA_CLI
//
//  Created by Alexey Ivanov on 13.06.2020.
//  Copyright © 2020 Alexey Ivanov. All rights reserved.
//

import Foundation
import Accelerate

//TODO: rename
class FrequencyCalculator {
    let sampleRate: Float
    let windowSize: Int  //Should be power of two for the FFT
    let signal: [Float]

    // The bandpass frequencies
    let lowerFreq : Float = 0.33
    let higherFreq: Float = 4
    
    private let fft: FFT
    
    
    lazy var window: [Float] = {
        vDSP.window(ofType: Float.self,
                    usingSequence: .hamming,
                    count: self.windowSize,
                    isHalfWindow: false)
    }()
    
    init(signal: [Float],
         windowSize: Int,
         sampleRate: Float) {
        self.signal = signal
        self.windowSize = windowSize
        self.sampleRate = sampleRate
        fft = FFT(length: windowSize)
    }
        
    ///Returns frequency with max power
    func maxFrequency(phase:[Float], spectrum: [Float]) -> Float {
        let freqs = getFrequencies(signal.count, fps: sampleRate)
        
//        let (_, filteredPhase, filteredSpectrum) = filter(signal: signal, fps: fps)
        
        let maxFrequencyResult = max(spectrum)
        let maxFrequency = freqs[maxFrequencyResult.index]
        let maxPhase = phase[maxFrequencyResult.index]
        
        print("Amplitude: \(maxFrequencyResult.value)")
        print("Frequency: \(maxFrequency)")
        print("Phase: \(maxPhase + .pi / 2)")
        
        return maxFrequency
    }
            
    func filter(signal:[Float]) -> (magnitude: [Float], phase: [Float], spectrum:[Float]) {
        let N = signal.count
        var (fullSpectrum, mag, phase) = fft.forwardTransformation(signal: signal)
        
        // ----------------------------------------------------------------
        // Bandpass Filtering
        // ----------------------------------------------------------------
        
        // Get the Frequencies for the current Framerate
        let freqs = getFrequencies(N,fps: sampleRate)
        // Get a Bandpass Filter
        let bandPassFilter = generateBandPassFilter(freqs)
        
        // Multiply phase and magnitude with the bandpass filter
        mag = mul(mag, y: bandPassFilter.filter)
        phase = mul(phase, y: bandPassFilter.filter)
        
        // Output Variables
        let filteredSpectrum = mul(fullSpectrum, y: bandPassFilter.filter)
        let filteredPhase = phase
        
        return (mag, filteredPhase, filteredSpectrum)
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
    
//    func sqrt(_ x: [Float]) -> [Float] {
//        var results = [Float](repeating: 0.0, count: x.count)
//        vvsqrtf(&results, x, [Int32(x.count)])
//
//        return results
//    }
    
    func max(_ x: [Float]) -> (value:Float, index:Int) {
        var result: Float = 0.0
        var idx : vDSP_Length = vDSP_Length(0)
        vDSP_maxvi(x, 1, &result, &idx, vDSP_Length(x.count))
        
        return (result, Int(idx))
    }
    
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
