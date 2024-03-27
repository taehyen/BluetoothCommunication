//
//  PeripheralViewController.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 2/26/24.
//

import UIKit
import CoreBluetooth
import RxSwift
import RxMediaPicker

class PeripheralViewController: UIViewController {
    let disposeBag = DisposeBag()
    
    lazy var picker: RxMediaPicker = {
        RxMediaPicker(delegate: self)
    }()
    
    @IBOutlet var textView: UITextView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var selectImageButton: UIButton!

    override func viewDidLoad() {
        initPeripheralManager()

        textView.delegate = self
        textView.text = ""
        
        selectImageButton.setTitle("Select Image", for: .normal)
        selectImageButton.setTitleColor(.blue, for: .normal)
        selectImageButton.setTitle("Unselect Image", for: .selected)
        selectImageButton.setTitleColor(.white, for: .selected)
        
        selectImageButton.rx.tap.throttle(.milliseconds(500), scheduler: MainScheduler.instance).subscribe(onNext: { _ in
            if self.selectImageButton.isSelected {
                self.removeImage()
            } else {
                self.selectImage()
            }
        }).disposed(by: disposeBag)
        
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        startAdvertising()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        stopAdvertising()
    }
    
    var peripheralManager: CBPeripheralManager!
    var transferTextCharacteristic: CBMutableCharacteristic?
    var transferImageCharacteristic: CBMutableCharacteristic?
    var connectedCentral: CBCentral?
    
    var dataToSend: [BluetoothData] = []
    var dataToReceive = Data()
    
    var operationQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
}

extension PeripheralViewController {
    private func initPeripheralManager() {
        //주변 장치 관리자를 인스턴스화할 때 Bluetooth의 전원이 꺼진 상태인 경우 시스템에서 경고해야 하는지 여부를 지정하는 부울 값입니다.
        //CBPeripheralManagerOptionShowPowerAlertKey
        
        //주변 장치 관리자를 인스턴스화하는 데 사용되는 UID(고유 식별자)입니다.
        //CBPeripheralManagerOptionRestoreIdentifierKey
        
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
    }
    
    private func setupPeripheral() {
        // Start with the CBMutableCharacteristic.
        let transferTextCharacteristic = CBMutableCharacteristic(type: TransferService.textCharacteristicUUID,
                                                             properties: [.indicate, .writeWithoutResponse, .read],
                                                             value: nil,
                                                             permissions: [.readable, .writeable])
        
        let transferImageCharacteristic = CBMutableCharacteristic(type: TransferService.imageCharacteristicUUID,
                                                             properties: [.indicate, .writeWithoutResponse, .read],
                                                             value: nil,
                                                             permissions: [.readable, .writeable])
        
        // Create a service from the characteristic.
        let transferService = CBMutableService(type: TransferService.serviceUUID, primary: true)
        
        // Add the characteristic to the service.
        transferService.characteristics = [transferTextCharacteristic, transferImageCharacteristic]
        
        // And add it to the peripheral manager.
        peripheralManager.add(transferService)
        
        // Save the characteristic for later.
        self.transferTextCharacteristic = transferTextCharacteristic
        self.transferImageCharacteristic = transferImageCharacteristic
        
        //test
        startAdvertising()
    }
    
    private func startAdvertising() {
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TransferService.serviceUUID],
                                               CBAdvertisementDataLocalNameKey: TransferService.peripheralName])
    }
    
    private func stopAdvertising() {
        // 우리가 표시되지 않는 동안 광고를 계속하지 마십시오.
        peripheralManager.stopAdvertising()
    }
}

// MARK: Helper
extension PeripheralViewController {
    private func sendData() {
        guard dataToSend.count > 0 else {
            log.info("data to send isn't")
            return
        }

        var imageToSend = Data()
        var textToSend = Data()
        dataToSend.forEach { data in
            if case .image(let data) = data {
                imageToSend.append(data)
            } else if case .text(let data) = data {
                textToSend.append(data)
            } else if case .binary(_) = data {
                log.warning("binary???????????")
            }
        }
        
        if imageToSend.count > 0, transferImageCharacteristic != nil {
            //operation
            let operation = BluetoothDataOperation.createInstance(manager: peripheralManager,
                                                                  central: connectedCentral,
                                                                  characteristic: transferImageCharacteristic!)
            
            operation.dataToSend = imageToSend
            
            operationQueue.addOperation(operation)
            
            imageToSend.removeAll(keepingCapacity: false)
        }
        
        if textToSend.count > 0, transferTextCharacteristic != nil {
            //operation
            let operation = BluetoothDataOperation.createInstance(manager: peripheralManager,
                                                                  central: connectedCentral,
                                                                  characteristic: transferTextCharacteristic!)
            
            operation.dataToSend = textToSend
            
            operationQueue.addOperation(operation)
            
            textToSend.removeAll(keepingCapacity: false)
        }
        
        if imageToSend.count == 0 && textToSend.count == 0 {
            dataToSend.removeAll(keepingCapacity: false)
        }
    }
}

extension PeripheralViewController: CBPeripheralManagerDelegate {
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
        
