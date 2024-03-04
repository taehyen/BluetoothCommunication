/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Transfer service and characteristics UUIDs
*/

import Foundation
import CoreBluetooth

struct TransferService {
	static let serviceUUID = CBUUID(string: "FFE0")
	static let characteristicUUID = CBUUID(string: "FFE1")
}
