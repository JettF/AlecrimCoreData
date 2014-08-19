//
//  CoreDataTable.swift
//  AlecrimCoreData
//
//  Created by Vanderlei Martinelli on 2014-06-25.
//  Copyright (c) 2014 Alecrim. All rights reserved.
//

import Foundation
import CoreData

public final class CoreDataTable<T: NSManagedObject> {
    
    internal let context: NSManagedObjectContext
    internal let defaultFetchBatchSize = 20
    internal lazy var underlyingFetchRequest = NSFetchRequest(entityName: T.entityName)

    public init(dataModel: CoreDataModel) {
        self.context = dataModel.context
    }
    
}

extension CoreDataTable {

    public func skip(count: Int) -> Self {
        self.underlyingFetchRequest.fetchOffset = count
        return self
    }
    
    public func take(count: Int) -> Self {
        self.underlyingFetchRequest.fetchLimit = count
        return self
    }

    public func sortBy(sortTerm: String, ascending: Bool = true) -> Self {
        let addedSortDescriptors = self.sortDescriptorsFromString(sortTerm, defaultAscendingValue: ascending)
        
        if var sortDescriptors = self.underlyingFetchRequest.sortDescriptors as? [NSSortDescriptor] {
            sortDescriptors += addedSortDescriptors
        }
        else {
            self.underlyingFetchRequest.sortDescriptors = addedSortDescriptors
        }
        
        return self
    }
    
    public func orderBy(attributeName: String) -> Self {
        return self.orderByAscending(attributeName)
    }

    public func orderByAscending(attributeName: String) -> Self {
        return self.sortBy(attributeName, ascending: true)
    }

    public func orderByDescending(attributeName: String) -> Self {
        return self.sortBy(attributeName, ascending: false)
    }

    public func filterBy(#predicate: NSPredicate) -> Self {
        if self.underlyingFetchRequest.predicate == nil {
            self.underlyingFetchRequest.predicate = predicate
        }
        else if let compoundPredicate = self.underlyingFetchRequest.predicate as? NSCompoundPredicate {
            var subpredicates = compoundPredicate.subpredicates as [NSPredicate]
            subpredicates.append(predicate)
            self.underlyingFetchRequest.predicate = NSCompoundPredicate.andPredicateWithSubpredicates(subpredicates)
        }
        else {
            let subpredicates = [ self.underlyingFetchRequest.predicate!, predicate ]
            self.underlyingFetchRequest.predicate = NSCompoundPredicate.andPredicateWithSubpredicates(subpredicates)
        }
    
        return self
    }
    
    public func filterBy(attribute attributeName: String, value: AnyObject?) -> Self {
        var predicate: NSPredicate
        if let v: AnyObject = value {
            predicate = NSPredicate(format: "%K == %@", argumentArray: [attributeName, v])
        }
        else {
            predicate = NSPredicate(format: "%K == nil", argumentArray: [attributeName])
        }
        
        return self.filterBy(predicate: predicate)
    }
    
    public func filterBy(#predicateFormat: String, argumentArray arguments: [AnyObject]!) -> Self {
        let predicate = NSPredicate(format: predicateFormat, argumentArray: arguments);
        return self.filterBy(predicate: predicate)
    }
    
    public func filterBy(#predicateFormat: String, arguments argList: CVaListPointer) -> Self {
        let predicate = NSPredicate(format: predicateFormat, arguments: argList)
        return self.filterBy(predicate: predicate)
    }
    
}

extension CoreDataTable {
    
    public func toFetchRequest() -> NSFetchRequest {
        return self.underlyingFetchRequest.copy() as NSFetchRequest
    }
    
}

extension CoreDataTable {

    public func toArray() -> [T] {
        return self.toArray(fetchRequest: self.toFetchRequest())
    }
    
    public func count() -> Int {
        return self.count(fetchRequest: self.toFetchRequest())
    }

    public func first() -> T? {
        let fetchRequest = self.toFetchRequest()
        fetchRequest.fetchLimit = 1
        
        let results = self.toArray(fetchRequest: fetchRequest)
        
        return (results.isEmpty ? nil : results[0])
    }
    