        // Get the data
        if let data = textView.text.data(using: .utf8) {
            dataToSend.append(.text(data))
        }

        // save central
        connectedCentral = central
        
        sendData()
    }
    
    /*
     *  central에서 구독을 취소할 때 인식.
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        log.verbose("Central unsubscribed from characteristic")
        connectedCentral = nil
    }
    
    /*
     *  이 콜백은 PeripheralManager가 다음 데이터 청크를 보낼 준비가 되었을 때 발생합니다.
     *  이는 패킷이 전송된 순서대로 도착하도록 보장하기 위한 것입니다.
     */
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Start sending again
        sendData()
    }
    
    /*
     * 이 콜백은 PeripheralManager가 특성에 대한 쓰기를 수신했을 때 발생합니다.
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {

        for aRequest in requests {
            guard let requestValue = aRequest.value else {
                continue
            }
            
            let stringFromData = String(data: requestValue, encoding: .utf8)
            log.verbose("Received write request of \(requestValue.count) bytes: \(String(describing: stringFromData))")
            if stringFromData == "EOM" {
                log.verbose("Receive EOM")
                
                self.set(image: UIImage(data: dataToReceive))
                dataToReceive.removeAll(keepingCapacity: false)
                
            } else {
//                self.textView.text = stringFromData
                dataToReceive.append(requestValue)
            }
        }
    }
    
}

extension PeripheralViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        let rightButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard))
        navigationItem.rightBarButtonItem = rightButton
        
        stopAdvertising()
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        startAdvertising()
    }
    
    @objc
    func dismissKeyboard() {
        textView.resignFirstResponder()
        navigationItem.rightBarButtonItem = nil
    }
}

extension PeripheralViewController: RxMediaPickerDelegate {
    func present(picker: UIImagePickerController) {
        present(picker, animated: true)
    }
    
    func dismiss(picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

extension PeripheralViewController {
    func set(image: UIImage?) {
        self.imageView.image = image
    }
    
    func removeImage() {
        self.selectImageButton.isSelected = false
        self.imageView.image = nil
    }
    
    func selectImage() {
        picker.selectImage().subscribe(onNext: { (image, editedImage) in
            self.imageView.image = editedImage != nil ? editedImage : image
            self.selectImageButton.isSelected = true
            
            //TODO: it needs to send image data after change bytes to periphercal connected.
            if let data = self.imageView.image?.jpegData(compressionQuality: 0.7) {
                self.dataToSend.append(.image(data))
                
                self.sendData()
            }
        }).disposed(by: disposeBag)
    }
}


class BluetoothDataOperation: Operation {
    private var peripheralManager: CBPeripheralManager!
    private weak var connectedCentral: CBCentral?
    private var transferCharacteristic: CBMutableCharacteristic!
    
    private var sendDataIndex: Int = 0
    var dataToSend = Data()
    
    var sendingEOM = false
    
    static func createInstance(manager: CBPeripheralManager, central: CBCentral?, characteristic: CBMutableCharacteristic) -> BluetoothDataOperation {
        let operation = BluetoothDataOperation()
        operation.peripheralManager = manager
        operation.transferCharacteristic = characteristic
        operation.connectedCentral = central
        return operation
    }
    
    override func main() {
        guard let peripheralManager = peripheralManager else {
            log.error("operation: \(self) - peripheralManager is nil")
            return
        }
        
        // 먼저 EOM을 보낼 예정인지 확인하세요.
        if sendingEOM {
            // 보낸다.
            let didSend = peripheralManager.updateValue("EOM".data(using: .utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
            // 보냈나?
            if didSend {
                // 그랬으므로 전송됨으로 표시하세요.
                sendingEOM = false
                log.verbose("Sent: EOM")
            }
            // 전송되지 않았으므로 종료하고 PeripheralManagerIsReadyToUpdateSubscribers가 sendData를 다시 호출할 때까지 기다립니다.
            return
        }
        
        // EOM을 보내는 것이 아니므로 데이터를 보내는 중.
        // 보낼게 남았나?
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
            
            // 작동하지 않으면 중단하고 콜백을 기다립니다.
            if !didSend {
                log.info("If it didn't work, drop out and wait for the callback")
                return
            }
            
            let stringFromData = String(data: chunk, encoding: .utf8)
            log.verbose("Sent \(chunk.count) bytes: \(String(describing: stringFromData))")
            
            // It did send, so update our index
            sendDataIndex += amountToSend
            // Was it the last one?
            if sendDataIndex >= dataToSend.count {
                // It was - send an EOM
                
                // Set this so if the send fails, we'll send it next time
                sendingEOM = true
                
                //Send it
                let eomSent = peripheralManager.updateValue("EOM".data(using: .utf8)!,
                                                            for: transferCharacteristic, 
                                                            onSubscribedCentrals: nil)
                
                if eomSent {
                    // It sent; we're all done
                    sendingEOM = false
                    log.verbose("Sent: EOM")
                    
                    sendDataIndex = 0
                    dataToSend.removeAll(keepingCapacity: false)
                }
                return
            }
        }
    }
}
