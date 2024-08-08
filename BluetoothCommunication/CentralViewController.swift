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
import SnapKit

class CentralViewController: UIViewController {
    private let disposeBag = DisposeBag()
    
    let viewModel = CentralViewModel()
    
    @IBOutlet weak var connectionStatusLabel: UILabel!
    @IBOutlet weak var serviceStatusLabel: UILabel!
    @IBOutlet weak var characteristicStatusLabel: UILabel!
    @IBOutlet weak var desciptorStatusLabel: UILabel!
    @IBOutlet weak var receivedDataLabel: UILabel!
    @IBOutlet weak var receiveDataImageView: UIImageView!
    
    //TEST - echo: 0x24, 0xBF, 0x01, 0x01, 0x3D, 0x05 (body length), body data
    
    @IBOutlet weak var test1Button: UIButton!
    @IBOutlet weak var test2Button: UIButton!
    @IBOutlet weak var test3Button: UIButton!
    @IBOutlet weak var test4Button: UIButton!
    @IBOutlet weak var test5Button: UIButton!
    @IBOutlet weak var test6Button: UIButton!
    
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
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        self.view.makeToast("Begin Central Mode")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    private func bindData() {
        viewModel.initialInfo.subscribe(onNext: { info in
            log.verbose("UI - info: \(info)")
            self.receivedDataLabel.text = "\(info)"
        }, onError: { error in
            log.error(error.localizedDescription)
        }, onCompleted: {
            log.verbose("initialInfo onCompleted")
        }, onDisposed: {
            log.verbose("initialInfo onDisposed")
        }).disposed(by: disposeBag)
        
        viewModel.slamBySpot.subscribe(onNext: { slam in
            log.verbose("UI - slam: \(slam)")
            self.receivedDataLabel.text = "\(slam)"
        }, onError: { error in
            log.error(error.localizedDescription)
        }, onCompleted: {
            log.verbose("slamBySpot onCompleted")
        }, onDisposed: {
            log.verbose("slamBySpot onDisposed")
        }).disposed(by: disposeBag)
        
        viewModel.endCapture.subscribe(onNext: { result in
            
        }, onError: { error in
            log.error(error.localizedDescription)
        }, onCompleted: {
            log.verbose("endCapture onCompleted")
        }, onDisposed: {
            log.verbose("endCapture onDisposed")
        }).disposed(by: disposeBag)
        
        viewModel.connected.subscribe(onNext: { isConnected in
            self.connectionStatusLabel.text = String(describing: isConnected ? "연결됨" : "끊어짐")
        }, onError: { error in
            log.error(error.localizedDescription)
        }, onCompleted: {
            log.verbose("endCapture onCompleted")
        }, onDisposed: {
            log.verbose("endCapture onDisposed")
        }).disposed(by: disposeBag)
    }
    
    private func bindUI() {
        test3Button.rx.tap.throttle(.milliseconds(300), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.viewModel.inputs.spt002()
            }).disposed(by: disposeBag)
        
        test4Button.rx.tap.throttle(.milliseconds(300), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.viewModel.inputs.spt004()
            }).disposed(by: disposeBag)
        
        test5Button.rx.tap.throttle(.milliseconds(300), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.viewModel.inputs.spt005()
            }).disposed(by: disposeBag)
        
        test6Button.rx.tap.throttle(.milliseconds(300), latest: false, scheduler: MainScheduler.instance)
            .subscribe(onNext: { _ in
                self.viewModel.inputs.spt007()
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
}
