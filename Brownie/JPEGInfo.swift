//
//  JPEGInfo.swift
//  Brownie
//
//  Created by Simon Cozens on 08/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Foundation
import MapKit

class JPEGInfo : Hashable {
    static func == (lhs: JPEGInfo, rhs: JPEGInfo) -> Bool {
        return lhs.path == rhs.path
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.path)
    }
    
    var path: URL
    var properties: Dictionary<NSObject, AnyObject>?
    var date :String? {
        guard let exif = properties?[kCGImagePropertyExifDictionary] else { return nil }
        return exif[kCGImagePropertyExifDateTimeOriginal] as! String?
    }
    var _isodate: Date?
    var isodate: Date? {
        if _isodate != nil { return _isodate }
        guard let stringdate = date else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        _isodate = dateFormatter.date(from: stringdate)
        return _isodate
    }
    
    var _location: CLLocationCoordinate2D?
    var location: CLLocationCoordinate2D? {
        if _location != nil { return _location }
        guard let gps = properties?[kCGImagePropertyGPSDictionary] else { return nil }
        guard var lat = gps[kCGImagePropertyGPSLatitude] as? CLLocationDegrees else { return nil }
        guard var long = gps[kCGImagePropertyGPSLongitude] as? CLLocationDegrees else { return nil }
        guard let latref = gps[kCGImagePropertyGPSLatitudeRef] else { return nil }
        guard let longref = gps[kCGImagePropertyGPSLongitudeRef] else { return nil }
        
        if (latref as! String) == "S" { lat = -lat }
        if (longref as! String) == "W" { long = -long }
        
        _location = CLLocationCoordinate2D(latitude: lat, longitude: long)
        return _location
    }
    init (path: URL, properties: Dictionary<NSObject,AnyObject>?) {
        self.path = path
        self.properties = nil
    }
}
