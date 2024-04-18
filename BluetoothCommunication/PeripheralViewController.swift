//
//  PeripheralViewController.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 2/26/24.
//

import UIKit
import CoreBluetooth
import RxSwift
import RxCocoa
import RxMediaPicker

class PeripheralViewController: UIViewController {
    let disposeBag = DisposeBag()
    
    let viewModel = PeripheralViewModel()
    
    lazy var picker: RxMediaPicker = {
        RxMediaPicker(delegate: self)
    }()
    
    @IBOutlet weak var connectionStatusLabel: UILabel!
    
    @IBOutlet weak var receivedDataLabel: UILabel!
    @IBOutlet weak var receiveDataImageView: UIImageView!
    
    @IBOutlet weak var test1Button: UIButton!
    @IBOutlet weak var test2Button: UIButton!
    
    @IBOutlet weak var test3Button: UIButton!
    @IBOutlet weak var test4Button: UIButton!
    @IBOutlet weak var test5Button: UIButton!
    

    override func viewDidLoad() {
        super.viewDidLoad()

        bindUI()
        bindData()
        
        viewModel.inputs.initPeripheral()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        viewModel.inputs.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        UIApplication.shared.isIdleTimerDisabled = false
        
        viewModel.inputs.stop()
        viewModel.inputs.finalPeripheral()
    }
    
    private func bindData() {
        viewModel.status.subscribe(onNext: { state in
            // TODO: 그런데, 연결상태를 내부에서 구현해야 함.
            self.connectionStatusLabel.text = String(describing: state)
        }).disposed(by: disposeBag)
        
        viewModel.receivedData.drive(onNext: { data in
            // TODO: 데이터를 이어받던게 완료되면 들어온다. 따라서, 프로그래스 형식을 구현하려면 여기서는 안됨.
            if case .image(let data) = data {
                
                let textContainImageSize = "image size: \(data.count) bytes"
                log.verbose("UI - receive \(textContainImageSize)")
                
                if let image = UIImage(data: data) {
                    let ratio: CGFloat = image.size.height / image.size.width
                    self.receiveDataImageView.image = UIImage(data: data)
                    let height = self.receiveDataImageView.frame.size.width * ratio
                    self.receiveDataImageView.snp.makeConstraints { make in
                        make.height.equalTo(height)
                    }
                    self.receiveDataImageView.frame.size.height = self.receiveDataImageView.frame.size.width * ratio
                    self.receiveDataImageView.sizeToFit()
                }
                
            } else if case .text(let data) = data {
                
                let text = data.hexEncodedString()
                log.verbose("UI - receive: \(text)")
                self.receivedDataLabel.text = text
                
            } else if case .binary(let packet) = data {
                let data = Data(bytes: packet.body, count: Int(packet.bodyLength))
                if let string = String(data: data, encoding: .utf8) {
                    self.receivedDataLabel.text = "received: \(string)"
                } else {
                    log.error("received data = \(data)")
                }
            }
            
        }).disposed(by: disposeBag)
    }
    
    private func bindUI() {
        test1Button.rx.tap.throttle(.milliseconds(300), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                if let data = "test string".data(using: .utf8) {
                    self.view.makeToast("send : test string")
                    self.viewModel.send(data: .text(data))
                }
            }).disposed(by: disposeBag)
        
        test2Button.rx.tap.throttle(.milliseconds(300), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.selectImage()
            }).disposed(by: disposeBag)
        
        test3Button.rx.tap.throttle(.milliseconds(300), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.viewModel.inputs.spt001()
            }).disposed(by: disposeBag)
        
        test4Button.rx.tap.throttle(.milliseconds(300), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.viewModel.inputs.spt003()
            }).disposed(by: disposeBag)
        
        test5Button.rx.tap.throttle(.milliseconds(300), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.viewModel.inputs.spt006()
            }).disposed(by: disposeBag)
    }
}

extension PeripheralViewController: RxMediaPickerDelegate {
    func present(picker: UIImagePickerController) {
        present(picker, animated: true)
    }
    
    func dismiss(picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func selectImage() {
        picker.selectImage().subscribe(onNext: { (image, editedImage) in
            guard let image = editedImage != nil ? editedImage : image else {
                log.error("all images is nil")
                return
            }
            
            if let data = image.jpegData(compressionQuality: 0.7) {
                self.viewModel.send(data: .image(data))
            }
        }).disposed(by: disposeBag)
    }
}

