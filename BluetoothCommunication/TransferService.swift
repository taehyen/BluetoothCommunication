/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Transfer service and characteristics UUIDs
*/

import Foundation
import CoreBluetooth

struct TransferService {
	static let serviceUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC0")
    //여러개의 characteristic을 사용하려면 각각 정의해야 함.
	static let textCharacteristicUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC1")
    static let imageCharacteristicUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC3")
    
    //여러개의 descriptor를 사용하려면 각각 정의해야 함.
    static let descriptorUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC2")
    
    static let characteristics = [textCharacteristicUUID, imageCharacteristicUUID]
    
    static let centralName = "Beamo Central"
    static let peripheralName = "Beamo Peripheral"
}

enum BluetoothData {
    case image(Data)
    case text(Data)
    case binary(Data)
}

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