    public func any() -> Bool {
        let fetchRequest = self.toFetchRequest()
        fetchRequest.fetchLimit = 1
        
        let result = self.count(fetchRequest: fetchRequest) > 0
        
        return result
    }
    
}

extension CoreDataTable {
    
    public func createEntity() -> T {
        let entityDescription = NSEntityDescription.entityForName(T.entityName, inManagedObjectContext: self.context)
        let managedObject = T(entity: entityDescription, insertIntoManagedObjectContext: self.context)
        
        return managedObject
    }
    
    public func createOrGetFirstEntity(whereAttribute attributeName: String, isEqualTo value: AnyObject?) -> T {
        if let entity = self.filterBy(attribute: attributeName, value: value).first() {
            return entity
        }
        else {
            let entity = self.createEntity()
            entity.setValue(value, forKey: attributeName)
            
            return entity
        }
    }
    
    public func deleteEntity(managedObject: T) -> (Bool, NSError?) {
        var retrieveExistingObjectError: NSError? = nil
        if let managedObjectInContext = self.context.existingObjectWithID(managedObject.objectID, error: &retrieveExistingObjectError) {
            self.context.deleteObject(managedObjectInContext)
            return (managedObject.deleted || managedObject.managedObjectContext == nil, nil)
        }
        else {
            return (false, retrieveExistingObjectError)
        }
    }
    
    public func refreshEntity(managedObject: T) {
        managedObject.managedObjectContext.refreshObject(managedObject, mergeChanges: true)
    }
    
}

extension CoreDataTable {
    
    public func delete() {
        let fetchRequest = self.toFetchRequest()
        fetchRequest.returnsObjectsAsFaults = true
        fetchRequest.includesPropertyValues = false
        
        let entities = self.toArray(fetchRequest: fetchRequest)
        for entity in entities {
            self.deleteEntity(entity)
        }
    }
    
}

extension CoreDataTable: SequenceType {
    
    public typealias GeneratorType = IndexingGenerator<[T]>
    
    public func generate() -> GeneratorType {
        return self.toArray().generate()
    }
    
}

extension CoreDataTable {
    
    private func sortDescriptorsFromString(string: String, defaultAscendingValue: Bool) -> [NSSortDescriptor] {
        var sortDescriptors = [NSSortDescriptor]()
        
        let sortKeys = string.componentsSeparatedByString(",") as [NSString]
        for sortKey in sortKeys {
            var effectiveSortKey = sortKey
            var effectiveAscending = defaultAscendingValue
            var effectiveOptionalParameter: NSString? = nil
            
            let sortComponents = sortKey.componentsSeparatedByString(":") as [NSString]
            if sortComponents.count > 1 {
                effectiveSortKey = sortComponents[0]
                effectiveAscending = sortComponents[1].boolValue
                
                if (sortComponents.count > 2) {
                    effectiveOptionalParameter = sortComponents[2]
                }
            }
            
            if effectiveOptionalParameter != nil && effectiveOptionalParameter!.rangeOfString("cd").location != NSNotFound {
                sortDescriptors.append(NSSortDescriptor(key: effectiveSortKey, ascending: effectiveAscending, selector: Selector("localizedCaseInsensitiveCompare:")))
            }
            else {
                sortDescriptors.append(NSSortDescriptor(key: effectiveSortKey, ascending: effectiveAscending))
            }
        }
        
        return sortDescriptors
    }
    
}

extension CoreDataTable {

    private func toArray(#fetchRequest: NSFetchRequest) -> [T] {
        fetchRequest.fetchBatchSize = self.defaultFetchBatchSize
        
        var results = [T]()
        
        self.context.performBlockAndWait { [weak self] in
            if let s = self {
                var error: NSError? = nil
                if let objects = s.context.executeFetchRequest(fetchRequest, error: &error) as? [T] {
                    results += objects
                }
            }
        }
        
        return results
    }

    private func count(#fetchRequest: NSFetchRequest) -> Int {
        var c = 0
        
        self.context.performBlockAndWait { [weak self] in
            if let s = self {
                var error: NSError? = nil
                c += s.context.countForFetchRequest(fetchRequest, error: &error)
            }
        }
        
        return c
    }
    
}
