//
//  CentralViewModel.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 3/15/24.
//

import Foundation
import CoreBluetooth
import RxSwift
import RxCocoa

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

class CentralViewModel: NSObject {
    private let disposeBag = DisposeBag()
    
    private var connectedSubject: PublishSubject<BluetoothCentralState> = .init()
    private var receiveDataSubject: PublishSubject<Data> = .init()
    private var errorSubject: PublishSubject<CentralError> = .init()
    
    private var serviceInfoSubject: PublishSubject<String> = .init()
    private var characteristicInfoSubject: PublishSubject<String> = .init()
    private var descriptorInfoSubject: PublishSubject<String> = .init()
    
    public var connected: Observable<BluetoothCentralState> {
        connectedSubject.asObservable()
    }
    public var receivedData: Observable<Data> {
        receiveDataSubject.asObservable()
    }
    public var error: Observable<CentralError> {
        errorSubject.asObservable()
    }
    public var serviceInfo: Observable<String> {
        serviceInfoSubject.asObservable()
    }
    public var characteristicInfo: Observable<String> {
        characteristicInfoSubject.asObservable()
    }
    public var descriptorInfo: Observable<String> {
        descriptorInfoSubject.asObservable()
    }
    
    func ready() {
        serviceInfoSubject.onNext("")
        characteristicInfoSubject.onNext("")
        descriptorInfoSubject.onNext("")
    }
    
    func send(data: BluetoothData) {
        guard let peripheral = discoveredPeripheral else {
            return
        }
        
        guard peripheral.state == .connected else {
            return
        }
        
        log.info("peripheral.state = \(peripheral.state)")
        
        //처음에 보낼 때이므로, 비우고 보낸다.
        dataToSend.removeAll(keepingCapacity: false)
        
        dataToSend.append(data)
        
        writeData()
    }
    
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    /// CBPeripherialDelegate 내에서 주로 사용되어지며, peripheral로 전송하려는 특성을 나타낸다.
    private var transferTextCharacteristic: CBCharacteristic?
    private var transferImageCharacteristic: CBCharacteristic?
    
    private var dataToSend: [BluetoothData] = []
    private var dataToReceive = Data() // 수신하는 데이터가 나누어져서 올 수 있기 때문에 EOM(end of message)을 받기 전에 이곳에 쌓아둔다.
    
    override init() {
        super.init()
        initCentralManager()
    }
    
    deinit {
        finalCentralManager()
    }
}

