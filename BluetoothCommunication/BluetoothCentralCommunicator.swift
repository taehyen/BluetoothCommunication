//
//  CentralViewModel.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 3/15/24.
//

import Foundation
import CoreBluetooth

enum BluetoothCentralState: String {
    case recovery
    case reconnecting
    case scanning
    case didDiscoverService
    case didDiscoverCharacteristic
    case failToConnected
    case connected
    case subscribing
    case waitingReceiveData
    case receivingEmptyData
    case receivingData
    case receivingDescriptor
    case receiveCompleted
    case sendingData
    case disconnected
}

enum CentralError: Error {
    case unknownService
    case unknownCharacteristic
    case unknownDescriptor
    case notReadyPeripheral
    case emptyService
    case emptyCharacteristic
    case emptyDescriptor
    case unknown(String)
}

protocol BluetoothCentralCommunicateType {
    var inputs: BluetoothCentralCommunicateInputs { get }
}

protocol BluetoothCentralCommunicateInputs {
    func initCentral()
    func finalCentral()
    func send(data: BluetoothData)
}

protocol BluetoothCentralCommunicatorDelegate {
    func didReceive(data: BluetoothData)
    func didConnected(_ connected: Bool)
    func didUpdate(state: BluetoothCentralState)
    func didReceive(error: CentralError)
    
    func didReceive(serviceInfo: String)
    func didReceive(characteristicInfo: String)
    func didReceive(descriptorInfo: String)
}

extension BluetoothCentralCommunicatorDelegate {
    func didReceive(serviceInfo: String) {}
    func didReceive(characteristicInfo: String) {}
    func didReceive(descriptorInfo: String) {}
}

let writeType: CBCharacteristicWriteType = .withoutResponse

class BluetoothCentralCommunicator: NSObject, BluetoothCentralCommunicateType {
    var delegate: BluetoothCentralCommunicatorDelegate?
    
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    
    /// CBPeripherialDelegate 내에서 주로 사용되어지며, peripheral로 전송하려는 특성을 나타낸다.
    private var serverTxCharacteristic: CBCharacteristic?
    private var serverRxCharacteristic: CBCharacteristic?
    
    private var dataToSend: [BluetoothData] = []
    
    override init() {
        super.init()
    }
    
    deinit {
        log.verbose("\(String(describing: self)) disposed")
    }
    
    var inputs: BluetoothCentralCommunicateInputs { self }
}

// MARK: - Inputs
extension BluetoothCentralCommunicator: BluetoothCentralCommunicateInputs {
    func initCentral() {
        initCentralManager()
    }
    
    func finalCentral() {
        finalCentralManager()
    }
    
    func send(data: BluetoothData) {
        guard let peripheral = discoveredPeripheral else {
            return
        }
        
        guard peripheral.state == .connected else {
            return
        }
        
        log.verbose("peripheral.state = \(peripheral.state)")
        
        //처음에 보낼 때이므로, 비우고 보낸다.
        dataToSend.removeAll(keepingCapacity: false)
        
        dataToSend.append(data)
        
        writeData()
    }
}

