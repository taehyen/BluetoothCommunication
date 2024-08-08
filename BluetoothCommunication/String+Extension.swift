//
//  String+Extension.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 8/8/24.
//

import Foundation

extension String {
    func toUUID() -> String? {
        var string = self
        if string.count < 16 {
            let spaceString = String(repeating: " ", count: 16 - string.count)
            string += spaceString
        }
        
        guard let data = string.data(using: .utf8) else { return nil }
        let bytesToConvert = data.count
        var outputString = ""
        
        for i in 0..<bytesToConvert {
            let byte = data[i]
            switch i {
                case 3, 5, 7, 9:
                    outputString += String(format: "%02X-", byte)
                default:
                    outputString += String(format: "%02X", byte)
            }
        }
        return outputString
    }
}

