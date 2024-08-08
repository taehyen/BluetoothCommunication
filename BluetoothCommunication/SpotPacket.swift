//
//  SpotPacket.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 8/8/24.
//

import Foundation

struct SpotPacket: Equatable {
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

extension SpotPacket {
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

extension SpotPacket {
    //받을 때
    static func convertUInt8ArrayToDoubles(_ uint8Array: [UInt8]) -> [Double] {
        var doubleArray = [Double]()
        
        // 길이를 8의 배수로 맞추기 위해 필요한 패딩 추가
        var paddedArray = uint8Array
        while paddedArray.count % 8 != 0 {
            paddedArray.append(0)
        }
        
        for i in stride(from: 0, to: paddedArray.count, by: 8) {
            // 8개의 UInt8 요소를 하나의 64비트 정수로 변환
            let uint64Value = paddedArray[i..<i+8].withUnsafeBytes { $0.load(as: UInt64.self) }
            
            // 64비트 정수를 Double로 변환
            let doubleValue = Double(bitPattern: uint64Value)
            
            doubleArray.append(doubleValue)
        }
        
        return doubleArray
    }
    //보낼 때
    static func convertDoublesToUInt8Array(_ doubleArray: [Double]) -> [UInt8] {
        var uint8Array = [UInt8]()
        
        for doubleValue in doubleArray {
            // Double 값의 바이트 표현을 UInt64로 변환
            let uint64Value = doubleValue.bitPattern
            
            // UInt64를 8개의 UInt8 요소로 분할하여 배열에 추가
            uint8Array += withUnsafeBytes(of: uint64Value) { Array($0) }
        }
        
        return uint8Array
    }
}
