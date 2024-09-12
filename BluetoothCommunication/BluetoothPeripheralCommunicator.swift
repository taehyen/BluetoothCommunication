//
//  BluetoothPeripheralCommunicator.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 8/12/24.
//

import Foundation
import CoreBluetooth

enum BluetoothPeripheralState: String {
    case powerOn
    case advertising
    case connected
    case sendingData
    case idle
    case disconnected
}

enum PeripheralError: Error {
    
}

class Weak<T: AnyObject> {
    weak var value: T?
    init(_ value: T) {
        self.value = value
    }
}

protocol BluetoothPeripheralCommunicatorInputs {
    func send(data: BluetoothData)
}

protocol BluetoothPeripheralCommunicatorDelegate {
    func didReceive(data: BluetoothData)
    func didConnected(_ connected: Bool)
    func didUpdate(state: BluetoothPeripheralState)
    func didReceive(error: PeripheralError)
    
    func didReceive(serviceInfo: String)
    func didReceive(characteristicInfo: String)
    func didReceive(descriptorInfo: String)
}

class BluetoothPeripheralCommunicator: NSObject {
    var delegate: BluetoothPeripheralCommunicatorDelegate?
    
    private var peripheralManager: CBPeripheralManager!
    private var allServices: [Weak<CustomService>] = []
    private var dataToReceive = Data()
    
    var inputs: BluetoothPeripheralCommunicatorInputs { self }
}

extension BluetoothPeripheralCommunicator: BluetoothPeripheralCommunicatorInputs {
    func send(data: BluetoothData) {
        log.verbose("send(data: \(data))")
        
        if case .binary(let packet) = data {
            if let service = self.allServices.filter({ $0.value is SpotService }).first {
                service.value?.packetToSend = packet
                service.value?.send(packet: packet)
            }
        }
    }
    
}

extension BluetoothPeripheralCommunicator {
    func initPeripheralManager() {
        //주변 장치 관리자를 인스턴스화할 때 Bluetooth의 전원이 꺼진 상태인 경우 시스템에서 경고해야 하는지 여부를 지정하는 부울 값입니다.
        //CBPeripheralManagerOptionShowPowerAlertKey
        
        //주변 장치 관리자를 인스턴스화하는 데 사용되는 UID(고유 식별자)입니다.
        //CBPeripheralManagerOptionRestoreIdentifierKey
        
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
    }
    
    func setupPeripheral() {
        // Create a service from the characteristic.
        let spotService = SpotService(type: TransferService.serviceUUID, primary: true)
        spotService.peripheralManager = peripheralManager
        spotService.delegate = self
        
        
//        let receiverService = ReceiverService(type: TransferService.serviceUUID, primary: true)
//        receiverService.peripheralManager = peripheralManager
//        receiverService.delegate = self
        
        // And add it to the peripheral manager.
        peripheralManager.add(spotService)
        allServices.append(Weak<CustomService>(spotService))
        
//        peripheralManager.add(receiverService)
//        allServices.append(Weak<CustomService>(receiverService))
    }
    
    func finalPeripheralManager() {
        log.verbose("all service : \(allServices)")
        
        allServices.removeAll(keepingCapacity: false)
        peripheralManager.removeAllServices()
        
        delegate?.didUpdate(state: .disconnected)
    }
    
    func startAdvertising() {
        log.verbose("startAdvertising")
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TransferService.serviceUUID],
                                               CBAdvertisementDataLocalNameKey: TransferService.peripheralName])
        
        delegate?.didReceive(serviceInfo: TransferService.serviceUUID.uuidString)
        delegate?.didReceive(characteristicInfo: TransferService.characteristics.map { $0.uuidString }.joined(separator: ","))
        delegate?.didReceive(descriptorInfo: TransferService.descriptorUUID.uuidString)
        
        delegate?.didUpdate(state: .advertising)
    }
    
    func stopAdvertising() {
        log.verbose("stopAdvertising")
        // 우리가 표시되지 않는 동안 광고를 계속하지 마십시오.
        peripheralManager.stopAdvertising()
        
        delegate?.didUpdate(state: .idle)
    }
}

