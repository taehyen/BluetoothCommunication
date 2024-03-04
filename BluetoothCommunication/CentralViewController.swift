//
//  CentralViewController.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 2/26/24.
//

import UIKit
import CoreBluetooth
import RxSwift
import RxCocoa
import RxMediaPicker

class CentralViewController: UIViewController {
    private let disposeBag = DisposeBag()
    
    @IBOutlet var textView: UITextView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var selectImageButton: UIButton!
    
    lazy var picker: RxMediaPicker = {
        RxMediaPicker(delegate: self)
    }()

    override func viewDidLoad() {
        initCentralManager()
        
        textView.delegate = self
        textView.text = ""
        
        selectImageButton.setTitle("Select Image", for: .normal)
        selectImageButton.setTitleColor(.blue, for: .normal)
        selectImageButton.setTitle("Unselect Image", for: .selected)
        selectImageButton.setTitleColor(.white, for: .selected)
    
        selectImageButton.rx.tap.throttle(.seconds(1), scheduler: MainScheduler.instance).subscribe(onNext: { _ in
            if self.selectImageButton.isSelected {
                self.selectImageButton.isSelected = false
                self.imageView.image = nil
            } else {
                self.selectImage()
            }
        }).disposed(by: disposeBag)
        
        super.viewDidLoad()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        finalCentralManager()
        super.viewWillDisappear(animated)
    }
    
    var centralManager: CBCentralManager!
    
    var discoveredPeripheral: CBPeripheral?
    
    /// CBPeripherialDelegate 내에서 주로 사용되어지며, peripheral로 전송하려는 특성을 나타낸다.
    var transferCharacteristic: CBCharacteristic?
    
    /// 연결 재시도 카운트
    var connectionIterationsComplete = 0
    
    /// Peripheral로 쓰기시도 카운트
    var writeIterationsComplete = 0
    
    /// 연결 재시도 최대 횟수 : 현재 1000번 재시도
    let defaultIterations = 1000
    
    /// 수신하는 데이터가 나누어져서 올 수 있기 때문에 EOM(end of message)을 받기 전에 이곳에 쌓아둔다.
    var data = Data()
}

extension CentralViewController {
    private func initCentralManager() {
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }
    
    private func finalCentralManager() {
        centralManager.stopScan()
        log.info("Scanning stopped")
        
        data.removeAll(keepingCapacity: false)
    }
    
    /*
     먼저 상대방과 이미 연결되어 있는지 확인하겠습니다.
     그렇지 않은 경우에는 주변 장치를 검색하십시오. 특히 이 회사의 서비스의 128비트 CBUUID에 대한 것입니다.
     */
    private func retrievePeripheral() {
        let connectedPeripherals: [CBPeripheral] = (centralManager.retrieveConnectedPeripherals(withServices: [TransferService.serviceUUID]))
        
        log.verbose("Found connected Peripherals with transfer service: \(connectedPeripherals)")
        
        if let connectedPeripheral = connectedPeripherals.last {
            log.verbose("Connecting to peripheral \(connectedPeripheral)")
            
            self.discoveredPeripheral = connectedPeripheral
            centralManager.connect(connectedPeripheral, options: nil)
        } else {
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
    private func cleanup() {
        // 우리가 연결되어 있지 않다면 아무것도 하지 마세요
        guard let discoveredPeripheral = discoveredPeripheral,
              case .connected = discoveredPeripheral.state else { return }
        
        for service in (discoveredPeripheral.services ?? [] as [CBService]) {
            for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {
                if characteristic.uuid == TransferService.characteristicUUID && characteristic.isNotifying {
                    // 알림이 오니까 구독취소
                    self.discoveredPeripheral?.setNotifyValue(false, for: characteristic)
                }
            }
        }
        
        // 여기까지 했다면 연결은 되었지만 구독이 안되어 그냥 연결이 끊어진 것입니다.
        centralManager.cancelPeripheralConnection(discoveredPeripheral)
    }
    
    /*
     *  주변 장치에 일부 테스트 데이터 쓰기
     */
    private func writeData() {
        
        guard let discoveredPeripheral = discoveredPeripheral,
              let transferCharacteristic = transferCharacteristic
        else { return }
        
        // 완료된 반복 횟수와 주변 장치가 더 많은 데이터를 수용할 수 있는지 확인하십시오.
        while writeIterationsComplete < defaultIterations && discoveredPeripheral.canSendWriteWithoutResponse {
            
            let mtu = discoveredPeripheral.maximumWriteValueLength (for: .withoutResponse)
            var rawPacket = [UInt8]()
            
            let bytesToCopy: size_t = min(mtu, data.count)
            data.copyBytes(to: &rawPacket, count: bytesToCopy)
            let packetData = Data(bytes: &rawPacket, count: bytesToCopy)
            
            let stringFromData = String(data: packetData, encoding: .utf8)
            log.verbose("Writing \(bytesToCopy) bytes: \(String(describing: stringFromData))")
            
            discoveredPeripheral.writeValue(packetData, for: transferCharacteristic, type: .withoutResponse)
            
            writeIterationsComplete += 1
            
        }
        
        if writeIterationsComplete == defaultIterations {
            discoveredPeripheral.writeValue("EOM".data(using: .utf8)!, for: transferCharacteristic, type: .withoutResponse)
            
            // 특성 구독 취소
            discoveredPeripheral.setNotifyValue(false, for: transferCharacteristic)
        }
    }
}

extension CentralViewController: CBCentralManagerDelegate {
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
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard RSSI.intValue >= -50 else {
            log.warning("Discovered peripheral not in expected range, at \(RSSI)")
            return
        }
        
        log.verbose("Discovered \(peripheral.name ?? "unknown name") at \(RSSI)")
        
        if discoveredPeripheral != peripheral {
            discoveredPeripheral = peripheral
            log.verbose("Connecting to peripheral \(peripheral)")
            centralManager.connect(peripheral, options: nil)
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
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.warning("Failed to connect to \(peripheral). \(String(describing: error))")
        cleanup()
    }
    
    //주변기기와 연결했으니 이제 '전송' 특성을 찾기 위해 서비스와 특성을 찾아야 합니다.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.verbose("Peripheral Connected")
        
        centralManager.stopScan()
        log.verbose("Scanning stoppped")
        
        connectionIterationsComplete += 1
        writeIterationsComplete = 0
        
        //이미 가지고 있을 수 있는 데이터 지우기
        data.removeAll(keepingCapacity: false)
        
        peripheral.delegate = self //CBPeripheralDelegate
        peripheral.discoverServices([TransferService.serviceUUID])
    }
    
    //연결이 끊어지면 주변 장치의 로컬 복사본을 정리해야 합니다.
    //5+
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        discoveredPeripheral = nil
        
        //연결이 끊어졌으니 다시 스캔을 시작하세요
        if connectionIterationsComplete < defaultIterations {
            retrievePeripheral()
        } else {
            log.warning("Connection iterations completed")
        }
    }
}

