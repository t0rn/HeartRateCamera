/// Copyright (c) 2019 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import Vision

class FaceView: UIView {
  var leftEye: [CGPoint] = []
  var rightEye: [CGPoint] = []
  var leftEyebrow: [CGPoint] = []
  var rightEyebrow: [CGPoint] = []
  var nose: [CGPoint] = []
  var outerLips: [CGPoint] = []
  var innerLips: [CGPoint] = []
  var faceContour: [CGPoint] = []

  var boundingBox = CGRect.zero
  
  func clear() {
    leftEye = []
    rightEye = []
    leftEyebrow = []
    rightEyebrow = []
    nose = []
    outerLips = []
    innerLips = []
    faceContour = []
    
    boundingBox = .zero
    
    DispatchQueue.main.async {
      self.setNeedsDisplay()
    }
  }
  
  override func draw(_ rect: CGRect) {
    // 1
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    // 2
    context.saveGState()

    // 3
    defer {
      context.restoreGState()
    }

    // 4
    context.addRect(boundingBox)

    // 5
    UIColor.red.setStroke()

    // 6
    context.strokePath()

    // 1
    UIColor.white.setStroke()

    if !leftEye.isEmpty {
      // 2
      context.addLines(between: leftEye)

      // 3
      context.closePath()

      // 4
      context.strokePath()
    }

    if !rightEye.isEmpty {
      context.addLines(between: rightEye)
      context.closePath()
      context.strokePath()
    }

    if !leftEyebrow.isEmpty {
      context.addLines(between: leftEyebrow)
      context.strokePath()
    }

    if !rightEyebrow.isEmpty {
      context.addLines(between: rightEyebrow)
      context.strokePath()
    }

    if !nose.isEmpty {
      context.addLines(between: nose)
      context.strokePath()
    }

    if !outerLips.isEmpty {
      context.addLines(between: outerLips)
      context.closePath()
      context.strokePath()
    }

    if !innerLips.isEmpty {
      context.addLines(between: innerLips)
      context.closePath()
      context.strokePath()
    }

    if !faceContour.isEmpty {
      context.addLines(between: faceContour)
      context.strokePath()
    }
  }
}
