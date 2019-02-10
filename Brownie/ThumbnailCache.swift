//
//  ThumbnailCache.swift
//  Brownie
//
//  Created by Simon Cozens on 09/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Foundation
import AppKit

extension Notification.Name {
    static let ThumbnailCacheDidPostThumbnail
        = NSNotification.Name("DidPostThumbnail")
}

class ThumbnailCache {
    var size: UInt
    var lock: pthread_rwlock_t
    var cache: LRUCache<URL>
    var pendingOperations: PendingOperations
    static var caches: Dictionary<UInt,ThumbnailCache> = [:]
    static func with(size:UInt) -> ThumbnailCache {
        if caches[size] == nil {
            caches[size] = ThumbnailCache(size: size)
        }
        return caches[size]!
    }
    
    init (size: UInt) {
        self.size = size
        self.cache = LRUCache<URL>(1000)
        self.lock = pthread_rwlock_t()
        self.pendingOperations = PendingOperations()
        pthread_rwlock_init(&self.lock, nil)
    }
    
    func get(_ item: JPEGInfo, deferable: Bool, oncompletion: @escaping (NSImage?)->Void) -> NSImage? {
        pthread_rwlock_wrlock(&lock) // Get does a remove, so improbably we need a write lock
        let maybe = self.cache.get(item.path) as! NSImage?
        pthread_rwlock_unlock(&lock)
        if maybe != nil { return maybe }
        if deferable {
            // Enqueue job
            startThumbnailGen(for: item.path, oncompletion: oncompletion)
            return nil
        }
        return makeThumbnailNow(path: item.path)
    }
    
    func makeThumbnailNow(path: URL) -> NSImage? {
        guard let tn = NSImage.thumbnailImage(with: path, maxWidth: CGFloat(size))
            else { return nil }
        pthread_rwlock_wrlock(&lock)
        cache.set(path, val: tn)
        pthread_rwlock_unlock(&lock)
        return tn
    }
    
    func startThumbnailGen(for path: URL, oncompletion: @escaping (NSImage?)->Void) {
        pthread_rwlock_rdlock(&lock)
        guard pendingOperations.resizesInProgress[path] == nil else {
            pthread_rwlock_unlock(&lock)
            return
        }
        pthread_rwlock_unlock(&lock)
        let thumbmaker = ThumbnailGenerator(path, cache: self)
        thumbmaker.completionBlock = {
            if thumbmaker.isCancelled { return }
            pthread_rwlock_wrlock(&self.lock)
            self.pendingOperations.resizesInProgress.removeValue(forKey: path)
            oncompletion(self.cache.get(path) as! NSImage?)
            pthread_rwlock_unlock(&self.lock)
        }
        
        pthread_rwlock_wrlock(&lock)
        pendingOperations.resizesInProgress[path] = thumbmaker
        pthread_rwlock_unlock(&lock)
        //        thumbmaker.qualityOfService = .userInteractive
        //        thumbmaker.queuePriority = .veryHigh
        pendingOperations.thumbnailQueue.addOperation(thumbmaker)
    }

}

class ThumbnailGenerator: Operation {
    var path: URL
    var cache: ThumbnailCache
    
    init(_ path: URL, cache: ThumbnailCache) {
        self.path = path
        self.cache = cache
    }
    
    override func main() {
        if isCancelled { return }
        _ = cache.makeThumbnailNow(path: path)
    }
}

extension NSImage {
    
    static func thumbnailImage(with url: URL, maxWidth: CGFloat) -> NSImage? {
        guard let inputImage = NSImage(contentsOf: url) else { return nil }
        
        let aspectRatio = inputImage.size.height / inputImage.size.width
        
        let thumbSize = NSSize(width: maxWidth, height: maxWidth * aspectRatio)
        
        let outputImage = NSImage(size: thumbSize)
        
        outputImage.lockFocus()
        
        inputImage.draw(in: NSRect(x: 0, y: 0, width: thumbSize.width, height: thumbSize.height), from: .zero, operation: .sourceOver, fraction: 1)
        
        outputImage.unlockFocus()
        
        return outputImage
    }
    
}
