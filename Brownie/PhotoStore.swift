//
//  PhotoStore.swift
//  Brownie
//
//  Created by Simon Cozens on 08/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Foundation
import MapKit
import SDWebImage

class DayTree {
    var count: Int = 0
    var members: [JPEGInfo] = []
}

class MonthTree {
    var count: Int = 0
    var members: [JPEGInfo] = []
    var days: Dictionary<Int,DayTree> = [:]
}

class YearTree {
    var count: Int = 0
    var members: [JPEGInfo] = []
    var months: Dictionary<Int,MonthTree> = [:]
}

class PhotoFilter {
    var tag: String
    var filter: (JPEGInfo) -> Bool
    init(tag: String, filter: @escaping (JPEGInfo) -> Bool) {
        self.tag = tag
        self.filter = filter
    }
}

class PhotoStore {
    var annotations: [MKAnnotation] = []
    var treeController: NSTreeController? = nil
    var clusterStore: Dictionary<CLLocationCoordinate2D,PhotoCluster> = [:]
    var clusterPrecision :Double = -1.0
    var pendingOperations = PendingOperations()
    var filters: [PhotoFilter] = []
    var allItems: [JPEGInfo] = []
    var yearTree: Dictionary<Int, YearTree> = [:]
    var countAtLastReload = 0
    var filtersChanged = true
    var filteredItems: [JPEGInfo] {
        pthread_rwlock_rdlock(&databaselock)
        var items: [JPEGInfo] = []
        if filters.count == 0 {
            items = allItems
        } else {
            items = allItems.lazy.filter {
                for f in self.filters {
                    if !f.filter($0) { return false }
                }
                return true
            }
        }
        pthread_rwlock_unlock(&databaselock)
        return items
    }
    var countFilteredItems: Int {
//        pthread_rwlock_rdlock(&databaselock)
        let c = filteredItems.count
//        pthread_rwlock_unlock(&databaselock)
        return c
    }
    var databaselock = pthread_rwlock_t()
    var clusterstorelock = pthread_rwlock_t()
    var treelock = pthread_rwlock_t()
    var yeartreelock = pthread_rwlock_t()
    var quiescent = true

    init() {
        pthread_rwlock_init(&databaselock, nil)
        pthread_rwlock_init(&clusterstorelock, nil)
        pthread_rwlock_init(&treelock, nil)
        pthread_rwlock_init(&yeartreelock, nil)
    }
    
    public static var shared = PhotoStore()

