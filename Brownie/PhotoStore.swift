//
//  PhotoStore.swift
//  Brownie
//
//  Created by Simon Cozens on 08/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Foundation
import MapKit
class PhotoStore {
    var regionRect = MKMapRect.null
    var annotations: [MKAnnotation] = []
    var treeController: NSTreeController? = nil
    var clusterStore: Dictionary<CLLocationCoordinate2D,PhotoCluster> = [:]
    var clusterPrecision :Double = -1.0
    var pendingOperations = PendingOperations()
    var allItems: [JPEGInfo] = []
    var countAtLastReload = 0
    var thumbnailStore: LRUCache<URL> = LRUCache(1000)
    var filteredItems: [JPEGInfo] {
        return allItems
    }
    var countFilteredItems: Int {
        pthread_rwlock_rdlock(&databaselock)
        let c = filteredItems.count
        pthread_rwlock_unlock(&databaselock)
        return c
    }
    var databaselock = pthread_rwlock_t()
    var clusterstorelock = pthread_rwlock_t()
    var regionrectlock = pthread_rwlock_t()
    var treelock = pthread_rwlock_t()

    init() {
        pthread_rwlock_init(&databaselock, nil)
        pthread_rwlock_init(&clusterstorelock, nil)
        pthread_rwlock_init(&regionrectlock, nil)
        pthread_rwlock_init(&treelock, nil)

    }
    
    
    public static var shared = PhotoStore()

    func addDirectory(_ url: URL,periodicUpdate:@escaping ()->Void) {
        let sourcesindex = IndexPath(index: 1) // XXX
        let sources = treeController!.arrangedObjects.descendant(at: sourcesindex)?.representedObject as! BaseNode
        print(sources.children.count)
        var thissourceindex = sourcesindex.appending(IndexPath(index: sources.children.count))
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
        do {
            while let f = enumerator.nextObject() as? URL {
//                enumerator.skipDescendants()
                try self.addFileToList(file: f, periodicUpdate: periodicUpdate, sourceNode: node)
            }
        } catch {
            print(error.localizedDescription)
        }
        print("All done!")
        self.pendingOperations.exifQueue.addOperation {
            print("Running final item in exifQueue")
            periodicUpdate()
        }
    }
    
    func addFileToList(file f: URL, periodicUpdate: @escaping ()->Void, sourceNode: BaseNode) throws {
        let type = try f.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier
        if type == nil || type! != "public.jpeg" { return }
        let item = JPEGInfo(path: f, properties: nil)
        let storer = AddToStore(item: item, store: self)
        let exif = ProcessEXIF(item: item, store: self)

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
            }
            pthread_rwlock_wrlock(&(self.treelock))
            sourceNode.count = sourceNode.count + 1
            self.pendingOperations.exifQueue.addOperation(exif)
            pthread_rwlock_unlock(&(self.treelock))

        }
        pendingOperations.additionQueue.addOperation(storer)
    }
    
    func nodeFor(year: Int) -> ChildNode {
        let datesindex = IndexPath(index: 0) // XXX
        pthread_rwlock_rdlock(&(self.treelock))
        let datesnode = treeController!.arrangedObjects.descendant(at: datesindex)?.representedObject as! BaseNode
        for n in datesnode.children {
            if n.nodeTitle == String(year) {
                pthread_rwlock_unlock(&(self.treelock))
                return n as! ChildNode
            }
        }
        pthread_rwlock_unlock(&(self.treelock))

        let node = ChildNode()
        node.nodeTitle = String(year)
        node.count = 0
        DispatchQueue.main.sync {
//            pthread_rwlock_wrlock(&(self.treelock))
            self.treeController!.insert(node, atArrangedObjectIndexPath: datesindex.appending(IndexPath(index: datesnode.children.count)))
//            pthread_rwlock_unlock(&(self.treelock))
        }

        return node
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

        let mp = MKMapPoint(loc)
        pthread_rwlock_rdlock(&(self.regionrectlock))
        let oldrr = regionRect
        pthread_rwlock_unlock(&(self.regionrectlock))
        if !oldrr.contains(mp) {
            let newRect = MKMapRect(origin: mp, size: MKMapSize(width:1, height: 1))
            pthread_rwlock_wrlock(&(self.regionrectlock))
            regionRect = regionRect.union(newRect)
            pthread_rwlock_unlock(&(self.regionrectlock))
        }
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
}

