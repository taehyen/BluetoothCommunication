//
//  CoreDataManager.swift
//  BluetoothCommunication
//
//  Created by 3i-A1-2022-033 on 3/4/24.
//

import Foundation
import CoreData

class CoreDataManager {
    static let shared: CoreDataManager = CoreDataManager()
    
    // MARK: - CoreData
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "SpotData") // 여기는 파일명
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error {
                fatalError("Unresolved error, \((error as NSError).userInfo)")
            }
        })
        return container
    }()
    
    let modelName: String = "SpotData"
    
    func get<T> (ascending: Bool = false) -> [T] {
        var models: [T] = [T]()
        
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: modelName)

        do {
            if let fetchResult: [T] = try context.fetch(fetchRequest) as? [T] {
                models = fetchResult
            }
        } catch let error as NSError {
            print("Could not fetch🥺: \(error), \(error.userInfo)")
        }
        
        return models
    }
    
    func saveSpotData(data: Data, onSuccess: @escaping ((Bool) -> Void)) {
        let context = persistentContainer.viewContext
        
        if let entity = NSEntityDescription.entity(forEntityName: modelName, in: context) {
            
            if let spotData: SpotData = NSManagedObject(entity: entity, insertInto: context) as? SpotData {
                spotData.data = data
                
                contextSave { success in
                    onSuccess(success)
                }
            }
        }
    }
    
    func deleteSpotData(id: Int64, onSuccess: @escaping ((Bool) -> Void)) {
        let context = persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = filteredRequest(id: id)
        
        do {
            if let results: [SpotData] = try context.fetch(fetchRequest) as? [SpotData] {
                if results.count != 0 {
                    context.delete(results[0])
                }
            }
        } catch let error as NSError {
            print("Could not fatch🥺: \(error), \(error.userInfo)")
            onSuccess(false)
        }
        
        contextSave { success in
            onSuccess(success)
        }
    }
}

extension CoreDataManager {
    fileprivate func filteredRequest(id: Int64) -> NSFetchRequest<NSFetchRequestResult> {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: modelName)
        fetchRequest.predicate = NSPredicate(format: "id = %@", NSNumber(value: id))
        return fetchRequest
    }
    
    fileprivate func contextSave(onSuccess: ((Bool) -> Void)) {
        let context = persistentContainer.viewContext
        do {
            try context.save()
            onSuccess(true)
        } catch let error as NSError {
            print("Could not save🥶: \(error), \(error.userInfo)")
            onSuccess(false)
        }
    }
}
