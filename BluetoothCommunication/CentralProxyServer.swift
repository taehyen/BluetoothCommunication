//
//  SpotProxyServer.swift
//  Quicksite
//
//  Created by 3i-A1-2022-033 on 4/15/24.
//  Copyright © 2024 3i. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

private protocol CentralCommunicationInterface {
	func receive_spt001(packet: SpotPacket) //SPOT이 촬영 요청하기 전 BEAMO 에게 준비하라는 알림
	func send_spt002(isConnected: Bool) //BEAMO가 SPOT에게 준비가 완료됨을 알림
	func receive_spt003(packet: SpotPacket) //SPOT BEAMO에게 촬영 요청
	func send_spt004(_ result: Bool, sceneId: String) //BEAMO가 SPOT에게 촬영요청 결과를 응답함
	func send_spt005(_ result: Bool, originSceneId: String, newSceneId: String) //BEAMO가 SPOT에게 촬영 데이터 서버 업로드 결과를 알려줌
	func receive_spt006(packet: SpotPacket) //SPOT이 BEAMO에게 촬영이 종료되었음을 알림
	func send_spt007() //BEAMO가 SPOT에게 필요한 상태 정보를 제공
}

protocol CentralProxyServerType {
	var inputs: CentralProxyServerSender { get }
	var outputs: CentralProxyServerReceiver { get }
}

protocol CentralProxyServerSender {
	func sendingStatusReady(isConnected: Bool)
	func sendingResultCaptured(_ result: Bool, sceneId: String)
	func sendingResultUploaded(_ result: Bool, originSceneId: String, newSceneId: String)
	func notifyDeviceStatus()
}

protocol CentralProxyServerReceiver {
	var initialInfo: Observable<SpotInitialInfo> { get }
	var slamBySpot: Observable<CentralProxyServer.Slam> { get }
	var endCapture: Observable<Bool> { get }
	var connected: Observable<Bool> { get }
    var bluetoothInfo: Observable<(String, String, String)> { get }
}

class CentralProxyServer {
	static let shared = CentralProxyServer()
	
	private let disposeBag = DisposeBag()
	private let bluetoothCommunicator = BluetoothCentralCommunicator()
	
	private var initialInfoSubject: PublishSubject<SpotInitialInfo> = .init()
	private var slamBySpotSubject: PublishSubject<CentralProxyServer.Slam> = .init()
	private var endCaptureSubject: PublishSubject<Bool> = .init()
	private var connectedSubject: PublishSubject<Bool> = .init()
    
    private var serviceInfoSubject: PublishSubject<String> = .init()
    private var characteristicInfoSubject: PublishSubject<String> = .init()
    private var descriptorInfoSubject: PublishSubject<String> = .init()
	
	init() {
		setUp()
	}
	
	deinit {
		bluetoothCommunicator.inputs.finalCentral()
	}
	
	func setUp() {
		bluetoothCommunicator.delegate = self
		
		bluetoothCommunicator.inputs.initCentral()
	}
	
	var sender: CentralProxyServerSender { self }
	var receiver: CentralProxyServerReceiver { self }
}

extension CentralProxyServer: CentralProxyServerSender {
	func sendingStatusReady(isConnected: Bool) {
		log.info("spt002 - isConnected: \(isConnected)")
		send_spt002(isConnected: isConnected)
	}
	
	func sendingResultCaptured(_ result: Bool, sceneId: String) {
		log.info("spt004 - result: \(result), sceneId: \(sceneId)")
		send_spt004(result, sceneId: sceneId)
	}
	
	func sendingResultUploaded(_ result: Bool, originSceneId: String, newSceneId: String) {
		log.info("spt005 - result: \(result), originSceneId: \(originSceneId), newSceneId: \(newSceneId)")
		send_spt005(result, originSceneId: originSceneId, newSceneId: newSceneId)
	}
	
	func notifyDeviceStatus() {
		log.info("spt007")
		send_spt007()
	}
}

extension CentralProxyServer: CentralProxyServerReceiver {
	var initialInfo: Observable<SpotInitialInfo> {
		initialInfoSubject.asObservable()
	}
	
	var slamBySpot: Observable<CentralProxyServer.Slam> {
		slamBySpotSubject.asObservable()
	}
	
	var endCapture: Observable<Bool> {
		endCaptureSubject.asObservable()
	}
	
