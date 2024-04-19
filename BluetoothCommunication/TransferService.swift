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
    static let binaryCharacteristicUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC1")
    static let imageCharacteristicUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC3")
    static let textCharacteristicUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC5")
    
    //여러개의 descriptor를 사용하려면 각각 정의해야 함.
    static let descriptorUUID = CBUUID(string: "EFF6DB99-3B96-42E9-9640-8A582EEEEBC2")
    
    static let characteristics = [textCharacteristicUUID, imageCharacteristicUUID]
    
    static let centralName = "Beamo Central"
    static let peripheralName = "Beamo Peripheral"
}

enum ServiceType {
    case notDefined
    case imageOnly
    case textOnly
    case binaryOnly
}

infix operator <>: MultiplicationPrecedence
enum BluetoothData: Equatable {
    case image(Data)
    case text(Data)
    case binary(Packet)
    case unknown
    
    static func <> (left: BluetoothData, right: BluetoothData) -> Bool {
        switch (left, right) {
            case (.image(_), .image(_)):
                return true
            case (.text(_), .text(_)):
                return true
            case (.binary(_), .binary(_)):
                return true
            default:
                return false
        }
    }
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

struct Packet: Equatable {
    var header: [UInt8] = [0x24, 0xBF]
    var protocolVersion: UInt8 = 0x00
    var commandGroup: UInt8 = 0x00
    var commandId: UInt8 = 0x00
    var bodyLength: UInt8 = 0x00
    var body: [UInt8] = []
    
    var data: Data {
        let byteArray: [UInt8] = header + [protocolVersion, commandGroup, commandId, bodyLength] + body
        return Data(byteArray)
    }
}

extension Packet {
    init(bytes: [UInt8]) {
        guard bytes.count >= 6 else {
            log.error("수신된 데이터가 짧음.")
            return
        }
        let header = [bytes[0], bytes[1]]
        guard self.header == header else {
            log.error("header가 잘못되었음.")
            return
        }
        protocolVersion = bytes[2]
        guard gSpotProtocolVersion == protocolVersion else {
            log.error("version이 다름")
            return
        }
        commandGroup = bytes[3]
        commandId = bytes[4]
        let length = Int(bytes[5])
        
        guard bytes.count >= length+6 else {
            log.error("length와 data 크기가 다름")
            return
        }
        
        let body = bytes[6..<(length+6)]
        bodyLength = bytes[5]
        self.body = Array(body)
        
        log.verbose("정상적으로 Packet데이터가 설정됨.")
    }
}
