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
    
    let viewModel = CentralViewModel() //TODO: 바깥으로 빼야 함.
    
    @IBOutlet var textView: UITextView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var selectImageButton: UIButton!
    
    lazy var picker: RxMediaPicker = {
        RxMediaPicker(delegate: self)
    }()

    override func viewDidLoad() {
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
        super.viewWillDisappear(animated)
    }
    
    private func bind() {
        viewModel.connected.subscribe(onNext: { state in
            // TODO: 그런데, 연결상태를 내부에서 구현해야 함.
        }).disposed(by: disposeBag)
        
        viewModel.receivedData.subscribe(onNext: { data in
            // TODO: 데이터를 이어받던게 완료되면 들어온다. 따라서, 프로그래스 형식을 구현하려면 여기서는 안됨.
            self.imageView.image = UIImage(data: data)
        }).disposed(by: disposeBag)
        
        viewModel.error.subscribe(onNext: { error in
            //TODO: 메시지 띄우기
        }).disposed(by: disposeBag)
    }
}

extension CentralViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        let rightButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard))
        navigationItem.rightBarButtonItem = rightButton
    }
    
    func textViewDidChange(_ textView: UITextView) {
        removeImage()
        
//        viewModel.dataToSend = textView.text.data(using: .utf8)!
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        //viewModel.writeData()
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
                self.viewModel.send(data: data)
            }
        }).disposed(by: disposeBag)
    }
}