// MARK: - Private
private extension BluetoothCentralCommunicator {
    func initCentralManager() {
        //queue는 main thread에서 처리해야하므로, 기본값인 nil로 한다.
        centralManager = CBCentralManager(delegate: self, queue: nil,
                                          options: [CBCentralManagerOptionShowPowerAlertKey: true,
                                                 CBCentralManagerOptionRestoreIdentifierKey: true])
        
        /*
         CBCentralManagerOptionShowPowerAlertKey
         이 옵션은 블루투스가 꺼져 있을 때 사용자에게 알림을 표시할지 여부를 결정합니다. true로 설정하면 블루투스가 꺼져 있을 때 사용자에게 경고 창이 표시되어 블루투스를 활성화하도록 요청합니다. 이는 사용자 경험을 개선할 수 있지만, 애플리케이션의 사용성에 따라 적절하게 사용해야 합니다.
         
         CBCentralManagerOptionRestoreIdentifierKey
         이 옵션은 애플리케이션의 중앙 관리자에게 고유 식별자를 제공하여, 애플리케이션이 백그라운드에서 종료된 후에도 시스템에 의해 다시 시작될 수 있게 합니다. 이 식별자를 사용하면, 애플리케이션을 다시 시작할 때 이전에 연결된 페리페럴들을 복원하고, 미처리된 작업을 계속할 수 있습니다. 이는 특히 백그라운드에서 장기 실행 작업을 처리하는 애플리케이션에 유용합니다.
         */
        
        //        CBCentralManager.supports(.extendedScanAndConnect)
        
        /*
         지원 여부를 결정하는 데 사용할 수 있는 목록이 없습니다. 그렇기 때문에 supportFeatures() 호출 뒤에 제어되므로 앱이 실행되는 기기에서 동적으로 결정할 수 있습니다. 테스트하고 싶다면 지원되는 iPhone 13 Pro를 사용할 수 있습니다. 그러나 실제로 이 기능을 사용하려면 광고 주변 장치도 확장된 광고 및 연결을 지원해야 합니다.
         
         확장된 스캔 및 연결은 링크 레이어 기능이며 앱에 대해 다른 기능을 활성화하지 않습니다. 이는 iOS 장치가 주변 장치로부터 확장된 광고 패킷을 검색하고 인식한다는 점을 나타내는 정보일 뿐입니다. 기능에는 더 긴 광고 패킷(254바이트 대 31바이트), 더 긴 데이터를 위한 체인 광고 패킷, 동기화된 광고가 포함됩니다. 모든 장치/iOS 조합에서 이러한 기능 중 일부가 활성화되는 것은 아닙니다. 지금 기능에 대해 YES 또는 NO를 반환하더라도 동일한 장치가 나중에 동일한 결과를 반환한다는 보장은 없습니다.
         
         알아차릴 수 있는 유일한 동작 차이점은 추가 데이터에 대한 SCAN_RSP 패킷이 더 이상 필요하지 않은 것으로 간주되는 경우 광고에 대한 보조 didDiscover() 콜백이 없다는 것입니다.
         */
    }
    
    func finalCentralManager() {
        centralManager.stopScan()
        log.verbose("Scanning stopped")
        
        delegate?.didUpdate(state: .disconnected)
        delegate?.didConnected(false)
        
        dataToSend.removeAll(keepingCapacity: false)
    }
    
