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
    
    @IBOutlet var textView: UITextView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var selectImageButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        textView.delegate = self
        textView.text = ""
        
        selectImageButton.setTitle("Select Image", for: .normal)
        selectImageButton.setTitleColor(.blue, for: .normal)
        selectImageButton.setTitle("Unselect Image", for: .selected)
        selectImageButton.setTitleColor(.white, for: .selected)
        
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
        viewModel.outputs.receivedData.subscribe(onNext: { bluetoothData in
            let data = Data()
            if case .image(data) = bluetoothData {
                self.imageView.image = UIImage(data: data)
            } else if case .text(data) = bluetoothData {
                self.textView.text = String(data: data, encoding: .utf8)
            }
        }).disposed(by: disposeBag)
    }
    
    private func bindUI() {
        selectImageButton.rx.tap.throttle(.seconds(1), scheduler: MainScheduler.instance).subscribe(onNext: { _ in
            if self.selectImageButton.isSelected {
                self.removeImage()
            } else {
                self.selectImage()
            }
        }).disposed(by: disposeBag)
    }
}

extension PeripheralViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        let rightButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard))
        navigationItem.rightBarButtonItem = rightButton
        
//        viewModel.inputs.stop()
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        viewModel.inputs.send(data: .text(textView.text.data(using: .utf8)!))
        
//        viewModel.inputs.start()
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
            
            //it needs to send image data after change bytes to periphercal connected.
            if let data = self.imageView.image?.jpegData(compressionQuality: 0.7) {
                self.viewModel.inputs.send(data: .image(data))
            }
        }).disposed(by: disposeBag)
    }
}