extension CentralViewController: CBPeripheralDelegate {
    //서비스가 무효화되었을 때 이를 알려주는 주변 장치입니다.
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        for service in invalidatedServices where service.uuid == TransferService.serviceUUID {
            log.verbose("Transfer service is invalidated - rediscover services")
            peripheral.discoverServices([TransferService.serviceUUID])
        }
    }
    
    //Transfer Service가 발견되었습니다.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            log.error("Error discovering services: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        //TODO: 원하는 characteristic(특성)을 여기서 찾아볼 것
        
        //둘 이상이 있을 경우를 대비하여 새로 채워진 Peripheral.services 배열을 반복합니다.
        guard let peripheralServices = peripheral.services else { return }
        for service in peripheralServices {
            peripheral.discoverCharacteristics([TransferService.characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log.error("Error discovering characteristics: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        //다시 한 번, 만약을 대비해 배열을 반복하고 그것이 올바른지 확인합니다.
        guard let serviceCharacteristics = service.characteristics else { return }
        for characteristic in serviceCharacteristics where characteristic.uuid == TransferService.characteristicUUID {
            
            //TODO: 찾는게 나오면 구독하는 처리를 여기서 할 것.
            
            transferCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
        
        //이 작업이 완료되면 데이터가 들어올 때까지 기다리면 됩니다.
    }
    
//    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
//    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log.error("Error discovering characteristics: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        guard let characteristicData = characteristic.value else {
            return
        }
        
        let stringFromData = String(data: characteristicData, encoding: .utf8)
        log.verbose("Received \(characteristicData.count) bytes: \(String(describing: stringFromData))")
        
        //메시지 끝 토큰을 받게 되면
        if stringFromData == "EOM" {
            //이 메서드가 어느 스레드에서 다시 호출될지 모르기 때문에 UI 업데이트를 위해 텍스트 보기 업데이트를 기본 대기열로 전달합니다.
            DispatchQueue.main.async {
                //TODO: 데이터를 보여주거나 마지막에 처리하는 쪽.
//                self.textView.text = String(data: self.data, encoding: .utf8)
                self.imageView.image = UIImage(data: self.data)
                
                self.removeImage()
                self.data.removeAll(keepingCapacity: false)
            }
        } else {
            //그렇지 않으면 이전에 받은 데이터에 데이터를 추가하면 됩니다.
            data.append(characteristicData)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log.error("Error changing notification state: \(error.localizedDescription)")
            return
        }
        
        // 전송 특성이 아닐 경우 종료
        guard characteristic.uuid == TransferService.characteristicUUID else { return }
        
        if characteristic.isNotifying {
            // 알림이 시작되었습니다
            log.verbose("Notification began on \(characteristic)")
        } else {
            // 알림이 중지되었으므로 주변기기와의 연결을 끊습니다.
            log.verbose("Notification stopped on \(characteristic). Disconnecting")
            cleanup()
        }
    }
    
    //응답 없이 쓰기를 사용할 때 주변기기가 더 많은 데이터를 받아들일 준비가 되었을 때 호출됩니다.
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        log.verbose("Peripheral is ready, send data")
        writeData()
    }
}

extension CentralViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        let rightButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard))
        navigationItem.rightBarButtonItem = rightButton
    }
    
    func textViewDidChange(_ textView: UITextView) {
        removeImage()
        data = textView.text.data(using: .utf8)!
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        writeData()
    }

    @objc
    func dismissKeyboard() {
        textView.resignFirstResponder()
        navigationItem.rightBarButtonItem = nil
    }
}

extension CentralViewController: RxMediaPickerDelegate {
    func present(picker: UIImagePickerController) {
        present(picker, animated: true)
    }
    
    func dismiss(picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

extension CentralViewController {
    func set(image: UIImage) {
        self.imageView.image = image
    }
    
    func removeImage() {
        self.selectImageButton.isSelected = false
        self.imageView.image = nil
    }
    
    func selectImage() {
        self.textView.text = ""
        
        picker.selectImage().subscribe(onNext: { (image, editedImage) in
            self.imageView.image = editedImage != nil ? editedImage : image
            self.selectImageButton.isSelected = true
            
            //TODO: it needs to send image data after change bytes to periphercal connected.
            if let data = self.imageView.image?.jpegData(compressionQuality: 0.7) {
                self.data = data
                
                self.writeData()
            }
        }).disposed(by: disposeBag)
    }
}
