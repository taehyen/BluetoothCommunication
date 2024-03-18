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
        
        selectImageButton.rx.tap.throttle(.seconds(1), scheduler: MainScheduler.instance).subscribe(onNext: { _ in
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
    
    var transferCharacteristic: CBMutableCharacteristic?
    var connectedCentral: CBCentral?
    
    var dataToSend = Data()
    var dataToReceive = Data()
    
    var sendDataIndex: Int = 0
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
        
        // Build our service.
        
        // Start with the CBMutableCharacteristic.
        let transferCharacteristic = CBMutableCharacteristic(type: TransferService.characteristicUUID,
                                                             properties: [.indicate, .write, .read],
                                                             value: nil,
                                                             permissions: [.readable, .writeable])
        
        // Create a service from the characteristic.
        let transferService = CBMutableService(type: TransferService.serviceUUID, primary: true)
        
        // Add the characteristic to the service.
        transferService.characteristics = [transferCharacteristic]
        
        // And add it to the peripheral manager.
        peripheralManager.add(transferService)
        
        // Save the characteristic for later.
        self.transferCharacteristic = transferCharacteristic
        
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
    /*
     *  Sends the next amount of data to the connected central
     */
    static var sendingEOM = false
    
    private func sendData() {
        
        guard let transferCharacteristic = transferCharacteristic else {
            return
        }
        
        // First up, check if we're meant to be sending an EOM
        if PeripheralViewController.sendingEOM {
            // send it
            let didSend = peripheralManager.updateValue("EOM".data(using: .utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
            // Did it send?
            if didSend {
                // It did, so mark it as sent
                PeripheralViewController.sendingEOM = false
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
            
            let stringFromData = String(data: chunk, encoding: .utf8)
            log.verbose("Sent \(chunk.count) bytes: \(String(describing: stringFromData))")
            
            // It did send, so update our index
            sendDataIndex += amountToSend
            // Was it the last one?
            if sendDataIndex >= dataToSend.count {
                // It was - send an EOM
                
                // Set this so if the send fails, we'll send it next time
                PeripheralViewController.sendingEOM = true
                
                //Send it
                let eomSent = peripheralManager.updateValue("EOM".data(using: .utf8)!,
                                                            for: transferCharacteristic, onSubscribedCentrals: nil)
                
                if eomSent {
                    // It sent; we're all done
                    PeripheralViewController.sendingEOM = false
                    log.verbose("Sent: EOM")
                    
                    removeImage()
                    
                    sendDataIndex = 0
                    dataToSend.removeAll(keepingCapacity: false)
                }
                return
            }
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
//        dataToSend = textView.text.data(using: .utf8)!

        // save central
        connectedCentral = central
        
        // Start sending if it has some data to send.
        if dataToSend.count > 0 {
            // Reset the index
            sendDataIndex = 0
            
            sendData()
        }
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
                self.dataToSend = data
                
                self.sendData()
            }
        }).disposed(by: disposeBag)
    }
}