    /*
     먼저 상대방과 이미 연결되어 있는지 확인하겠습니다.
     그렇지 않은 경우에는 주변 장치를 검색하십시오. 특히 이 회사의 서비스의 128비트 CBUUID에 대한 것입니다.
     */
    func retrievePeripheral() {
        let connectedPeripherals = (centralManager.retrieveConnectedPeripherals(withServices: [TransferService.serviceUUID]))
        
        //TODO: 여러개가 존재할 때, 정확히 어떤 Peripheral에 접속해야 하는지 조건식이 추가되어야 한다.
        
        log.verbose("Found connected Peripherals with transfer service: \(connectedPeripherals)")
        
        if let connectedPeripheral = connectedPeripherals.last {
            delegate?.didUpdate(state: .connected)
            
            log.verbose("Connecting to peripheral \(connectedPeripheral)")
            
            discoveredPeripheral = connectedPeripheral
            centralManager.connect(connectedPeripheral, options: nil)
            
        } else {
            delegate?.didUpdate(state: .scanning)
            
            centralManager.delegate = self
            
            log.verbose("Scan for Peripherals")
            
            // We were not connected to our counterpart, so start scanning
            centralManager.scanForPeripherals(withServices: [TransferService.serviceUUID],
                                              options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }
    
    /*
     문제가 발생하거나 연결이 완료되면 이 호출을 사용.
     구독이 있는 경우 구독이 취소되고, 구독이 없으면 연결이 바로 끊어집니다.
     didUpdateNotificationStateForCharacteristic은 구독이 관련된 경우 연결을 취소합니다.
     */
    func cleanup(cancelPeripheral: Bool = true) {
        guard let peripheral = discoveredPeripheral else {
            return
        }
        
        peripheral.cleanUp()
        
        if cancelPeripheral == true {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        
        delegate?.didUpdate(state: .disconnected)
    }
    
    // 주변 장치에 일부 테스트 데이터 쓰기
    func writeData() {
        guard let peripheral = discoveredPeripheral else {
            log.error("peripheral is not ready.")
            delegate?.didReceive(error: .notReadyPeripheral)
            return
        }
        
        guard let data = dataToSend.last else {
            return
        }
        
        delegate?.didUpdate(state:.sendingData)
        
        if case .binary(let packet) = data {
            if let characteristic = serverTxCharacteristic {
                peripheral.write(packet: packet, characteristic: characteristic)
            }
        } else {
            log.error("Characteristic is not ready.")
            delegate?.didReceive(error: .emptyCharacteristic)
        }
        
        dataToSend.removeAll(keepingCapacity: false)
    }
}

extension BluetoothCentralCommunicator: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
            case .poweredOn:
                log.verbose("CBManager is powered on")
                retrievePeripheral()
            case .poweredOff:
                log.verbose("CBManager is not powered on")
            case .resetting:
                log.verbose("CBManager is resetting")
            case .unauthorized:
                if #available(iOS 13.1, *) {
                    switch CBManager.authorization {
                        case .denied:
                            log.verbose("You are not authorized to use Bluetooth")
                        case .restricted:
                            log.verbose("Bluetooth is restricted")
                        default:
                            log.verbose("Unexpected authorization")
                    }
                } else {
                    switch central.authorization {
                        case .denied:
                            log.verbose("You are not authorized to use Bluetooth")
                        case .restricted:
                            log.verbose("Bluetooth is restricted")
                        default:
                            log.verbose("Unexpected authorization")
                    }
                }
                return
            case .unknown:
                log.verbose("CBManager state is unknown")
            case .unsupported:
                log.verbose("Bluetooth is not supported on this device")
            @unknown default:
                log.verbose("A previously unknown central manager state occurred")
                return
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        //        statusSubject.onNext(.recovery)
        delegate?.didUpdate(state: .recovery)
        
        // 이전에 연결된 주변 장치 복원
        if let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            // 처리 코드 작성
            log.verbose("restoredPeripherals: \(restoredPeripherals)")
        }
        
        // 이전에 스캔 중이던 주변 장치 복원
        if let restoredScanServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
            // 처리 코드 작성
            log.verbose("restoredScanServices: \(restoredScanServices)")
        }
        
        // 기타 상태 복원 처리...
        log.verbose("etc restore...")
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        //        guard RSSI.intValue >= -50 else {
        //            log.warning("Discovered peripheral not in expected range, at \(RSSI)")
        //            return
        //        }
        
        log.verbose("Discovered \(peripheral.name ?? "unknown name") at \(RSSI)")
        if discoveredPeripheral != peripheral {
            discoveredPeripheral = peripheral
        }
        
        if peripheral.state == .disconnected {
            delegate?.didUpdate(state: .reconnecting)
            log.verbose("Connecting to peripheral \(peripheral)")
            centralManager.connect(peripheral, options: nil)
        } else {
            log.verbose("peripheral state = \(peripheral.state)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        delegate?.didUpdate(state: .failToConnected)
        
        log.warning("Failed to connect to \(peripheral). \(String(describing: error))")
        
        cleanup()
    }
    
    //주변기기와 연결했으니 이제 '전송' 특성을 찾기 위해 서비스와 특성을 찾아야 합니다.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        delegate?.didUpdate(state: .connected)
        
        log.verbose("Peripheral Connected")
        
        centralManager.stopScan()
        log.verbose("Scanning stoppped")
        
        //이미 가지고 있을 수 있는 데이터 지우기
        dataToSend.removeAll(keepingCapacity: false)
        
        peripheral.delegate = self //CBPeripheralDelegate
        peripheral.discoverServices([TransferService.serviceUUID])
    }
    
    //연결이 끊어지면 주변 장치의 로컬 복사본을 정리해야 합니다.
    //5+
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        delegate?.didUpdate(state: .disconnected)
        log.verbose("didDisconnectPeripheral: \(peripheral)")
        
        //연결이 끊어졌으니 다시 스캔을 시작하세요
        retrievePeripheral()
    }
}