	var connected: Observable<Bool> {
		connectedSubject.asObservable()
	}
    
    var bluetoothInfo: Observable<(String, String, String)> {
        Observable.combineLatest(serviceInfoSubject, characteristicInfoSubject, descriptorInfoSubject)
    }
}

extension CentralProxyServer: BluetoothCentralCommunicatorDelegate {
	func didReceive(error: CentralError) {
		log.error(error.localizedDescription)
	}
	
	func didReceive(data: BluetoothData) {
		self.receive(bluetoothData: data)
	}
	
	func didConnected(_ connected: Bool) {
		connectedSubject.onNext(connected)
	}
	
	func didUpdate(state: BluetoothCentralState) {
		log.verbose(state)
	}
    
    func didReceive(serviceInfo: String) {
        serviceInfoSubject.onNext(serviceInfo)
    }
    
    func didReceive(descriptorInfo: String) {
        descriptorInfoSubject.onNext(descriptorInfo)
    }
    
    func didReceive(characteristicInfo: String) {
        characteristicInfoSubject.onNext(characteristicInfo)
    }
}

extension CentralProxyServer: CentralCommunicationInterface {
	/// SPOT이 촬영 요청하기 전 BEAMO 에게 준비하라는 알림
	func receive_spt001(packet: SpotPacket) {
		/*
		 pjtCd        : 프로젝트 코드 (ex - 19SC)
		 dongCd    : 동 코드 (ex - A0001)
		 phseCd    : Phase 코드 (향후 추가될 가능성 있음 임시 "-")
		 floorCd     : 층 코드 (ex - A0203)
		 */
		//site, building, dongCd
		//plan, floor, floorCd
		//survey, scene (촬영한 지점)
		
		guard let info = SpotInitialInfo.extractData(from: packet.body) else {
			log.error("extract data error")
			return
		}
		
		log.info("spt001 - info: \(info)")
		//이후에 floor code를 floor id로 변환하는 과정해야 함.
		initialInfoSubject.onNext(info)
	}
	
	/// BEAMO가 SPOT에게 준비가 완료됨을 알림
	func send_spt002(isConnected: Bool) {
		var bytes: [UInt8] = []
		bytes.append(isConnected == true ? 0x00 : 0x01)
		
		let packet = SpotPacket(protocolVersion: 0x01, commandGroup: 0x02, commandId: 0x02, bodyLength: UInt8(bytes.count), body: bytes)
		
		send(packet: packet)
	}
	
	/// SPOT BEAMO에게 촬영 요청
	func receive_spt003(packet: SpotPacket) {
		let doubleArray = SpotPacket.convertUInt8ArrayToDoubles(packet.body)
		let x = doubleArray[0]
		let y = doubleArray[1]
		let z = doubleArray[2]
		let roll = doubleArray[3]
		let pitch = doubleArray[4]
		let yaw = doubleArray[5]
		let slamDictionary = ["slam": ["position": ["x": x, "y": y, "z": z], "rotation": ["roll": roll, "pitch": pitch, "yaw": yaw]]]
		
		log.info("spt003 - Slam : \(slamDictionary)")
		
		guard let slam = convertDictionaryToSlam(dictionary: slamDictionary) else {
			log.error("error convertDictionaryToSlam")
			return
		}
		
		//이후에 촬영요청을 받는 쪽에서 해야 함
		slamBySpotSubject.onNext(slam)
	}
	
	/// BEAMO가 SPOT에게 촬영요청 결과를 응답함
	func send_spt004(_ result: Bool, sceneId: String) {
		var bytes: [UInt8] = []
		if sceneId.count > 0 {
			let uuid = sceneId //촬영한 포인트의 uuid
			let data = uuid.data(using: .utf8)!
			bytes = [UInt8](data)
		}
		
		bytes.insert(result == true ? UInt8(0x00) : UInt8(0x01), at: 0)
		
		let packet = SpotPacket(protocolVersion: 0x01, commandGroup: 0x02, commandId: 0x04, bodyLength: UInt8(bytes.count), body: bytes)
		send(packet: packet)
	}
	
