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
        var queue = OperationQueue()
        queue.name = "EXIF queue"
        return queue
    }()
}

class AddToStore: Operation {
    var item: JPEGInfo
    
    init(item: JPEGInfo) {
        self.item = item
    }
    
    override func main() {
        if isCancelled { return }
        PhotoStore.shared.semaphoredAddItem(item)
    }
}

class ProcessEXIF: Operation {
    var item: JPEGInfo
    
    init(item: JPEGInfo) {
        self.item = item
    }
    override func main() {
        if isCancelled { return }
        if let imageSource = CGImageSourceCreateWithURL(item.path as CFURL, nil) {
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as Dictionary?
            item.properties = imageProperties
            // Parse date
            _ = item.isodate
            _ = item.location
        }
    }
}

class FinishFiling: Operation {
    var item: JPEGInfo
    
    init(item: JPEGInfo) {
        self.item = item
    }

    override func main() {
        if isCancelled { return }
        PhotoStore.shared.fileInYearTree(item)
        PhotoStore.shared.processLocation(item)
    }
}
