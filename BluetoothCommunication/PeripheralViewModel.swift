//
//  PeripheralViewModel.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 3/29/24.
//  Copyright (c) 2024 ___ORGANIZATIONNAME___. All rights reserved.
//

import RxSwift
import RxCocoa
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

protocol PeripheralViewModelType {
    var inputs: PeripheralViewModelInputs { get }
    var outputs: PeripheralViewModelOutputs { get }
}

protocol PeripheralViewModelInputs {
    func initPeripheral()
    func finalPeripheral()
    func start()
    func stop()
    
    func send(data: BluetoothData)
    func spt001()
    func spt003()
    func spt006()
}

protocol PeripheralViewModelOutputs {
    var error: Observable<PeripheralError> { get }
    var status: Observable<BluetoothPeripheralState> { get }
    var receivedData: Driver<BluetoothData> { get }
}

class Weak<T: AnyObject> {
    weak var value: T?
    init(_ value: T) {
        self.value = value
    }
}

// MARK: - ViewModel
class PeripheralViewModel: NSObject, PeripheralViewModelType {
    var disposeBag = DisposeBag()
    
    private var peripheralManager: CBPeripheralManager!
    private var allServices: [Weak<CustomService>] = []
    private var dataToReceive = Data()

    private let errorSubject: PublishSubject<PeripheralError?> = .init()
    private var statusSubject: PublishSubject<BluetoothPeripheralState> = .init()
    private var receiveDataSubject: PublishSubject<BluetoothData> = .init()
    
    let spotProxyServer = SpotProxyServer.shared

    override init() {
        super.init()
    }

    deinit {
        log.verbose("\(String(describing: self)) disposed")
    }

    var inputs: PeripheralViewModelInputs { self }
    var outputs: PeripheralViewModelOutputs { self }
}

// MARK: - Inputs
extension PeripheralViewModel: PeripheralViewModelInputs {
    func initPeripheral() {
        initPeripheralManager()
        setupPeripheral()
    }
    
    func finalPeripheral() {
        finalPeripheralManager()
    }
    
    func start() {
        startAdvertising()
    }
    
    func stop() {
        stopAdvertising()
    }
    
    func send(data: BluetoothData) {
        log.verbose("send(data: \(data))")

        if case .binary(let packet) = data {
            if let service = self.allServices.filter({ $0.value is SenderService }).first {
                service.value?.packetToSend = packet
                service.value?.send(packet: packet)
            }
        }
    }

    func spt001() {
//        let exampleData = ProjectData(pjtCd: "19ZS", dongCd: "A0026", phseCd: "-", floorCd: "A0210")
        let exampleData = ProjectData(pjtCd: "19SC", dongCd: "A0001", phseCd: "-", floorCd: "A0206")
        let data = serializeProjectData(exampleData)
        let bytes = [UInt8](data)
        let packet = SpotPacket(protocolVersion: 0x01, commandGroup: 0x01, commandId: 0x01, bodyLength: UInt8(bytes.count), body: bytes)
        send(data: .binary(packet))
    }

    func spt003() {
        let doubleArray = [Double(-1561.98876953125),  -44.063999176025391, -511.66659545898438, 0.26332375407218933, 0, -0.014338493347167969, 210]
        let bytes = SpotPacket.convertDoublesToUInt8Array(doubleArray)
        let packet = SpotPacket(protocolVersion: 0x01, commandGroup: 0x01, commandId: 0x03, bodyLength: UInt8(bytes.count), body: bytes)
        send(data: .binary(packet))
    }

    func spt006() {
        let data = UInt8(0x00)
        let bytes: [UInt8] = [data]
        let packet = SpotPacket(protocolVersion: 0x01, commandGroup: 0x01, commandId: 0x06, bodyLength: UInt8(bytes.count), body: bytes)
        send(data: .binary(packet))
    }
}

// MARK: - Outputs
extension PeripheralViewModel: PeripheralViewModelOutputs {
    var error: Observable<PeripheralError> {
        errorSubject.asObservable().compactMap { $0 }
    }

    var status: Observable<BluetoothPeripheralState> {
        statusSubject.asObservable()
    }
    
    var receivedData: Driver<BluetoothData> {
        receiveDataSubject.asDriver(onErrorJustReturn: .unknown)
    }
}

// MARK: - Private
private extension PeripheralViewModel {
    private func initPeripheralManager() {
        //주변 장치 관리자를 인스턴스화할 때 Bluetooth의 전원이 꺼진 상태인 경우 시스템에서 경고해야 하는지 여부를 지정하는 부울 값입니다.
        //CBPeripheralManagerOptionShowPowerAlertKey
        
        //주변 장치 관리자를 인스턴스화하는 데 사용되는 UID(고유 식별자)입니다.
        //CBPeripheralManagerOptionRestoreIdentifierKey
        
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
    }
    