extension BluetoothCentralCommunicator: CBPeripheralDelegate {
    //서비스가 무효화되었을 때 이를 알려주는 주변 장치입니다.
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        log.verbose("didModifyServices: \(peripheral)")
        
        var invalidated: Bool = false
        for service in invalidatedServices where service.uuid == TransferService.serviceUUID {
            log.verbose("Transfer service is invalidated - rediscover services")
            peripheral.discoverServices([TransferService.serviceUUID])
            invalidated = true
        }
        
        if invalidated == true {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    //Transfer Service가 발견되었습니다.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        log.verbose("didDiscoverServices: \(peripheral)")
        
        if let error = error {
            log.error("Error discovering services: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        //둘 이상이 있을 경우를 대비하여 새로 채워진 Peripheral.services 배열을 반복합니다.
        guard let peripheralServices = peripheral.services else {
            delegate?.didReceive(error: .emptyService)
            return
        }
        
        delegate?.didUpdate(state: .didDiscoverService)
        
        log.verbose("CALL peripheral.discoverCharacteristics")
        
        for service in peripheralServices {
            peripheral.discoverCharacteristics([TransferService.serverRxCharacteristicUUID,
                                                TransferService.serverTxCharacteristicUUID], for: service)
            
            log.verbose("service = \(service)")
            
            delegate?.didReceive(serviceInfo: "\(service.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log.error("Error discovering characteristics: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        delegate?.didUpdate(state: .didDiscoverCharacteristic)
        
        if let characteristics = service.characteristics {
            log.verbose("service.characteristics = \(characteristics)")
        } else {
            log.verbose("service.characteristics is nil")
        }
        
        //다시 한 번, 만약을 대비해 배열을 반복하고 그것이 올바른지 확인합니다.
        guard let serviceCharacteristics = service.characteristics, serviceCharacteristics.count > 0 else {
            delegate?.didReceive(error: .emptyCharacteristic)
            return
        }
        
        //찾는 특성이 나오면 이 루프 안에서 구독하는 처리를 한다.
        for characteristic in serviceCharacteristics {
            if characteristic.uuid == TransferService.serverRxCharacteristicUUID {
                serverRxCharacteristic = characteristic
                
                delegate?.didReceive(characteristicInfo: "\(characteristic.uuid)")
                
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    serverRxCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.discoverDescriptors(for: characteristic)
                } else {
                    log.error("serverRxCharacteristic does not support notify")
                }
                
                delegate?.didUpdate(state: .subscribing)
                
                delegate?.didConnected(true)
                
            } else if characteristic.uuid == TransferService.serverTxCharacteristicUUID {
                delegate?.didReceive(characteristicInfo: "\(characteristic.uuid)")
                
                if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                    serverTxCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.discoverDescriptors(for: characteristic)
                } else {
                    log.error("serverTxCharacteristic does not support write")
                }
                
                delegate?.didUpdate(state: .subscribing)
                delegate?.didConnected(true)
            }
        }
        
        
        
        //이 작업이 완료되면 데이터가 들어올 때까지 기다리면 됩니다.
        delegate?.didUpdate(state: .waitingReceiveData)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let descriptors = characteristic.descriptors else { return }
        
        for descriptor in descriptors {
            // 여기서 descriptor 객체를 사용할 수 있습니다.
            // 예: descriptor 읽기
            peripheral.readValue(for: descriptor)
            
            log.verbose("descriptor = \(descriptor)")
            delegate?.didUpdate(state: .receivingDescriptor)
        }
    }
    
    //완료
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log.error("Error discovering characteristics: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        guard let characteristicData = characteristic.value else {
            delegate?.didUpdate(state: .receivingEmptyData)
            return
        }
        
        log.verbose("received data length : \(characteristicData.count)")
        
        delegate?.didUpdate(state: .receiveCompleted)
        
        if characteristic == serverRxCharacteristic {
            let packet = SpotPacket(bytes: [UInt8](characteristicData))
            self.delegate?.didReceive(data: .binary(packet))
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        delegate?.didUpdate(state: .receivingDescriptor)
        
        delegate?.didReceive(descriptorInfo: "\(descriptor.uuid)")
        
        log.verbose("didUpdateValueFor descriptor: \(descriptor)")
    }
    
    //주변 장치가 지정된 특성의 값에 대한 알림을 시작하거나 중단하라는 요청을 받았다고 대리인에게 알려줍니다.
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log.error("Error changing notification state: \(error.localizedDescription)")
            return
        }
        
        // 전송 특성이 아닐 경우 종료
        guard TransferService.characteristics.contains(characteristic.uuid) else {
            //해당되는 특성이 아니므로, clean할 필요는 없다.
            delegate?.didReceive(error: .unknownCharacteristic)
            return
        }
        
        //이거 peripheral 쪽에서 알려주는건데, 어떻게 날라오는거지?
        if characteristic.isNotifying {
            // 알림이 시작되었습니다
            log.verbose("Notification began on \(characteristic)")
        } else {
            // 알림이 중지되었으므로 주변기기와의 연결을 끊습니다.
            log.verbose("Notification stopped on \(characteristic). Disconnecting")
            cleanup(cancelPeripheral: false)
        }
    }
    
