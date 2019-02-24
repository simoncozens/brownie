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
//        queue.maxConcurrentOperationCount = 4
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
}

class ProcessEXIF: Operation {
    var item: JPEGInfo
    init(item: JPEGInfo) {
        self.item = item
    }
    override func main() {
        if isCancelled { return }
//        print("Processing EXIF for \(item.path)")
//        let startTime = CFAbsoluteTimeGetCurrent()

        if let imageSource = CGImageSourceCreateWithURL(item.path as CFURL, nil) {
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as Dictionary?
            item.properties = imageProperties
            PhotoStore.shared.fileInYearTree(item)
        }
        PhotoStore.shared.processLocation(item)
//        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
//        print("Processed EXIF for \(item.path) in \(elapsed)s")
    }

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
