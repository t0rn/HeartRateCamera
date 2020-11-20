//
//  RingBuffer.swift
//  HeartRate
//
//  Created by Alexey Ivanov on 14.06.2020.
//  Copyright © 2020 Alexey Ivanov. All rights reserved.
//

import Foundation

public struct RingBuffer<T> {
    private var array: [T?]
    private var readIndex = 0
    private var writeIndex = 0
    
    public init(count: Int) {
        array = [T?](repeating: nil, count: count)
    }
    
    public var count: Int {
        return availableSpaceForReading
    }
    /* Returns false if out of space. */
    @discardableResult
    public mutating func write(_ element: T) -> Bool {
        guard !isFull else { return false }
        defer {
            writeIndex += 1
        }
        array[wrapped: writeIndex] = element
        return true
    }
    
    /* Returns nil if the buffer is empty. */
    public mutating func read() -> T? {
        guard !isEmpty else { return nil }
        defer {
            array[wrapped: readIndex] = nil
            readIndex += 1
        }
        return array[wrapped: readIndex]
    }
    
    private var availableSpaceForReading: Int {
        return writeIndex - readIndex
    }
    
    public var isEmpty: Bool {
        return availableSpaceForReading == 0
    }
    
    private var availableSpaceForWriting: Int {
        return array.count - availableSpaceForReading
    }
    
    public var isFull: Bool {
        return availableSpaceForWriting == 0
    }
    
    public mutating func removeAll() {
        writeIndex = readIndex
    }
    
    public mutating func readAll() -> [T] {
        guard isEmpty == false else { return [] }
        var result = [T?]()
        while availableSpaceForReading > 0 {
            result.append(read())
        }
        return result.compactMap{$0}
    }
    
    public var first: T? {
        return array[readIndex]
    }
    
    
    public var last: T? {
        guard writeIndex > 0 else {return nil}
        let lastIndex = writeIndex - 1
        return array[wrapped: lastIndex]
    }

}

extension RingBuffer: Sequence {
    public func makeIterator() -> AnyIterator<T> {
        var index = readIndex
        return AnyIterator {
            guard index < self.writeIndex else { return nil }
            defer {
                index += 1
            }
            return self.array[wrapped: index]
        }
    }
}

private extension Array {
    subscript (wrapped index: Int) -> Element {
        get {
            return self[index % count]
        }
        set {
            self[index % count] = newValue
        }
    }
}

extension RingBuffer: CustomStringConvertible {
    public var description: String {
        let values = (0..<availableSpaceForReading).map {
            String(describing: array[($0 + readIndex) % array.count]!)
        }
        return "[" + values.joined(separator: ", ") + "]"
    }
}


public extension RingBuffer {
    subscript (reverted index:Int) -> Element? {
        get {
            guard index < array.count, index >= 0 else {return nil}
            let i = (array.count + writeIndex % array.count - 1 - index) % array.count
            return array[i]
        }
        set {
            let i = (array.count + writeIndex % array.count - 1 - index) % array.count
            array[i] = newValue
        }
    }
}

public extension RingBuffer where T: Comparable {
    ///Returns the index of the last element in collection
    func lastIndex(of element:T) -> Int? {
        return array.lastIndex(of: element)
    }
    
    func firstIndex(of element:T) -> Int? {
        return array.firstIndex(of: element)
    }
}

public extension RingBuffer where T: Comparable {
    ///Returns the index of the last element in collection
    func reversedLastIndex(of element:T) -> Int? {
        return self.reversed().lastIndex(of: element)
    }
    
    func reversedFirstIndex(of element:T) -> Int? {
        return self.reversed().firstIndex(of: element)
    }
}

extension RingBuffer where T: BinaryFloatingPoint {
    func sum() -> T { reduce(.zero, +) }
    
    func average() -> T {
        guard !isEmpty else {return .zero}
        return sum() / T(count)
    }
    
}