    //응답 없이 쓰기를 사용할 때 주변기기가 더 많은 데이터를 받아들일 준비가 되었을 때 호출됩니다.
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        log.verbose("Peripheral is ready, send data")
        
        writeData()
    }
}

var writeInProgress = false

extension CBPeripheral {
    
    func cleanUp() {
        guard case .connected = state else { return }
        
        for service in (services ?? [] as [CBService]) {
            for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {
                if TransferService.characteristics.contains(characteristic.uuid) && characteristic.isNotifying {
                    // 알림이 오니까 구독취소
                    setNotifyValue(false, for: characteristic)
                }
            }
        }
    }
    
    func write(packet: SpotPacket, characteristic: CBCharacteristic) {
        let maxAttempts = 100
        var attempts = 0
        
        while !writeInProgress && attempts < maxAttempts {
            let mtu = self.maximumWriteValueLength(for: writeType)
            let data = packet.data
            
            let bytesToCopy: size_t = min(mtu, data.count)
            var rawPacket = Array<UInt8>(repeating: 0, count: bytesToCopy)
            data.copyBytes(to: &rawPacket, count: bytesToCopy)
            let packetData = Data(rawPacket)
            
            self.writeValue(packetData, for: characteristic, type: writeType)
            log.verbose("Writing \(bytesToCopy) bytes.")
            
            writeInProgress = true // 데이터를 쓰기 시작했으므로 플래그 설정
            attempts += 1
        }
        
        if attempts >= maxAttempts {
            log.error("Failed to write all data: maximum attempts reached.")
        }
        
        writeInProgress = false
    }
    
    var canSendWriteWithResponse: Bool {
        return !writeInProgress
    }
    
    //    func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int {
    //        // 주어진 쓰기 타입에 따라 최대 쓰기 크기를 반환합니다.
    //        // withResponse의 경우, 일반적으로 MTU 크기를 반환합니다.
    //        return 20 // 예시로 20 바이트 반환 (실제 구현에서는 주변 장치의 MTU 크기를 반환)
    //    }
}
