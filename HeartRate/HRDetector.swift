//
//  HRDetector.swift
//  FastICA_CLI
//
//  Created by Alexey Ivanov on 13.06.2020.
//  Copyright © 2020 Alexey Ivanov. All rights reserved.
//

import Foundation
import Accelerate

class HRDetector {
    let samplingRate: Float = 10.0
    let windowSize = 256
    let signal: [Float]
    
    private(set) var pageNumber: Int = 0
    private let fft: FFT
    
    lazy var window: [Float] = {
        vDSP.window(ofType: Float.self,
                    usingSequence: .hamming,
                    count: self.windowSize, //Should be power of two for the FFT !
                    isHalfWindow: false)
    }()
    
    init(signal: [Float]) {
        self.signal = signal
        fft = FFT(length: windowSize)
    }
    
    func calcHR() -> [Float] { //TODO: bufferize and return average
        let totalPages = signal.count/windowSize
        let seconds = Float(window.count) / samplingRate
        let fps = Float(window.count) / seconds
        
        let hrValues = (0...totalPages)
            .map{_ in  fft.caltHR(signal: getSignal(), fps: fps) }
                    
        return hrValues
    }
    
    private func getSignal() -> [Float] {
        let start = pageNumber * windowSize
        let end = (pageNumber + 1) * windowSize
        
        let page = Array(signal[start ..< end])
        
        pageNumber += 1
        
        if (pageNumber + 1) * windowSize >= signal.count {
            pageNumber = 0
        }
        
        return page
    }
    
}
