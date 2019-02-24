//
//  MapViewController.swift
//  Brownie
//
//  Created by Simon Cozens on 09/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Foundation
import MapKit

class MapViewController : NSViewController {
    @IBOutlet var mapView: MKMapView!
    @IBOutlet var collectionView: NSCollectionView!
    override func viewDidLoad() {
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildAnnotations), name: NSNotification.Name.MorePhotosHaveArrived, object: nil)
    }
    
    var visibleAnnotations : [PhotoCluster] {
        if pthread_rwlock_tryrdlock(&(PhotoStore.shared.clusterstorelock)) == 0 {
        let annots = mapView.annotations(in: mapView.visibleMapRect).map { obj -> PhotoCluster in return obj as! PhotoCluster }
        pthread_rwlock_unlock(&(PhotoStore.shared.clusterstorelock))
        return annots
        } else { return [] }
    }
    
    var visibleImages: [JPEGInfo] {
        pthread_rwlock_rdlock(&(PhotoStore.shared.clusterstorelock))
        let items = visibleAnnotations.flatMap {
            $0.items
        }
        pthread_rwlock_unlock(&(PhotoStore.shared.clusterstorelock))
        return items
    }
    
    var curMapScale = Double(1.0)
    @objc func rebuildAnnotations () {
        let photoStore = PhotoStore.shared
        print("Doing annotations")
        pthread_rwlock_rdlock(&(photoStore.clusterstorelock))
        let annotationset = Set<PhotoCluster>(photoStore.clusterStore.values)
        pthread_rwlock_unlock(&(photoStore.clusterstorelock))
        let currentAnnotations = Set(mapView.annotations as! [PhotoCluster])
        let toRemove = Array(currentAnnotations.subtracting(annotationset))
        let toAdd = Array(annotationset.subtracting(currentAnnotations))
        DispatchQueue.main.async {
            self.mapView.removeAnnotations(toRemove)
            self.mapView.addAnnotations(toAdd)
            self.collectionView.reloadData()
        }
    }
}

extension MapViewController :MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        print("Map scale: \(self.mapView.zoomLevel)")
        if (PhotoStore.shared.quiescent) {
            DispatchQueue.main.async {
                PhotoStore.shared.removeFilter(withTag: "Map")
                let mapFilter = PhotoFilter(tag: "Map") { photo in
                    return photo.location != nil &&
                    self.mapView.visibleMapRect.contains(MKMapPoint(photo.location!))
                }
                PhotoStore.shared.addFilter(mapFilter)
                PhotoStore.shared.rebuildYearTree()
                if self.mapView.zoomLevel != self.curMapScale {
                    self.curMapScale = self.mapView.zoomLevel
                    PhotoStore.shared.reroundCoordinates(self.curMapScale)
                    DispatchQueue.global(qos: .default).async {
                        self.rebuildAnnotations()
                    }
                }
                self.collectionView.reloadData()
            }
        }
    }
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is PhotoCluster else { return nil }
        pthread_rwlock_rdlock(&(PhotoStore.shared.clusterstorelock))
        let customAnnotationView = self.customAnnotationView(in: mapView, for: annotation)
        pthread_rwlock_unlock(&(PhotoStore.shared.clusterstorelock))
        return customAnnotationView
    }
    private func customAnnotationView(in mapView: MKMapView, for annotation: MKAnnotation) -> CustomAnnotationView {
        let identifier = (annotation as! PhotoCluster).items.first!.path.absoluteString
        
        if let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? CustomAnnotationView {
            annotationView.annotation = annotation
            return annotationView
        } else {
            let customAnnotationView = CustomAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            customAnnotationView.canShowCallout = true
            return customAnnotationView
        }
    }
}

extension MapViewController : NSCollectionViewDelegate, NSCollectionViewDataSource {
    
    // 2
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return visibleImages.count
    }
    
    // 3
    func collectionView(_ itemForRepresentedObjectAtcollectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        // 4
        let item = self.collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "CollectionViewItem"), for: indexPath)
        guard let collectionViewItem = item as? CollectionViewItem else {return item}
        let i = indexPath.last
        let v = visibleImages
        if i != nil && i! < v.count {
            collectionViewItem.item = v[i!]
        }
        return item
    }
    
}
