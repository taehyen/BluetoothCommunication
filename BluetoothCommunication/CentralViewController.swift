//
//  CentralViewController.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 2/26/24.
//

import UIKit
import RxSwift
import RxCocoa
import Toast
import RxMediaPicker

class CentralViewController: UIViewController {
    private let disposeBag = DisposeBag()
    
    let viewModel = CentralViewModel()
    
    @IBOutlet weak var connectionStatusLabel: UILabel!
    @IBOutlet weak var serviceStatusLabel: UILabel!
    @IBOutlet weak var characteristicStatusLabel: UILabel!
    @IBOutlet weak var desciptorStatusLabel: UILabel!
    @IBOutlet weak var receivedDataLabel: UILabel!
    
    //TEST - echo: 0x24, 0xBF, 0x01, 0x01, 0x3D, 0x05 (body length), body data
    
    @IBOutlet weak var test1Button: UIButton!
    @IBOutlet weak var test2Button: UIButton!
    
    lazy var picker: RxMediaPicker = {
        RxMediaPicker(delegate: self)
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        bindUI()
        bindData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        viewModel.inputs.initCentral()

        self.view.makeToast("Begin Central Mode")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        viewModel.inputs.finalCentral()
    }
    
    private func bindData() {
        viewModel.error.subscribe(onNext: { error in
            self.view.makeToast("error: \(error)")
        }).disposed(by: disposeBag)
        
        viewModel.connected.subscribe(onNext: { state in
            // TODO: 그런데, 연결상태를 내부에서 구현해야 함.
            self.connectionStatusLabel.text = String(describing: state)
        }).disposed(by: disposeBag)
        
        viewModel.receivedData.subscribe(onNext: { data in
            // TODO: 데이터를 이어받던게 완료되면 들어온다. 따라서, 프로그래스 형식을 구현하려면 여기서는 안됨.
            if case .image(let data) = data {
                
                let textContainImageSize = "image size: \(data.count) bytes"
                log.verbose("UI - receive \(textContainImageSize)")
                self.receivedDataLabel.text = textContainImageSize
                
            } else if case .text(let data) = data {
                
                let text = data.hexEncodedString()
                log.verbose("UI - receive: \(text)")
                self.receivedDataLabel.text = text
                
            }
            
        }).disposed(by: disposeBag)
        
        viewModel.serviceInfo.subscribe(onNext: { info in
            self.serviceStatusLabel.text = info
        }).disposed(by: disposeBag)
        
        viewModel.characteristicInfo.subscribe(onNext: { info in
            self.characteristicStatusLabel.text = info
        }).disposed(by: disposeBag)
        
        viewModel.descriptorInfo.subscribe(onNext: { info in
            self.desciptorStatusLabel.text = info
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
    }
}

extension CentralViewController: RxMediaPickerDelegate {
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

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }
    
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let hexDigits = options.contains(.upperCase) ? "0123456789ABCDEF" : "0123456789abcdef"
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            let utf8Digits = Array(hexDigits.utf8)
            return String(unsafeUninitializedCapacity: 2 * self.count) { (ptr) -> Int in
                var p = ptr.baseAddress!
                for byte in self {
                    p[0] = utf8Digits[Int(byte / 16)]
                    p[1] = utf8Digits[Int(byte % 16)]
                    p += 2
                }
                return 2 * self.count
            }
        } else {
            let utf16Digits = Array(hexDigits.utf16)
            var chars: [unichar] = []
            chars.reserveCapacity(2 * self.count)
            for byte in self {
                chars.append(utf16Digits[Int(byte / 16)])
                chars.append(utf16Digits[Int(byte % 16)])
            }
            return String(utf16CodeUnits: chars, count: chars.count)
        }
    }
}
