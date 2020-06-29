//
//  HRDetector.swift
//  FastICA_CLI
//
//  Created by Alexey Ivanov on 13.06.2020.
//  Copyright © 2020 Alexey Ivanov. All rights reserved.
//

import Foundation
import Accelerate

class FrequencyCalculator {
    let sampleRate: Float
    let windowSize: Int  //Should be power of two for the FFT !
    let signal: [Float]
        
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
    
    func maxFrequency() -> Float {
        let seconds = Float(window.count) / sampleRate
        let fps = Float(window.count) / seconds
        let freq = fft.maxFrequency(signal: signal, fps: fps)
        return freq
    }
}
