//
//  ViewController.swift
//  Brownie
//
//  Created by Simon Cozens on 07/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Cocoa
import MapKit

// Todo:
// Select year in tree view
// Sort out photo clustering
// Speed enhancements

extension Notification.Name {
    static let MorePhotosHaveArrived = NSNotification.Name("MorePhotosHaveArrived")
    static let SyncYearTree = NSNotification.Name("SyncYearTree")
    static let ActivityOn = NSNotification.Name("ActivityOn")
    static let ActivityOff = NSNotification.Name("ActivityOff")

}

class ViewController: NSWindowController {
//    @IBOutlet weak var photocount: NSTextField!
    @IBOutlet weak var spinner: NSProgressIndicator!
    override func windowWillLoad() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.animateSpinner), name: NSNotification.Name.ActivityOn, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.stopSpinner), name: NSNotification.Name.ActivityOff, object: nil)
        spinner.isHidden = false
    }
    
    @objc func animateSpinner() {
        print("Got animate notification")
        DispatchQueue.main.async {
            self.spinner.isHidden = false
            self.spinner.startAnimation(nil)
        }
    }
    @objc func stopSpinner() {
        DispatchQueue.main.async {
            self.spinner.stopAnimation(nil)
            self.spinner.isHidden = true
        }
    }

}


extension MKCoordinateRegion {
    
    init(coordinates: [CLLocationCoordinate2D]) {
        var minLat: CLLocationDegrees = 90.0
        var maxLat: CLLocationDegrees = -90.0
        var minLon: CLLocationDegrees = 180.0
        var maxLon: CLLocationDegrees = -180.0
        
        for coordinate in coordinates {
            let lat = Double(coordinate.latitude)
            let long = Double(coordinate.longitude)
            if lat < minLat {
                minLat = lat
            }
            if long < minLon {
                minLon = long
            }
            if lat > maxLat {
                maxLat = lat
            }
            if long > maxLon {
                maxLon = long
            }
        }
        
        let span = MKCoordinateSpan.init(latitudeDelta: maxLat - minLat, longitudeDelta: maxLon - minLon)
        let center = CLLocationCoordinate2DMake((maxLat - span.latitudeDelta / 2), maxLon - span.longitudeDelta / 2)
        self.init(center: center, span: span)
    }
    
}


extension CLLocationCoordinate2D {
    
    var latitudeMinutes:  Double { return (latitude * 3600).truncatingRemainder(dividingBy: 3600) / 60 }
    var latitudeSeconds:  Double { return ((latitude * 3600).truncatingRemainder(dividingBy: 3600)).truncatingRemainder(dividingBy: 60) }
    
    var longitudeMinutes: Double { return (longitude * 3600).truncatingRemainder(dividingBy: 3600) / 60 }
    var longitudeSeconds: Double { return ((longitude * 3600).truncatingRemainder(dividingBy: 3600)).truncatingRemainder(dividingBy: 60) }
    
    var dms:(latitude: String, longitude: String) {
        
        return (String(format:"%d°%d'%.1f\"%@",
                       Int(abs(latitude)),
                       Int(abs(latitudeMinutes)),
                       abs(latitudeSeconds),
                       latitude >= 0 ? "N" : "S"),
                String(format:"%d°%d'%.1f\"%@",
                       Int(abs(longitude)),
                       Int(abs(longitudeMinutes)),
                       abs(longitudeSeconds),
                       longitude >= 0 ? "E" : "W"))
    }
    
    var dmm: (latitude: String, longitude: String) {
        return (String(format:"%d°%.4f'%@",
                       Int(abs(latitude)),
                       abs(latitudeMinutes),
                       latitude >= 0 ? "N" : "S"),
                String(format:"%d°%.4f'%@",
                       Int(abs(longitude)),
                       abs(longitudeMinutes),
                       longitude >= 0 ? "E" : "W"))
    }
}
