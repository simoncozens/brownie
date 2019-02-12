//
//  Operations.swift
//  Brownie
//
//  Created by Simon Cozens on 07/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Foundation
import Cocoa

class PendingOperations {
    lazy var resizesInProgress: [URL: Operation] = [:]
    lazy var storeAdditionsInProgress: [JPEGInfo: Operation] = [:]
    lazy var additionQueue: OperationQueue = {
        var queue = OperationQueue()
//        queue.maxConcurrentOperationCount = 1
        queue.name = "Addition queue"
        return queue
    }()
    lazy var exifQueue: OperationQueue = {
        return additionQueue
//        var queue = OperationQueue()
//        queue.maxConcurrentOperationCount = 4
//        queue.name = "EXIF queue"
//        return queue
    }()
    lazy var thumbnailQueue: OperationQueue = {
        return additionQueue
//        var queue = OperationQueue()
//        queue.maxConcurrentOperationCount = 4
//        queue.name = "Thumbnail queue"
//        return queue
    }()

}

class ProcessEXIF: Operation {
    var item: JPEGInfo
    var store: PhotoStore
    init(item: JPEGInfo, store: PhotoStore) {
        self.item = item
        self.store = store
    }
    override func main() {
        if isCancelled { return }
//        print("Processing \(f.lastPathComponent)")
        if let imageSource = CGImageSourceCreateWithURL(item.path as CFURL, nil) {
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as Dictionary?
            pthread_rwlock_wrlock(&(store.databaselock))
            item.properties = imageProperties
            store.fileInYearTree(item)
            pthread_rwlock_unlock(&(store.databaselock))
        }
        store.processLocation(item)

    }

}

class AddToStore: Operation {
    var item: JPEGInfo
    var store: PhotoStore
    
    init(item: JPEGInfo, store: PhotoStore) {
        self.item = item
        self.store = store
    }
    
    override func main() {
        if isCancelled { return }
        store.semaphoredAddItem(item)
    }
}
