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

struct DayTree {
    var count: Int = 0
    var members: [JPEGInfo] = []
}

enum LockType {
    case Read
    case Write
}

struct MonthTree {
    var count: Int = 0
    var members: [JPEGInfo] = []
    var days: Dictionary<Int,DayTree> = [:]
}

struct YearTree {
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
    var filters: [PhotoFilter] = []
    var allItems: [JPEGInfo] = []
    var yearTree: Dictionary<Int, YearTree> = [:]
    var pendingAdditions: [JPEGInfo] = []
    var countAtLastReload = 0
    var filtersChanged = true
    var _filteredItems: [JPEGInfo] = []
    var substores: [PhotoStore] = []
    var roundRobin = 0
    var queue: DispatchQueue?
    var filteredItems: [JPEGInfo] {
        checkAndRebuildFilteredItems()
        return _filteredItems
    }
    var countFilteredItems: Int {
        let c = filteredItems.count
        return c
    }
    var clusterstorelock = pthread_rwlock_t()
    var quiescent = true

    init() {
        pthread_rwlock_init(&clusterstorelock, nil)
    }
    
    func nextSubstore() -> PhotoStore {
        if substores.count == 0 {
            for var i in 1...8 {
                let store = PhotoStore()
                store.queue = DispatchQueue(label: "Substore \(i)")
                substores.append(store)
            }
        }
        let q = substores[roundRobin]
        roundRobin = (roundRobin + 1) % substores.count
        return q
    }
    
    public static var shared = PhotoStore()

    func addDirectory(_ url: URL,periodicUpdate:@escaping ()->Void) {
        if PhotoStore.shared.queue == nil {
            PhotoStore.shared.queue = DispatchQueue(label: "Main Database")
        }
        self.quiescent = false
        print("Sending animation notification")
        NotificationCenter.default.post(name: Notification.Name.ActivityOn, object: nil)
        let sourcesindex = IndexPath(index: 1) // XXX
        let sources = treeController!.arrangedObjects.descendant(at: sourcesindex)?.representedObject as! BaseNode
        let thissourceindex = sourcesindex.appending(IndexPath(index: sources.children.count))
        let node = ChildNode()
        node.nodeTitle = url.lastPathComponent
        node.count = 0
        DispatchQueue.main.async {
            self.treeController!.insert(node, atArrangedObjectIndexPath: thissourceindex)
            self.treeController!.rearrangeObjects()
        }

        let fileManager = FileManager.default
        countAtLastReload = allItems.count
        let enumerator:FileManager.DirectoryEnumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.typeIdentifierKey])!
        
        let dg = DispatchGroup()
        while let f = enumerator.nextObject() as? URL {
            var store = nextSubstore()
            dg.enter()
            store.queue!.async {
                store.addFileToList(file: f, sourceNode: node)
                dg.leave()
            }
        }
        print("Waiting for dispatch group!")

        dg.wait()
        print("All done!")
        for store in substores {
            store.syncWithShared(node)
        }
        NotificationCenter.default.post(name: NSNotification.Name.MorePhotosHaveArrived, object: nil)
        NotificationCenter.default.post(name: Notification.Name.SyncYearTree, object: nil)
        NotificationCenter.default.post(name: Notification.Name.ActivityOff, object: nil)
    }
    
    func addFileToList(file f: URL, sourceNode: BaseNode) {
        var type: String?
        do {
            type = try f.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier
        } catch {
            return
        }
        if type == nil || type! != "public.jpeg" { return }
        
        
        let item = JPEGInfo(path: f, properties: nil)
        
        self.allItems.append(item)
//        print("I am \(self.queue!.label) and I now have \(allItems.count) items")
        
        // Process the EXIF
        if let imageSource = CGImageSourceCreateWithURL(item.path as CFURL, nil) {
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as Dictionary?
            item.properties = imageProperties
            // Parse date
            _ = item.isodate
            _ = item.location
        }
        
        // Finish off
        fileInYearTree(item)
        processLocation(item)

        if allItems.count > 400 {
            syncWithShared(sourceNode)
            NotificationCenter.default.post(name: NSNotification.Name.MorePhotosHaveArrived, object: nil)
            NotificationCenter.default.post(name: Notification.Name.SyncYearTree, object: nil)
        }
    }
    
    func syncWithShared(_ sourceNode: BaseNode) {
        var myItems = allItems
        allItems = []
        print("Calling sync from queue \(queue!.label)")
        PhotoStore.shared.queue!.sync(flags: .barrier) {
            print("Entering barrier section for queue \(self.queue!.label)")
            PhotoStore.shared.allItems.append(contentsOf: myItems)
            PhotoStore.shared.filtersChanged = true
            // Add contents of year tree!
            // XXX This is dumb
            for var i in myItems {
                PhotoStore.shared.fileInYearTree(i)
            }
            sourceNode.count = sourceNode.count + myItems.count
            // Run periodic updates
            print("Leaving barrier section")
        }
    }
    
    func addFilter(_ f: PhotoFilter) {
        self.filtersChanged = true
        self.filters.append(f)
    }
    
    func removeFilter(withTag: String) {
        self.filtersChanged = true
        self.filters = self.filters.filter { $0.tag != withTag }
    }
    
    func getYearTree() -> Dictionary<Int, YearTree> {
        return queue!.sync {
            return self.yearTree
        }
    }
    
    func rebuildYearTree() { // Should be barriered
        self.yearTree = [:]
        for f in filteredItems {
            self.fileInYearTree(f)
        }
        NotificationCenter.default.post(name: Notification.Name.SyncYearTree, object: nil)
    }
    
    func fileInYearTree(_ item: JPEGInfo) {
        guard let date = item.isodate else { return }
        let year = Calendar.current.component(.year, from: date)
        let month = Calendar.current.component(.month, from: date)

        if yearTree[year] == nil {
            yearTree[year] = YearTree()
        }
        let c = yearTree[year]!.count
        yearTree[year]!.count = c + 1
        yearTree[year]!.members.append(item)
        if (yearTree[year]!.months[month] == nil) {
            yearTree[year]!.months[month] = MonthTree()
        }
        let cm = yearTree[year]!.months[month]!.count
        yearTree[year]!.months[month]!.count = cm + 1
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
    
    func reroundCoordinates(_ mapscale: Double) {
        let startTime = CFAbsoluteTimeGetCurrent()
        pthread_rwlock_wrlock(&(self.clusterstorelock))
        clusterPrecision = mapscale
        clusterStore.removeAll()
        let divand = clusterPrecision / 2.0
//        print("Rounding to \(divand)")

        for i in filteredItems {
            self.processLocation(i)
        }
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
//        print("Rebuilt \(clusterStore.count) annots from \(self.countFilteredItems()) in \(timeElapsed)s.")
        pthread_rwlock_unlock(&(self.clusterstorelock))
    }
    
    func precacheThumbnails(_ item: JPEGInfo) {
        let transformer = SDImageResizingTransformer(size: CGSize(width: 200, height: 200), scaleMode: .aspectFit)
        
        SDWebImageManager.shared.loadImage(with: item.path, options: [], context: [.imageTransformer: transformer], progress: nil, completed:{
            
                (image, data, error, cache, finished, url) in
                
            })
    }
    
    func checkAndRebuildFilteredItems() {
        queue!.sync(flags: .barrier) {
            if filtersChanged {
                let startTime = CFAbsoluteTimeGetCurrent()
                defer { print("Filtered items in \(CFAbsoluteTimeGetCurrent()-startTime)s") }
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
                filtersChanged = false
                _filteredItems = items
            }
        }
    }
}

