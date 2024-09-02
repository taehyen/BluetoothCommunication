/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Transfer service and characteristics UUIDs
*/

import Foundation
import CoreBluetooth

let gSpotProtocolVersion: UInt8 = 0x01

struct TransferService {
    static let serviceUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC0")
    
    //여러개의 characteristic을 사용하려면 각각 정의해야 함.
    static let serverRxCharacteristicUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC1")
    static let serverTxCharacteristicUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC3")
    
    //여러개의 descriptor를 사용하려면 각각 정의해야 함.
    static let descriptorUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC2")
    
    static let characteristics = [serverRxCharacteristicUUID, serverTxCharacteristicUUID]
    
    static let centralName = "Beamo"
    static let peripheralName = "SPOT"
}

enum ServiceType {
    case read
    case write
    case readwrite
}

infix operator <>: MultiplicationPrecedence
enum BluetoothData: Equatable {
    case image(Data)
    case text(Data)
    case binary(SpotPacket)
    case unknown
    
    static func <> (left: BluetoothData, right: BluetoothData) -> Bool {
        switch (left, right) {
            case (.binary(_), .binary(_)):
                return true
            default:
                return false
        }
    }
}
