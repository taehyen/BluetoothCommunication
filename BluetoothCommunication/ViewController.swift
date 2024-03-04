//
//  ViewController.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 2/26/24.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func onClickForCentralMode(_ sender: Any) {
        let storyboard = UIStoryboard(name: "CentralViewController", bundle: nil)
        guard let viewController = storyboard.instantiateViewController(withIdentifier: "CentralViewController") as? CentralViewController else { return }
        self.navigationController?.pushViewController(viewController, animated: true)
    }
    
    @IBAction func onClickForPeripheralMode(_ sender: Any) {
        let storyboard = UIStoryboard(name: "PeripheralViewController", bundle: nil)
        guard let viewController = storyboard.instantiateViewController(withIdentifier: "PeripheralViewController") as? PeripheralViewController else { return }
        self.navigationController?.pushViewController(viewController, animated: true)
    }
}

