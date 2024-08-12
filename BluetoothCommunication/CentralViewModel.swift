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

protocol CentralViewModelType {
    var inputs: CentralViewModelInputs { get }
    var outputs: CentralViewModelOutputs { get }
}

protocol CentralViewModelInputs {
    func spt002()
    func spt004()
    func spt005()
    func spt007()
}

protocol CentralViewModelOutputs {
    var initialInfo: Observable<SpotInitialInfo> { get }
    var slamBySpot: Observable<CentralProxyServer.Slam> { get }
    var endCapture: Observable<Bool> { get }
    var connected: Observable<Bool> { get }
    var bluetoothInfo: Observable<(String, String, String)> { get }
}

class CentralViewModel: NSObject, CentralViewModelType {
    private let disposeBag = DisposeBag()
    
    let spotProxyServer = CentralProxyServer.shared
    
    var sceneId = UUID().uuidString.lowercased()
    var newSceneId = UUID().uuidString.lowercased()
    
    override init() {
        super.init()
    }
    
    deinit {
        log.verbose("\(String(describing: self)) disposed")
    }
    
    var inputs: CentralViewModelInputs { self }
    var outputs: CentralViewModelOutputs { self }
}

// MARK: - Inputs
extension CentralViewModel: CentralViewModelInputs {
    func spt002() {
        spotProxyServer.send_spt002(isConnected: true)
    }
    
    func spt004() {
        spotProxyServer.send_spt004(true, sceneId: sceneId)
    }
    
    func spt005() {
        spotProxyServer.send_spt005(true, originSceneId: sceneId, newSceneId: newSceneId)
    }
    
    func spt007() {
        spotProxyServer.send_spt007()
    }
}

// MARK: - Outputs
extension CentralViewModel: CentralViewModelOutputs {
    var initialInfo: Observable<SpotInitialInfo> {
        spotProxyServer.initialInfo
    }
    var slamBySpot: Observable<CentralProxyServer.Slam> {
        spotProxyServer.slamBySpot
    }
    var endCapture: Observable<Bool> {
        spotProxyServer.endCapture
    }
    var connected: Observable<Bool> {
        spotProxyServer.connected
    }
    var bluetoothInfo: Observable<(String, String, String)> {
        spotProxyServer.bluetoothInfo
    }
}

// MARK: - Private
private extension CentralViewModel {
}