	/// BEAMO가 SPOT에게 촬영 데이터 서버 업로드 결과를 알려줌
	func send_spt005(_ result: Bool, originSceneId: String, newSceneId: String) {
		var bytes: [UInt8] = []
		
		if originSceneId.count > 0 {
			let uuid = originSceneId //업로드한 포인트의 uuid
			let data = uuid.data(using: .utf8)!
			bytes = [UInt8](data)
		}
		
		if newSceneId.count > 0 {
			let uuid = newSceneId //업로드한 포인트의 uuid
			let data = uuid.data(using: .utf8)!
			bytes = [UInt8](data)
		}
		
		bytes.insert(result == true ? UInt8(0x00) : UInt8(0x01), at: 0)
		
		let packet = SpotPacket(protocolVersion: 0x01, commandGroup: 0x02, commandId: 0x05, bodyLength: UInt8(bytes.count), body: bytes)
		send(packet: packet)
	}
	
	/// SPOT이 BEAMO에게 촬영이 종료되었음을 알림
	func receive_spt006(packet: SpotPacket) {
		let data = Data(bytes: packet.body, count: Int(packet.bodyLength))
		
		guard packet.bodyLength >= 1 else {
			return
		}
		
		let result = packet.body[0] == 0x00
		
		log.info("spt006 = result: \(result)")
		
		//이후에 무한 업로드 시도
		endCaptureSubject.onNext(result)
	}
	
	/// BEAMO가 SPOT에게 필요한 상태 정보를 제공
    func send_spt007() {
        var uint8Array: [UInt8] = []
        uint8Array.append(100)  //360카메라 배터리 상태
        uint8Array.append(100)  //아이폰 배터리 상태
        uint8Array.append(0x01)  //iphone and 360
        uint8Array.append(0x00)  //vpn
        
        let packet = SpotPacket(protocolVersion: 0x01, commandGroup: 0x02, commandId: 0x07, bodyLength: UInt8(uint8Array.count), body: uint8Array)
        
        send(packet: packet)
    }
}

extension CentralProxyServer {
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
			case (0x01, 0x01): receive_spt001(packet: packet)
			case (0x01, 0x03): receive_spt003(packet: packet)
			case (0x01, 0x06): receive_spt006(packet: packet)
			default:
				break
		}
	}
	
	func send(packet: SpotPacket) {
		bluetoothCommunicator.inputs.send(data: BluetoothData.binary(packet))
	}
}

struct SpotInitialInfo {
	let pjtCd: String
	let dongCd: String
	let phseCd: String
	let floorCd: String
}

extension SpotInitialInfo {
	static func extractData(from byteArray: [UInt8]) -> SpotInitialInfo? {
		var offset = 0
		
		func extractString(from byteArray: [UInt8], offset: inout Int) -> String? {
			guard offset < byteArray.count else { return nil }
			let length = Int(byteArray[offset])
			offset += 1
			guard offset + length <= byteArray.count else { return nil }
			let stringData = Data(byteArray[offset..<(offset + length)])
			offset += length
			return String(data: stringData, encoding: .utf8)
		}
		
		guard let pjtCd = extractString(from: byteArray, offset: &offset),
			  let dongCd = extractString(from: byteArray, offset: &offset),
			  let phseCd = extractString(from: byteArray, offset: &offset),
			  let floorCd = extractString(from: byteArray, offset: &offset) else {
			return nil
		}
		
		return SpotInitialInfo(pjtCd: pjtCd, dongCd: dongCd, phseCd: phseCd, floorCd: floorCd)
	}
}

extension CentralProxyServer {
	struct Position: Codable {
		var x: Double
		var y: Double
		var z: Double
	}
	
	struct Rotation: Codable {
		var roll: Double
		var pitch: Double
		var yaw: Double
	}
	
	struct Slam: Codable {
		var position: Position
		var rotation: Rotation
	}
	
	func convertDictionaryToSlam(dictionary: [String: Any]) -> Slam? {
		guard
			let slamData = dictionary["slam"] as? [String: Any],
			let positionData = slamData["position"] as? [String: Double],
			let rotationData = slamData["rotation"] as? [String: Double],
			let x = positionData["x"],
			let y = positionData["y"],
			let z = positionData["z"],
			let roll = rotationData["roll"],
			let pitch = rotationData["pitch"],
			let yaw = rotationData["yaw"]
		else {
			return nil
		}
		
		let position = Position(x: x, y: y, z: z)
		let rotation = Rotation(roll: roll, pitch: pitch, yaw: yaw)
		return Slam(position: position, rotation: rotation)
	}
}
