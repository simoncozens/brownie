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
    override func viewDidLoad() {
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildAnnotations), name: NSNotification.Name.MorePhotosHaveArrived, object: nil)
    }
    
    var curMapScale = Double(1.0)
    @objc func rebuildAnnotations () {
        let photoStore = PhotoStore.shared
        print("Doing annotations")
        pthread_rwlock_rdlock(&(photoStore.clusterstorelock))
        pthread_rwlock_rdlock(&(photoStore.regionrectlock))
        let annotationset = Set<PhotoCluster>(photoStore.clusterStore.values).filter {
            photoStore.regionRect.contains(MKMapPoint($0.coordinate))
        }
        pthread_rwlock_unlock(&(photoStore.clusterstorelock))
        pthread_rwlock_unlock(&(photoStore.regionrectlock))
        let currentAnnotations = Set(mapView.annotations as! [PhotoCluster])
        let toRemove = Array(currentAnnotations.subtracting(annotationset))
        let toAdd = Array(annotationset.subtracting(currentAnnotations))
        DispatchQueue.main.async {
//            self.photocount.stringValue = "\(self.photoStore.semaphoredCountItems())  photos"
            self.mapView.removeAnnotations(toRemove)
            self.mapView.addAnnotations(toAdd)
        }
    }
}

extension MapViewController :MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        print("Map scale: \(self.mapView.zoomLevel)")
        if self.mapView.zoomLevel != curMapScale {
            self.curMapScale = self.mapView.zoomLevel
            PhotoStore.shared.reroundCoordinates(self.curMapScale)
            DispatchQueue.global(qos: .default).async {
                self.rebuildAnnotations()
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
