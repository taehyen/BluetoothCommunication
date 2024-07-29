//
//  BluetoothCommunicationTests.swift
//  BluetoothCommunicationTests
//
//  Created by 3i-A1-2022-033 on 2/26/24.
//

import XCTest
@testable import BluetoothCommunication

final class BluetoothCommunicationTests: XCTestCase {
    
    let peripheralViewModel = PeripheralViewModel()

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        peripheralViewModel.start()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testSend001() throws {
        peripheralViewModel.spt001()
    }
    
    func testSend003() throws {
        peripheralViewModel.spt003()
    }

    func testSend006() throws {
        peripheralViewModel.spt006()
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