    private func setupPeripheral() {
        // Create a service from the characteristic.
        let senderService = SenderService(type: TransferService.serviceUUID, primary: true)
        senderService.peripheralManager = peripheralManager
        senderService.completion.subscribe(onNext: { _ in
            log.verbose("send data")
        }).disposed(by: disposeBag)
        
        let receiverService = ReceiverService(type: TransferService.serviceUUID, primary: true)
        receiverService.peripheralManager = peripheralManager
        receiverService.completion.subscribe(onNext: { _ in
            log.verbose("receive data")
        }).disposed(by: disposeBag)
                    
        // And add it to the peripheral manager.
        peripheralManager.add(senderService)
        allServices.append(Weak<CustomService>(senderService))
        
        peripheralManager.add(receiverService)
        allServices.append(Weak<CustomService>(receiverService))
    }
    
    private func finalPeripheralManager() {
        log.verbose("all service : \(allServices)")
        
        allServices.removeAll(keepingCapacity: false)
        peripheralManager.removeAllServices()
        
        statusSubject.onNext(.disconnected)
    }
    
    private func startAdvertising() {
        log.verbose("startAdvertising")
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TransferService.serviceUUID],
                                               CBAdvertisementDataLocalNameKey: TransferService.peripheralName])
        
        statusSubject.onNext(.advertising)
    }
    
    private func stopAdvertising() {
        log.verbose("stopAdvertising")
        // 우리가 표시되지 않는 동안 광고를 계속하지 마십시오.
        peripheralManager.stopAdvertising()
        
        statusSubject.onNext(.idle)
    }
}

extension PeripheralViewModel: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
//        advertisingSwitch.isEnabled = peripheral.state == .poweredOn
        
        switch peripheral.state {
            case .poweredOn:
                log.verbose("CBManager is powered on")
                statusSubject.onNext(.powerOn)
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
            
            if let service = allServices.filter({ $0.value?.transferCharacteristic?.uuid == aRequest.characteristic.uuid }).first {
                if service.value?.type == .read {
                    let packet = SpotPacket(bytes: [UInt8](requestValue)) //TODO: 데이터가 제대로 들어오는지 확인해야 함.
                    self.receiveDataSubject.onNext(.binary(packet))
                    dataToReceive.removeAll(keepingCapacity: false)
                }
            }
        }
    }
}

class CustomService: CBMutableService {
    let disposeBag = DisposeBag()
    
    var transferCharacteristic: CBMutableCharacteristic?
    weak var peripheralManager: CBPeripheralManager?
    weak var connectedCentral: CBCentral?
    
    var type: ServiceType = .read
    private var sendingEOM = false
    
    var packetToSend: SpotPacket?
    var dataToSend = Data()
    var sendDataIndex: Int = 0
    
    private var completedSubject: PublishSubject<Void> = .init()
    var completion: Observable<Void> {
        completedSubject.asObservable()
    }
    
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
        
        guard let transferCharacteristic = transferCharacteristic else {
            return
        }

        //Send it
        let eomSent = peripheralManager.updateValue("EOM".data(using: .utf8)!,
                                                    for: transferCharacteristic, onSubscribedCentrals: nil)
        
        if eomSent {
            // It sent; we're all done
            sendingEOM = false
            log.verbose("Sent: EOM")
            
            completedSubject.onNext(())
            
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
        
        guard let transferCharacteristic = transferCharacteristic else {
            return
        }
        
//        let data = Data(bytes: packet.body, count: Int(packet.bodyLength))
        //보낼때
        let didSend = peripheralManager.updateValue(packet.data, for: transferCharacteristic, onSubscribedCentrals: nil)
        
        log.info("didSend: \(didSend)")
        
        completedSubject.onNext(())
    }
    
    func sendData() {
        guard let peripheralManager = peripheralManager else {
            return
        }
        
        guard let transferCharacteristic = transferCharacteristic else {
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

class SenderService: CustomService {
    override func setUp() {
        type = .read
        
        let characteristic = CBMutableCharacteristic(type: TransferService.serverRxCharacteristicUUID,
                                                     properties: [.read, .notify],
                                                     value: nil,
                                                     permissions: [.readable, .readEncryptionRequired])
        transferCharacteristic = characteristic
        // Add the characteristic to the service.
        characteristics = [characteristic]
        
    }
}

class ReceiverService: CustomService {
    override func setUp() {
        type = .write
        
        let characteristic = CBMutableCharacteristic(type: TransferService.serverTxCharacteristicUUID,
                                                     properties: [.write, .writeWithoutResponse],
                                                     value: nil,
                                                     permissions: [.writeable, .writeEncryptionRequired])
        transferCharacteristic = characteristic
        // Add the characteristic to the service.
        characteristics = [characteristic]
    }
}

// 데이터 구조 정의
struct ProjectData {
    let pjtCd: String
    let dongCd: String
    let phseCd: String
    let floorCd: String
}

// 문자열을 직렬화하는 함수
func serializeString(_ string: String) -> Data {
    var data = Data()
    let length = UInt8(string.count)
    data.append(length)
    if let stringData = string.data(using: .utf8) {
        data.append(stringData)
    }
    return data
}

// 전체 데이터를 직렬화하는 함수
func serializeProjectData(_ projectData: ProjectData) -> Data {
    var data = Data()
    
    data.append(serializeString(projectData.pjtCd))
    data.append(serializeString(projectData.dongCd))
    data.append(serializeString(projectData.phseCd))
    data.append(serializeString(projectData.floorCd))
    
    return data
}