extension BluetoothPeripheralCommunicator: CustomServiceDelegate {
    func didCompleted(service: CustomService) {
        log.verbose("\(service) completed")
    }
}

extension BluetoothPeripheralCommunicator: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        //        advertisingSwitch.isEnabled = peripheral.state == .poweredOn
        
        switch peripheral.state {
            case .poweredOn:
                log.verbose("CBManager is powered on")
                delegate?.didUpdate(state: .powerOn)
                setupPeripheral()
            case .poweredOff:
                log.verbose("CBManager is not powered on")
            case .resetting:
                log.verbose("CBManager is resetting")
            case .unauthorized:
                var authorization: CBManagerAuthorization!
                
                if #available(iOS 13.0, *) {
                    authorization = CBPeripheralManager.authorization
                } else {
                    authorization = peripheral.authorization
                }
                
                switch authorization {
                    case .denied:
                        log.verbose("You are not authorized to use Bluetooth")
                    case .restricted:
                        log.verbose("Bluetooth is restricted")
                    default:
                        log.verbose("Unexpected authorization")
                }
            case .unknown:
                log.verbose("CBManager state is unknown")
            case .unsupported:
                log.verbose("Bluetooth is not supported on this device")
            @unknown default:
                log.verbose("A previously unknown peripheral manager state occurred")
        }
    }
    
    /*
     *  누군가가 특성을 구독하는 것을 포착한 다음 데이터 전송을 시작.
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        log.verbose("Central subscribed to characteristic")
        
        peripheralManager.setDesiredConnectionLatency(.low, for: central)
        
        allServices.removeAll(where: { $0.value == nil })
        
        // Start sending if it has some data to send.
        allServices.forEach {
            guard let service = $0.value else { return }
            // save central
            service.connectedCentral = central
            
            if service.type == .write {
                if let packet = service.packetToSend {
                    service.send(packet: packet)
                }
            }
        }
    }
    
    /*
     *  central에서 구독을 취소할 때 인식.
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        log.verbose("Central unsubscribed from characteristic")
        
        allServices.forEach {
            guard let value = $0.value else { return }
            // save central
            value.connectedCentral = nil
        }
    }
    
    /*
     *  이 콜백은 PeripheralManager가 다음 데이터 청크를 보낼 준비가 되었을 때 발생합니다.
     *  이는 패킷이 전송된 순서대로 도착하도록 보장하기 위한 것입니다.
     */
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Start sending again
        allServices.forEach { $0.value?.sendData() }
    }
    
    /*
     * 이 콜백은 PeripheralManager가 특성에 대한 쓰기를 수신했을 때 발생합니다.
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        
        for aRequest in requests {
            guard let requestValue = aRequest.value else {
                continue
            }
            
            allServices.forEach { service in
                if service.value?.rxCharacteristic?.uuid == aRequest.characteristic.uuid {
                    let packet = SpotPacket(bytes: [UInt8](requestValue)) //TODO: 데이터가 제대로 들어오는지 확인해야 함.
                    delegate?.didReceive(data: .binary(packet))
                    dataToReceive.removeAll(keepingCapacity: false)
                }
            }
            
//            if let service = allServices.filter({ $0.value?.transferCharacteristic?.uuid == aRequest.characteristic.uuid }).first {
//                if service.value?.type == .write {
//                    let packet = SpotPacket(bytes: [UInt8](requestValue)) //TODO: 데이터가 제대로 들어오는지 확인해야 함.
//                    delegate?.didReceive(data: .binary(packet))
//                    dataToReceive.removeAll(keepingCapacity: false)
//                }
//            }
        }
    }
}


protocol CustomServiceDelegate {
    func didCompleted(service: CustomService)
}

class CustomService: CBMutableService {
    var delegate: CustomServiceDelegate?
    
    var rxCharacteristic: CBMutableCharacteristic?
    var txCharacteristic: CBMutableCharacteristic?
    
    weak var peripheralManager: CBPeripheralManager?
    weak var connectedCentral: CBCentral?
    
    var type: ServiceType = .read
    private var sendingEOM = false
    
    var packetToSend: SpotPacket?
    var dataToSend = Data()
    var sendDataIndex: Int = 0
    
    override init(type UUID: CBUUID, primary isPrimary: Bool) {
        super.init(type: UUID, primary: isPrimary)
        
        setUp()
    }
    
    func setUp() {
        //자식 클래스에서 사용
    }
    
    private func sendEOM() {
        guard let peripheralManager = peripheralManager else {
            return
        }
        
        guard let transferCharacteristic = txCharacteristic else {
            return
        }
        
        //Send it
        let eomSent = peripheralManager.updateValue("EOM".data(using: .utf8)!,
                                                    for: transferCharacteristic, onSubscribedCentrals: nil)
        
        if eomSent {
            // It sent; we're all done
            sendingEOM = false
            log.verbose("Sent: EOM")
            
            delegate?.didCompleted(service: self)
            
            sendDataIndex = 0
            dataToSend.removeAll(keepingCapacity: false)
        } else {
            log.error("Fail to send EOM")
        }
    }
    
    func send(packet: SpotPacket) {
        guard let peripheralManager = peripheralManager else {
            return
        }
        
        guard let transferCharacteristic = txCharacteristic else {
            return
        }
        
        //        let data = Data(bytes: packet.body, count: Int(packet.bodyLength))
        //보낼때
        let didSend = peripheralManager.updateValue(packet.data, for: transferCharacteristic, onSubscribedCentrals: nil)
        
        log.info("didSend: \(didSend)")
        
        delegate?.didCompleted(service: self)
    }
    
    func sendData() {
        guard let peripheralManager = peripheralManager else {
            return
        }
        
        guard let transferCharacteristic = txCharacteristic else {
            return
        }
        
        // First up, check if we're meant to be sending an EOM
        if sendingEOM {
            // send it
            sendEOM()
            // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
            return
        }
        
        // We're not sending an EOM, so we're sending data
        // Is there any left to send?
        if sendDataIndex >= dataToSend.count {
            // No data left.  Do nothing
            return
        }
        
        // There's data left, so send until the callback fails, or we're done.
        var didSend = true
        while didSend {
            
            // Work out how big it should be
            var amountToSend = dataToSend.count - sendDataIndex
            if let mtu = connectedCentral?.maximumUpdateValueLength {
                amountToSend = min(amountToSend, mtu)
            }
            
            // Copy out the data we want
            let chunk = dataToSend.subdata(in: sendDataIndex..<(sendDataIndex + amountToSend))
            
            // Send it
            didSend = peripheralManager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil)
            
            // If it didn't work, drop out and wait for the callback
            if !didSend {
                return
            }
            
            //            let stringFromData = String(data: chunk, encoding: .utf8)
            //            log.verbose("Sent \(chunk.count) bytes: \(String(describing: stringFromData))")
            
            // It did send, so update our index
            sendDataIndex += amountToSend
            
            // = \((sendDataIndex * 100) / dataToSend.count)
            log.verbose("Sending: \(sendDataIndex) / \(dataToSend.count)")
            
            // Was it the last one?
            if sendDataIndex >= dataToSend.count {
                // It was - send an EOM
                
                // Set this so if the send fails, we'll send it next time
                sendingEOM = true
                
                sendEOM()
            }
        }
    }
}

class SpotService: CustomService {
    override func setUp() {
        type = .readwrite
        
        let rxCharacteristic = CBMutableCharacteristic(type: TransferService.serverRxCharacteristicUUID,
                                                       properties: [.read, .notifyEncryptionRequired, .indicateEncryptionRequired],
                                                       value: nil,
                                                       permissions: [.readable, .readEncryptionRequired])
        
        let txCharacteristic = CBMutableCharacteristic(type: TransferService.serverTxCharacteristicUUID,
                                                       properties: [.write, .writeWithoutResponse],
                                                       value: nil,
                                                       permissions: [.writeable, .writeEncryptionRequired])
        
        //rx, tx 자리를 바꾸는 이유는 rx가 sender app -> receive app 기준으로 고정되어있기 때문이다.
        self.rxCharacteristic = txCharacteristic
        self.txCharacteristic = rxCharacteristic
        
        characteristics = [rxCharacteristic, txCharacteristic]
    }
}