    func addDirectory(_ url: URL,periodicUpdate:@escaping ()->Void) {
        self.quiescent = false
        let sourcesindex = IndexPath(index: 1) // XXX
        let sources = treeController!.arrangedObjects.descendant(at: sourcesindex)?.representedObject as! BaseNode
        print(sources.children.count)
        let thissourceindex = sourcesindex.appending(IndexPath(index: sources.children.count))
        let node = ChildNode()
        node.nodeTitle = url.lastPathComponent
        node.count = 0
        DispatchQueue.main.async {
            pthread_rwlock_wrlock(&self.treelock)
            self.treeController!.insert(node, atArrangedObjectIndexPath: thissourceindex)
            pthread_rwlock_unlock(&self.treelock)
        }

        let fileManager = FileManager.default
        countAtLastReload = allItems.count
        let enumerator:FileManager.DirectoryEnumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.typeIdentifierKey])!
        let completionOperation = BlockOperation {
            print("Running final item in exifQueue")
            periodicUpdate()
            self.quiescent = true
            NotificationCenter.default.post(name: Notification.Name.SyncYearTree, object: nil)
        }
        do {
            while let f = enumerator.nextObject() as? URL {
//                enumerator.skipDescendants()
                try self.addFileToList(file: f, periodicUpdate: periodicUpdate, sourceNode: node, completionOperation: completionOperation)
            }
        } catch {
            print(error.localizedDescription)
        }
        pendingOperations.additionQueue.addOperation(completionOperation)
    }
    
    func addFileToList(file f: URL, periodicUpdate: @escaping ()->Void, sourceNode: BaseNode, completionOperation: BlockOperation) throws {
        let type = try f.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier
        if type == nil || type! != "public.jpeg" { return }
        let item = JPEGInfo(path: f, properties: nil)
        let storer = AddToStore(item: item)
        let exif = ProcessEXIF(item: item)

        storer.completionBlock = {
            if storer.isCancelled { return }
            pthread_rwlock_rdlock(&(self.databaselock))
            let lastReload = self.countAtLastReload + 1000
            pthread_rwlock_unlock(&(self.databaselock))
            if self.semaphoredCountItems() > lastReload {
                print("Reloading")
                pthread_rwlock_wrlock(&(self.databaselock))
                self.countAtLastReload = self.allItems.count
                pthread_rwlock_unlock(&(self.databaselock))
                periodicUpdate()
                NotificationCenter.default.post(name: Notification.Name.SyncYearTree, object: nil)
                //
            }
            pthread_rwlock_wrlock(&(self.databaselock))
            DispatchQueue.main.async {
                sourceNode.count = sourceNode.count + 1
            }
            completionOperation.addDependency(exif)
            self.pendingOperations.exifQueue.addOperation(exif)
            pthread_rwlock_unlock(&(self.databaselock))
        }
        completionOperation.addDependency(storer)
        pendingOperations.additionQueue.addOperation(storer)
    }
    
    func addFilter(_ f: PhotoFilter) {
        self.filters.append(f)
    }
    
    func removeFilter(withTag: String) {
        self.filters = self.filters.filter { $0.tag != withTag }
    }
    
    func getYearTree() -> Dictionary<Int, YearTree> {
        pthread_rwlock_rdlock(&(self.yeartreelock))
        let yt = self.yearTree
        pthread_rwlock_unlock(&(self.yeartreelock))
        return yt
    }
    
    func rebuildYearTree() {
        pthread_rwlock_wrlock(&(self.yeartreelock))
        self.yearTree = [:]
        for f in filteredItems {
            self.fileInYearTree(f)
        }
        pthread_rwlock_unlock(&(self.yeartreelock))
        NotificationCenter.default.post(name: Notification.Name.SyncYearTree, object: nil)
    }
    
    func fileInYearTree(_ item: JPEGInfo) {
        guard let date = item.isodate else { return }
        let year = Calendar.current.component(.year, from: date)
        let month = Calendar.current.component(.month, from: date)

        pthread_rwlock_rdlock(&(self.yeartreelock))
        if yearTree[year] == nil {
            pthread_rwlock_unlock(&(self.yeartreelock))
            pthread_rwlock_wrlock(&(self.yeartreelock))
            yearTree[year] = YearTree()
        }
        pthread_rwlock_unlock(&(self.yeartreelock))
        pthread_rwlock_rdlock(&(self.yeartreelock))
        let c = yearTree[year]!.count
        pthread_rwlock_unlock(&(self.yeartreelock))
        pthread_rwlock_wrlock(&(self.yeartreelock))
        yearTree[year]!.count = c + 1
        yearTree[year]!.members.append(item)
        if (yearTree[year]!.months[month] == nil) {
            yearTree[year]!.months[month] = MonthTree()
        }
        pthread_rwlock_unlock(&(self.yeartreelock))
        pthread_rwlock_rdlock(&(self.yeartreelock))
        let cm = yearTree[year]!.months[month]!.count
        pthread_rwlock_unlock(&(self.yeartreelock))
        pthread_rwlock_wrlock(&(self.yeartreelock))
        yearTree[year]!.months[month]!.count = cm + 1
        pthread_rwlock_unlock(&(self.yeartreelock))
    }
    
    func processLocation(_ item: JPEGInfo) {
        guard let loc = item.location else { return }
        pthread_rwlock_wrlock(&(self.clusterstorelock))
        let locRounded = loc.rounded(clusterPrecision)
//        print("Making an annotation")
        var node = clusterStore[locRounded]
        if node == nil {
            clusterStore[locRounded] = PhotoCluster(title: "Hello", locationName: "X", items: [], coordinate: loc)
            node = clusterStore[locRounded]
            assert(clusterStore[locRounded] != nil)
        }
        node!.items.append(item)
        pthread_rwlock_unlock(&(self.clusterstorelock))
    }
    
    func semaphoredCountItems() -> Int {
        pthread_rwlock_rdlock(&(self.databaselock))
        let c = self.allItems.count
        pthread_rwlock_unlock(&(self.databaselock))
        return c
    }

    func semaphoredAddItem(_ item: JPEGInfo) {
        pthread_rwlock_wrlock(&(self.databaselock))
        self.allItems.append(item)
        pthread_rwlock_unlock(&(self.databaselock))
    }

    func reroundCoordinates(_ mapscale: Double) {
        let startTime = CFAbsoluteTimeGetCurrent()
        pthread_rwlock_wrlock(&(self.clusterstorelock))
        clusterPrecision = mapscale
        clusterStore.removeAll()
        pthread_rwlock_rdlock(&(self.databaselock))
        let divand = clusterPrecision / 2.0
        print("Rounding to \(divand)")

        for i in filteredItems {
            self.processLocation(i)
        }
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("Rebuilt \(clusterStore.count) annots from \(filteredItems.count) in \(timeElapsed)s.")
        pthread_rwlock_unlock(&(self.databaselock))
        pthread_rwlock_unlock(&(self.clusterstorelock))
    }
    
    func precacheThumbnails(_ item: JPEGInfo) {
        let transformer = SDImageResizingTransformer(size: CGSize(width: 200, height: 200), scaleMode: .aspectFit)
        
        SDWebImageManager.shared.loadImage(with: item.path, options: [], context: [.imageTransformer: transformer], progress: nil, completed:{
            
                (image, data, error, cache, finished, url) in
                
            })
    }
}

