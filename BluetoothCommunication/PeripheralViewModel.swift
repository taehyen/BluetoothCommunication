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
}

protocol PeripheralViewModelOutputs {
    var error: Observable<PeripheralError> { get }
    var receivedData: Observable<BluetoothData> { get }
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
    private let receivedDataSubject: PublishSubject<BluetoothData> = .init()

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
        
        if case .image(let data) = data {
            if let service = self.allServices.filter({ $0.value is ImageTransferService }).first {
                service.value?.dataToSend = data
                service.value?.sendData()
            }
        } else if case .text(let data) = data {
            if let service = self.allServices.filter({ $0.value is TextTransferService }).first {
                service.value?.dataToSend = data
                service.value?.sendData()
            }
        }
    }
}

// MARK: - Outputs
extension PeripheralViewModel: PeripheralViewModelOutputs {
    var error: Observable<PeripheralError> {
        errorSubject.asObservable().compactMap { $0 }
    }
    
    var receivedData: Observable<BluetoothData> {
        receivedDataSubject.asObservable()
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
        let transferService1 = ImageTransferService(type: TransferService.serviceUUID, primary: true)
        transferService1.peripheralManager = peripheralManager
        transferService1.completion.subscribe(onNext: { _ in
            log.verbose("image sent!")
        }).disposed(by: disposeBag)
        
        let transferService2 = TextTransferService(type: TransferService.serviceUUID, primary: true)
        transferService2.peripheralManager = peripheralManager
        transferService2.completion.subscribe(onNext: { _ in
            log.verbose("text sent!")
        }).disposed(by: disposeBag)
        
        // And add it to the peripheral manager.
        peripheralManager.add(transferService1)
        allServices.append(Weak<CustomService>(transferService1))
        peripheralManager.add(transferService2)
        allServices.append(Weak<CustomService>(transferService2))
    }
    
    private func finalPeripheralManager() {
        log.verbose("all service : \(allServices)")
        
        allServices.removeAll(keepingCapacity: false)
        peripheralManager.removeAllServices()
    }
    
    private func startAdvertising() {
        log.verbose("startAdvertising")
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TransferService.serviceUUID],
                                               CBAdvertisementDataLocalNameKey: TransferService.peripheralName])
    }
    
    private func stopAdvertising() {
        log.verbose("stopAdvertising")
        // 우리가 표시되지 않는 동안 광고를 계속하지 마십시오.
        peripheralManager.stopAdvertising()
    }
}

extension PeripheralViewModel: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
//        advertisingSwitch.isEnabled = peripheral.state == .poweredOn
        
        switch peripheral.state {
            case .poweredOn:
                // ... so start working with the peripheral
                log.verbose("CBManager is powered on")
                setupPeripheral()
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
                    switch peripheral.authorization {
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
                log.verbose("A previously unknown peripheral manager state occurred")
                // In a real app, you'd deal with yet unknown cases that might occur in the future
                return
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
            guard let value = $0.value else { return }
            // save central
            value.connectedCentral = central
            
            if value.dataToSend.count > 0 {
                value.sendDataIndex = 0
                value.sendData()
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
                if service.value?.type == .imageOnly {
                    let stringFromData = String(data: requestValue, encoding: .utf8)
                    log.verbose("image::Received write request of \(requestValue.count) bytes: \(String(describing: stringFromData))")
                    if stringFromData == "EOM" {
                        log.verbose("Receive EOM")
                                                
                        self.receivedDataSubject.onNext(.image(dataToReceive))
                        
                        dataToReceive.removeAll(keepingCapacity: false)
                    } else {
                        dataToReceive.append(requestValue)
                    }
                } else if service.value?.type == .textOnly {
                    let stringFromData = String(data: requestValue, encoding: .utf8)
                    log.verbose("text::Received write request of \(requestValue.count) bytes: \(String(describing: stringFromData))")
                    if stringFromData == "EOM" {
                        log.verbose("Receive EOM")
                        
                        self.receivedDataSubject.onNext(.text(requestValue))
                        
                        dataToReceive.removeAll(keepingCapacity: false)
                    } else {
                        dataToReceive.append(requestValue)
                    }
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
    
    var type: ServiceType = .notDefined
    var sendingEOM = false
    
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
            let didSend = peripheralManager.updateValue("EOM".data(using: .utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
            // Did it send?
            if didSend {
                // It did, so mark it as sent
                sendingEOM = false
                log.verbose("Sent: EOM")
            }
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
        }
    }
}

class ImageTransferService: CustomService {
    override func setUp() {
        let characteristic = CBMutableCharacteristic(type: TransferService.imageCharacteristicUUID,
                                                     properties: [.indicate, .writeWithoutResponse, .read],
                                                     value: nil,
                                                     permissions: [.readable, .writeable])
        transferCharacteristic = characteristic
        // Add the characteristic to the service.
        characteristics = [characteristic]
        
    }
}

class TextTransferService: CustomService {
    override func setUp() {
        let characteristic = CBMutableCharacteristic(type: TransferService.textCharacteristicUUID,
                                                     properties: [.indicate, .writeWithoutResponse, .read],
                                                     value: nil,
                                                     permissions: [.readable, .writeable])
        transferCharacteristic = characteristic
        // Add the characteristic to the service.
        characteristics = [characteristic]
    }
}
