//
//  Matrix.swift
//  FastICA_CLI
//
//  Created by Alexey Ivanov on 31.05.2020.
//  Copyright © 2020 Alexey Ivanov. All rights reserved.
//

import Foundation

//borrowed from https://github.com/Jounce/Surge
public struct Matrix<Scalar> where Scalar: FloatingPoint, Scalar: ExpressibleByFloatLiteral {
    typealias Vector = [Scalar]
    
    let rows: Int
    let columns: Int
    
    private(set) var elements: Vector
    
    public init(rows: Int, columns: Int, repeatedValue: Scalar) {
        self.rows = rows
        self.columns = columns

        self.elements = [Scalar](repeating: repeatedValue, count: rows * columns)
    }
    
    init(_ elements: [Vector]) {
        self.init(rows: elements.count, columns: elements.first!.count, repeatedValue: 0.0)
        for (i, row) in elements.enumerated() {
            precondition(row.count == columns, "All rows should have the same number of columns")
            self.elements.replaceSubrange(i * columns..<(i + 1) * columns, with: row)
        }
    }
}

extension Matrix: CustomStringConvertible {
    public var description: String {
        var description = ""

        for i in 0..<rows {
            let contents = (0..<columns).map { "\(self[i, $0])" }.joined(separator: "\t")

            switch (i, rows) {
            case (0, 1):
                description += "(\t\(contents)\t)"
            case (0, _):
                description += "⎛\t\(contents)\t⎞"
            case (rows - 1, _):
                description += "⎝\t\(contents)\t⎠"
            default:
                description += "⎜\t\(contents)\t⎥"
            }

            description += "\n"
        }

        return description
    }
}

extension Matrix: Collection {
    
    public subscript(_ row: Int) -> ArraySlice<Scalar> {
        let startIndex = row * columns
        let endIndex = startIndex + columns
        return self.elements[startIndex..<endIndex]
    }

    public var startIndex: Int {
        return 0
    }

    public var endIndex: Int {
        return self.rows
    }

    public func index(after i: Int) -> Int {
        return i + 1
    }
}

extension Matrix {
    // MARK: - Subscript

    public subscript(row: Int, column: Int) -> Scalar {
        get {
            assert(indexIsValidForRow(row, column: column))
            return elements[(row * columns) + column]
        }

        set {
            assert(indexIsValidForRow(row, column: column))
            elements[(row * columns) + column] = newValue
        }
    }

    public subscript(row row: Int) -> [Scalar] {
        get {
            assert(row < rows)
            let startIndex = row * columns
            let endIndex = row * columns + columns
            return Array(elements[startIndex..<endIndex])
        }

        set {
            assert(row < rows)
            assert(newValue.count == columns)
            let startIndex = row * columns
            let endIndex = row * columns + columns
            elements.replaceSubrange(startIndex..<endIndex, with: newValue)
        }
    }

    public subscript(column column: Int) -> [Scalar] {
        get {
            var result = [Scalar](repeating: 0.0, count: rows)
            for i in 0..<rows {
                let index = i * columns + column
                result[i] = self.elements[index]
            }
            return result
        }

        set {
            assert(column < columns)
            assert(newValue.count == rows)
            for i in 0..<rows {
                let index = i * columns + column
                elements[index] = newValue[i]
            }
        }
    }

    private func indexIsValidForRow(_ row: Int, column: Int) -> Bool {
        return row >= 0 && row < rows && column >= 0 && column < columns
    }
}
