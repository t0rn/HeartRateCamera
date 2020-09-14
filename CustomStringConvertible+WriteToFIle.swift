//
//  CustomStringConvertible+WriteToFIle.swift
//  HeartRate
//
//  Created by Alexey Ivanov on 20.07.2019.
//  Copyright © 2019 Alexey Ivanov. All rights reserved.
//

import Foundation

extension CustomStringConvertible {
    func write(fileName:String = "tmp.txt",
               directory: URL = URL(fileURLWithPath:NSTemporaryDirectory())) throws {
        let url =  directory.appendingPathComponent(fileName, isDirectory: false)
        let toWrite = description + "\r\n"
        return try toWrite.write(to: url, atomically: true, encoding: .utf8)        
    }
}