extension CentralViewModel {
    private func initCentralManager() {
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
    
    private func finalCentralManager() {
        centralManager.stopScan()
        log.info("Scanning stopped")
        
        connectedSubject.onNext(.disconnected)
        
        dataToSend.removeAll(keepingCapacity: false)
        dataToReceive.removeAll(keepingCapacity: false)
    }
    
    /*
     먼저 상대방과 이미 연결되어 있는지 확인하겠습니다.
     그렇지 않은 경우에는 주변 장치를 검색하십시오. 특히 이 회사의 서비스의 128비트 CBUUID에 대한 것입니다.
     */
    private func retrievePeripheral() {
        let connectedPeripherals = (centralManager.retrieveConnectedPeripherals(withServices: [TransferService.serviceUUID]))
        
        //TODO: 여러개가 존재할 때, 정확히 어떤 Peripheral에 접속해야 하는지 조건식이 추가되어야 한다.
        
        log.verbose("Found connected Peripherals with transfer service: \(connectedPeripherals)")
        
        if let connectedPeripheral = connectedPeripherals.last {
            connectedSubject.onNext(.connected)
            
            log.verbose("Connecting to peripheral \(connectedPeripheral)")

            discoveredPeripheral = connectedPeripheral
            centralManager.connect(connectedPeripheral, options: nil)
        } else {
            connectedSubject.onNext(.scanning)
            
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
    private func cleanup(cancelPeripheral: Bool = true) {
        guard let peripheral = discoveredPeripheral else {
            return
        }
        
        peripheral.cleanUp()
        
        if cancelPeripheral == true {
            centralManager.cancelPeripheralConnection(peripheral)
            ready()
        }

        connectedSubject.onNext(.disconnected)
    }
    
    // 주변 장치에 일부 테스트 데이터 쓰기
    private func writeData() {
        guard let peripheral = discoveredPeripheral else {
            log.error("peripheral is not ready.")
            errorSubject.onNext(.notReadyPeripheral)
            return
        }
        
        guard let data = dataToSend.last else {
            return
        }
        
        connectedSubject.onNext(.sendingData)
        
        if case .image(let data) = data {
            if let transferCharacteristic = transferImageCharacteristic {
                // 완료된 반복 횟수와 주변 장치가 더 많은 데이터를 수용할 수 있는지 확인하십시오.
                peripheral.write(data: data, characteristic: transferCharacteristic)
            }
        } else if case .text(let data) = data {
            if let transferCharacteristic = transferTextCharacteristic {
                // 완료된 반복 횟수와 주변 장치가 더 많은 데이터를 수용할 수 있는지 확인하십시오.
                peripheral.write(data: data, characteristic: transferCharacteristic)
            }
        } else if case .binary(_) = data {
//            if let transferCharacteristic = transferImageCharacteristic {
//                // 완료된 반복 횟수와 주변 장치가 더 많은 데이터를 수용할 수 있는지 확인하십시오.
//                peripheral.write(data: data, characteristic: transferCharacteristic)
//            }
        } else {
            log.error("Characteristic is not ready.")
            errorSubject.onNext(.emptyCharacteristic)
        }

        dataToSend.removeAll(keepingCapacity: false)
    }
}

extension CentralViewModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
            case .poweredOn:
                // ... so start working with the peripheral
                log.verbose("CBManager is powered on")
                retrievePeripheral()
            case .poweredOff:
                log.verbose("CBManager is not powered on")
                // In a real app, you'd deal with all the states accordingly
                return
            case .resetting:
                log.verbose("CBManager is resetting")
                // In a real app, you'd deal with all the states accordingly
                return
            case .unauthorized:
                // In a real app, you'd deal with all the states accordingly
                if #available(iOS 13.0, *) {
                    switch central.authorization {
                        case .denied:
                            log.verbose("You are not authorized to use Bluetooth")
                        case .restricted:
                            log.verbose("Bluetooth is restricted")
                        default:
                            log.verbose("Unexpected authorization")
                    }
                } else {
                    // Fallback on earlier versions
                }
                return
            case .unknown:
                log.verbose("CBManager state is unknown")
                // In a real app, you'd deal with all the states accordingly
                return
            case .unsupported:
                log.verbose("Bluetooth is not supported on this device")
                // In a real app, you'd deal with all the states accordingly
                return
            @unknown default:
                log.verbose("A previously unknown central manager state occurred")
                // In a real app, you'd deal with yet unknown cases that might occur in the future
                return
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        connectedSubject.onNext(.recovery)
        
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
        
        print("Discovered \(peripheral.name ?? "unknown name") at \(RSSI)")
        if discoveredPeripheral != peripheral {
            discoveredPeripheral = peripheral
        }
        
        if peripheral.state == .disconnected {
            connectedSubject.onNext(.reconnecting)
            log.verbose("Connecting to peripheral \(peripheral)")
            centralManager.connect(peripheral, options: nil)
        } else {
            log.verbose("peripheral state = \(peripheral.state)")
        }
        
        //CBConnectPeripheralOptionNotifyOnConnectionKey            //6+
        //CBConnectPeripheralOptionNotifyOnDisconnectionKey         //5+
        //CBConnectPeripheralOptionNotifyOnNotificationKey          //6+
        //CBConnectPeripheralOptionEnableTransportBridgingKey       //13+
        //CBConnectPeripheralOptionRequiresANCS                     //13+
        //CBConnectPeripheralOptionStartDelayKey                    //6+
        //CBConnectPeripheralOptionEnableAutoReconnect              //17+
        
        //iOS 17 이하에서 자동으로 연결하는 것은 로직으로 해야 함.
        //DisconnectionKey을 사용해서 처리하는 방향으로 해야 함.
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedSubject.onNext(.failToConnected)
        
        log.warning("Failed to connect to \(peripheral). \(String(describing: error))")
        
        cleanup()
    }
    
    //주변기기와 연결했으니 이제 '전송' 특성을 찾기 위해 서비스와 특성을 찾아야 합니다.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedSubject.onNext(.connected)
        
        log.verbose("Peripheral Connected")
        
        centralManager.stopScan()
        log.verbose("Scanning stoppped")
        
//TODO: 끊어졌다가 다시 연결하는 경우에는, 지우면 안될지도 모른다.
        //이미 가지고 있을 수 있는 데이터 지우기
        dataToReceive.removeAll(keepingCapacity: false)
        dataToSend.removeAll(keepingCapacity: false)
        
        peripheral.delegate = self //CBPeripheralDelegate
        peripheral.discoverServices([TransferService.serviceUUID])
    }
    
    //연결이 끊어지면 주변 장치의 로컬 복사본을 정리해야 합니다.
    //5+
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedSubject.onNext(.disconnected)
        log.verbose("didDisconnectPeripheral: \(peripheral)")
        
        ready()
        
        //연결이 끊어졌으니 다시 스캔을 시작하세요
        retrievePeripheral()
    }
}

