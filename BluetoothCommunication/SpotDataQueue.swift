//
//  SpotDataQueue.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 3/4/24.
//

import Foundation
import CoreData

class SpotDataQueue {
    private var dataArray: [SpotData] = []
    
    func attach(spotData: SpotData) {
        //TODO: 중복체크해야하는지
        dataArray.append(spotData)
        try? spotData.managedObjectContext?.save()
    }
    
    func dispatch() -> SpotData? {
        dataArray.removeFirst()
    }
}

//코어데이터에 저장해야 함.
extension SpotDataQueue {
    
}
