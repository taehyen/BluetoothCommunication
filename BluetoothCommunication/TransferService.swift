/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Transfer service and characteristics UUIDs
*/

import Foundation
import CoreBluetooth

struct TransferService {
	static let serviceUUID = CBUUID(string: "FFE0")
    
    //여러개의 characteristicUUID를 사용하려면 각각 정의해야 함.
	static let characteristicUUID = CBUUID(string: "FFE1")

    static let centralName = "Beamo Central"
    static let peripheralName = "Beamo Peripheral"
}