extension CentralViewModel: CBPeripheralDelegate {
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
            errorSubject.onNext(.emptyService)
            return
        }
        
        connectedSubject.onNext(.didDiscoverService)
        
        log.verbose("CALL peripheral.discoverCharacteristics")
        
        for service in peripheralServices {
            peripheral.discoverCharacteristics([TransferService.textCharacteristicUUID,
                                                TransferService.imageCharacteristicUUID], for: service)
            
            log.verbose("service = \(service)")
            serviceInfoSubject.onNext("\(service.uuid)")
            
            if let characteristics = service.characteristics {
                log.verbose("service.characteristics = \(characteristics)")
            } else {
                log.verbose("service.characteristics is nil")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log.error("Error discovering characteristics: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        connectedSubject.onNext(.didDiscoverCharacteristic)
        
        //다시 한 번, 만약을 대비해 배열을 반복하고 그것이 올바른지 확인합니다.
        guard let serviceCharacteristics = service.characteristics else {
            errorSubject.onNext(.emptyCharacteristic)
            return
        }

        //찾는 특성이 나오면 이 루프 안에서 구독하는 처리를 한다.
        for characteristic in serviceCharacteristics {
            
            if characteristic.uuid == TransferService.textCharacteristicUUID {
                transferTextCharacteristic = characteristic
                
                characteristicInfoSubject.onNext("\(characteristic.uuid)")

                peripheral.setNotifyValue(true, for: characteristic)

                peripheral.discoverDescriptors(for: characteristic)
                
                connectedSubject.onNext(.subscribing)
                
            } else if characteristic.uuid == TransferService.imageCharacteristicUUID {
                transferImageCharacteristic = characteristic
                
                characteristicInfoSubject.onNext("\(characteristic.uuid)")
                
                peripheral.setNotifyValue(true, for: characteristic)

                peripheral.discoverDescriptors(for: characteristic)
                
                connectedSubject.onNext(.subscribing)
            }
        }
        
        //이 작업이 완료되면 데이터가 들어올 때까지 기다리면 됩니다.
        connectedSubject.onNext(.waitingReceiveData)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let descriptors = characteristic.descriptors else { return }
        
        for descriptor in descriptors {
            // 여기서 descriptor 객체를 사용할 수 있습니다.
            // 예: descriptor 읽기
            peripheral.readValue(for: descriptor)
            
            log.verbose("descriptor = \(descriptor)")
            connectedSubject.onNext(.receivingDescriptor)
        }
    }
    
//완료.
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log.error("Error discovering characteristics: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        guard let characteristicData = characteristic.value else {
            connectedSubject.onNext(.receivingEmptyData)
            return
        }
        
        let stringFromData = String(data: characteristicData, encoding: .utf8)
        log.verbose("received data length : \(characteristicData.count)")
        log.verbose("bytes: \(String(describing: stringFromData))")
        
        //메시지 끝 토큰을 받게 되면
        if stringFromData == "EOM" {
            //이 메서드가 어느 스레드에서 다시 호출될지 모르기 때문에 UI 업데이트를 위해 텍스트 보기 업데이트를 기본 대기열로 전달합니다.
            //Rx로 처리하므로, observer쪽에서 메인쓰레드로 바꾸면 될 듯.
            receiveDataSubject.onNext(self.dataToReceive)
            
            dataToReceive.removeAll(keepingCapacity: false)
            
            connectedSubject.onNext(.receiveCompleted)
        } else {
            //그렇지 않으면 이전에 받은 데이터에 데이터를 추가하면 됩니다.
            dataToReceive.append(characteristicData)
            
            connectedSubject.onNext(.receivingData)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        connectedSubject.onNext(.receivingDescriptor)
        
        descriptorInfoSubject.onNext("\(descriptor.uuid)")
        
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
            errorSubject.onNext(.unknownCharacteristic)
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

//TODO: 자꾸 Casting 해야 해서, Decorator(Container) 형식으로 바꿔야 하는지 검토 필요.
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
    
    func write(data: Data, characteristic: CBCharacteristic) {
        // 완료된 반복 횟수와 주변 장치가 더 많은 데이터를 수용할 수 있는지 확인하십시오.
        while self.canSendWriteWithoutResponse {
            let mtu = self.maximumWriteValueLength (for: .withoutResponse)
            var rawPacket = [UInt8]()
            
            let bytesToCopy: size_t = min(mtu, data.count)
            data.copyBytes(to: &rawPacket, count: bytesToCopy)
            let packetData = Data(bytes: &rawPacket, count: bytesToCopy)
            
            self.writeValue(packetData, for: characteristic, type: .withoutResponse)
            
            log.verbose("Writing \(bytesToCopy) bytes.")
        }
        
        self.writeValue("EOM".data(using: .utf8)!, for: characteristic, type: .withoutResponse)
        
        log.verbose("Writing EOM")
    }
}
