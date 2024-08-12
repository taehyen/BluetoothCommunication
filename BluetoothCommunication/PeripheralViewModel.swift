//
//  PeripheralViewModel.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 3/29/24.
//

import RxSwift
import RxCocoa
import CoreBluetooth

private protocol PeripheralCommunicationInterface {
    func send_spt001(pjtCd: String, dongCd: String, floorCd: String)
    func send_spt003()
    func send_spt006()
    
    func receive_spt002(packet: SpotPacket)
    func receive_spt004(packet: SpotPacket)
    func receive_spt005(packet: SpotPacket)
    func receive_spt007(packet: SpotPacket)
}

protocol PeripheralViewModelType {
    var inputs: PeripheralViewModelInputs { get }
    var outputs: PeripheralViewModelOutputs { get }
}

protocol PeripheralViewModelInputs {
    func start()
    func stop()
}

protocol PeripheralViewModelOutputs {
    var status: Observable<BluetoothPeripheralState> { get }
    var connected: Observable<Bool> { get }
    var bluetoothInfo: Observable<(String, String, String)> { get }
    var receiveString: Observable<String> { get }
}

// MARK: - ViewModel
class PeripheralViewModel: NSObject, PeripheralViewModelType {
    var disposeBag = DisposeBag()
    
    private var statusSubject: PublishSubject<BluetoothPeripheralState> = .init()
    private var connectedSubject: PublishSubject<Bool> = .init()
    private var receiveStringSubject: PublishSubject<String> = .init()
    
    private var serviceInfoSubject: PublishSubject<String> = .init()
    private var characteristicInfoSubject: PublishSubject<String> = .init()
    private var descriptorInfoSubject: PublishSubject<String> = .init()
    
//    let spotProxyServer = PeripheralProxyServer.shared
    private let communicator = BluetoothPeripheralCommunicator()

    override init() {
        super.init()
        communicator.delegate = self
        communicator.initPeripheralManager()
        communicator.setupPeripheral()
    }

    deinit {
        log.verbose("\(String(describing: self)) disposed")
        communicator.finalPeripheralManager()
    }

    var inputs: PeripheralViewModelInputs { self }
    var outputs: PeripheralViewModelOutputs { self }
}

// MARK: - Inputs
extension PeripheralViewModel: PeripheralViewModelInputs {
    func start() {
        communicator.startAdvertising()
    }
    
    func stop() {
        communicator.stopAdvertising()
    }
}

// MARK: - Outputs
extension PeripheralViewModel: PeripheralViewModelOutputs {
    var connected: RxSwift.Observable<Bool> {
        connectedSubject.asObservable()
    }
    
    var bluetoothInfo: RxSwift.Observable<(String, String, String)> {
        Observable.combineLatest(serviceInfoSubject, characteristicInfoSubject, descriptorInfoSubject)
    }
    
    var status: Observable<BluetoothPeripheralState> {
        statusSubject.asObservable()
    }
    
    var receiveString: Observable<String> {
        receiveStringSubject.asObservable()
    }
}

extension PeripheralViewModel: BluetoothPeripheralCommunicatorDelegate {
    func didReceive(data: BluetoothData) {
        self.receive(bluetoothData: data)
    }
    
    func didConnected(_ connected: Bool) {
        
    }
    
    func didUpdate(state: BluetoothPeripheralState) {
        statusSubject.onNext(state)
    }
    
    func didReceive(error: PeripheralError) {
        log.error(error.localizedDescription)
    }
    
    func didReceive(serviceInfo: String) {
        serviceInfoSubject.onNext(serviceInfo)
    }
    
    func didReceive(characteristicInfo: String) {
        characteristicInfoSubject.onNext(characteristicInfo)
    }
    
    func didReceive(descriptorInfo: String) {
        descriptorInfoSubject.onNext(descriptorInfo)
    }
}

extension PeripheralViewModel: PeripheralCommunicationInterface {
    func send_spt001(pjtCd: String, dongCd: String, floorCd: String) {
        let exampleData = ProjectData(pjtCd: pjtCd, dongCd: dongCd, phseCd: "-", floorCd: floorCd)
        let data = serializeProjectData(exampleData)
        let bytes = [UInt8](data)
        let packet = SpotPacket(protocolVersion: 0x01, commandGroup: 0x01, commandId: 0x01, bodyLength: UInt8(bytes.count), body: bytes)
        communicator.send(data: .binary(packet))
    }
    
    func send_spt003() {
        let doubleArray = [Double(-1561.98876953125),  -44.063999176025391, -511.66659545898438, 0.26332375407218933, 0, -0.014338493347167969, 210]
        let bytes = SpotPacket.convertDoublesToUInt8Array(doubleArray)
        let packet = SpotPacket(protocolVersion: 0x01, commandGroup: 0x01, commandId: 0x03, bodyLength: UInt8(bytes.count), body: bytes)
        communicator.send(data: .binary(packet))
    }
    
    func send_spt006() {
        let data = UInt8(0x00)
        let bytes: [UInt8] = [data]
        let packet = SpotPacket(protocolVersion: 0x01, commandGroup: 0x01, commandId: 0x06, bodyLength: UInt8(bytes.count), body: bytes)
        communicator.send(data: .binary(packet))
    }
    
    func receive_spt002(packet: SpotPacket) {
        log.debug("\(packet)")
        
        let doubleArray = SpotPacket.convertUInt8ArrayToDoubles(packet.body)
        receiveStringSubject.onNext("\(doubleArray)")
    }
    
    func receive_spt004(packet: SpotPacket) {
        log.debug("\(packet)")
        
        let doubleArray = SpotPacket.convertUInt8ArrayToDoubles(packet.body)
        receiveStringSubject.onNext("\(doubleArray)")
    }
    
    func receive_spt005(packet: SpotPacket) {
        log.debug("\(packet)")
        
        let doubleArray = SpotPacket.convertUInt8ArrayToDoubles(packet.body)
        receiveStringSubject.onNext("\(doubleArray)")
    }
    
    func receive_spt007(packet: SpotPacket) {
        log.debug("\(packet)")
        
        let doubleArray = SpotPacket.convertUInt8ArrayToDoubles(packet.body)
        receiveStringSubject.onNext("\(doubleArray)")
    }
}

extension PeripheralViewModel {
    func receive(bluetoothData: BluetoothData) {
        if case .binary(let packet) = bluetoothData {
            receive(packet: packet)
        } else {
            // 지원하지 않는 형식 (text, image)
        }
    }
    
    func receive(packet: SpotPacket) {
        log.info("receive packet: \(packet)")
        
        //수신된 데이터에 따라, 각 함수 호출
        switch (packet.commandGroup, packet.commandId) {
            case (0x02, 0x02): receive_spt002(packet: packet)
            case (0x02, 0x04): receive_spt004(packet: packet)
            case (0x02, 0x05): receive_spt005(packet: packet)
            case (0x02, 0x07): receive_spt007(packet: packet)
            default:
                break
        }
    }
    
    func send(packet: SpotPacket) {
        communicator.send(data: BluetoothData.binary(packet))
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
