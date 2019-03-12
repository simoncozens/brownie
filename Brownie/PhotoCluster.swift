//
//  PhotoCluster.swift
//  Brownie
//
//  Created by Simon Cozens on 07/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Foundation
import MapKit
import AppKit
import SDWebImage

class PhotoCluster: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var items: [JPEGInfo]
    let title: String?
    let locationName: String
    init(title: String, locationName: String, items: [JPEGInfo], coordinate: CLLocationCoordinate2D) {
        self.title = title
        self.locationName = locationName
        self.items = items
        self.coordinate = coordinate
        
        super.init()
    }
    
    var subtitle: String? {
        return String(format: "%i", items.count)
    }

}


extension CLLocationCoordinate2D :Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.latitude)
        hasher.combine(self.longitude)
    }
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.longitude.isEqual(to: rhs.longitude) && lhs.latitude.isEqual(to: rhs.latitude)
    }
    
    func rounded(_ precision: Double) -> CLLocationCoordinate2D {
        let divand = precision / 2.0
        let rLat = (self.latitude * divand).rounded() / divand
        let rLong = (self.longitude * divand).rounded() / divand
        return CLLocationCoordinate2D(latitude: rLat, longitude: rLong)
        
    }
}

extension MKMapView {
    
    var zoomLevel: Double {
        let maxZoom: Double = 20
        let zoomScale = self.visibleMapRect.size.width / Double(self.frame.size.width)
        let zoomExponent = log2(zoomScale)
        return maxZoom - zoomExponent
    }
    
}


class CustomAnnotationView: MKAnnotationView {
    private let annotationFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
    private let label: NSTextField
    
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        self.label = NSTextField(frame: annotationFrame.offsetBy(dx: 0, dy: -6))
        self.label.isEnabled = false
        
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        guard annotation is PhotoCluster else { return }
        guard let item = (annotation as! PhotoCluster).items.first else { return }
        if (annotation as! PhotoCluster).items.count > 1 {
            self.label.stringValue = "+" + String((annotation as! PhotoCluster).items.count-1)
        }
        self.layer?.masksToBounds = true
        layer?.borderWidth = 1.0;
        layer?.cornerRadius = 8.0;

        self.frame = annotationFrame
        self.label.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        self.label.textColor = .white
        let transformer = SDImageResizingTransformer(size: CGSize(width: 200, height: 200), scaleMode: .aspectFit)

        SDWebImageManager.shared.loadImage(with: item.path, options: [], context: [.imageTransformer: transformer], progress: nil, completed: {
            (image, data, error, cache, finished, url) in
            DispatchQueue.main.async { self.image = image }
            })
        self.addSubview(label)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not implemented!")
    }
}
