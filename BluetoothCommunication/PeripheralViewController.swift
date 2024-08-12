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
    
    @IBOutlet weak var projectCodeTextField: UITextField!
    @IBOutlet weak var dongCodeTextField: UITextField!
    @IBOutlet weak var floorCodeTextField: UITextField!
    
    @IBOutlet weak var connectionStatusLabel: UILabel!
    
    @IBOutlet weak var serviceInfoLabel: UILabel!
    @IBOutlet weak var characteristicInfoLabel: UILabel!
    @IBOutlet weak var descriptorInfoLabel: UILabel!
    
    @IBOutlet weak var receivedDataLabel: UILabel!
    
    
    @IBOutlet weak var test1Button: UIButton!
    @IBOutlet weak var test2Button: UIButton!
    @IBOutlet weak var test3Button: UIButton!
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        projectCodeTextField.text = "19SC"  //19ZS
        dongCodeTextField.text = "A0001"    //A0026
        floorCodeTextField.text = "A0206"   //A0210

        bindUI()
        bindData()
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
    }
    
    private func bindData() {
        viewModel.status.subscribe(onNext: { state in
            self.connectionStatusLabel.text = String(describing: state)
        }).disposed(by: disposeBag)
        
        viewModel.outputs.receiveString.subscribe(onNext: { string in
            self.receivedDataLabel.text = string
        }).disposed(by: disposeBag)
    }
    
    private func bindUI() {
        test1Button.rx.tap.throttle(.seconds(1), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                guard let `self` = self else { return }
                
                guard let pjtCd = self.projectCodeTextField.text,
                      let dongCd = self.dongCodeTextField.text,
                      let floorCd = self.floorCodeTextField.text else {
                    return
                }
                
                self.viewModel.send_spt001(pjtCd: pjtCd, dongCd: dongCd, floorCd: floorCd)
            }).disposed(by: disposeBag)
        
        test2Button.rx.tap.throttle(.seconds(1), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.viewModel.send_spt003()
            }).disposed(by: disposeBag)
        
        test3Button.rx.tap.throttle(.seconds(1), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.viewModel.send_spt006()
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
}

