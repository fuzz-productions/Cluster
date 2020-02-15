//
//  AnnotationGrouper.swift
//  Example
//
//  Created by Nick Trienens on 2/14/20.
//  Copyright © 2020 efremidze. All rights reserved.
//

import Foundation
import MapKit

extension MKAnnotation {
    static func == (lhs: MKAnnotation, rhs: MKAnnotation) -> Bool {
        return lhs.coordinate == rhs.coordinate
    }
}

public class AnnotationGrouper: AnnotationsContainer {
    var annotations =  [MKAnnotation]()
    var groups =  [AnnatationGroup]()
    var updateSinceLastRanging = true
    
    var rangedSet = [SortingPin]()
    
    @discardableResult
   public func add(_ annotation: MKAnnotation) -> Bool {
        if annotations.contains(where: { $0.coordinate == annotation.coordinate }) { return false }
        
        annotations.append(annotation)
        updateSinceLastRanging = true
        return true
   }
   
   @discardableResult
   public func remove(_ annotation: MKAnnotation) -> Bool {
        annotations.remove(annotation)
        updateSinceLastRanging = true
        return true
   }
   
   public func annotations(in rect: MKMapRect) -> [MKAnnotation] {
       return annotations
   }
    
    func clusteredAnnotations( zoomScale: Double,
                               minCountForClustering: Int,
                               mapCenter: CLLocationCoordinate2D,
                               maxZoomLevel: Int,
                               delegate: ClusterManagerDelegate?) -> [MKAnnotation] {
        
        let clusteringRange = 1.0/zoomScale * 10.0
        
        if updateSinceLastRanging {
            rangedSet = annotations.map { pin -> SortingPin in
                 let sorted = annotations.compactMap  { second -> SortingPin? in
                    guard !pin.isEqual(second) else { return nil }
                    let distance = pin.coordinate.distance(from: second.coordinate)
                    return SortingPin( annotation: second, distance: distance)
                }
                return SortingPin(annotation: pin, nearby: sorted)
            }
            .sorted { $0.annotation.coordinate.distance(from: mapCenter) < $1.annotation.coordinate.distance(from: mapCenter) }
            
            updateSinceLastRanging = false
        }
        var usedPins = [SortingPin]()
        var createdClusters = [AnnatationGroup]()
        var singleAnnotations = [MKAnnotation]()
        var protectedAnnotations = [MKAnnotation]()
        
        
        for pin in rangedSet {
            if zoomScale.zoomLevel > Double(maxZoomLevel) {
                singleAnnotations.append(pin.annotation)
                continue
            }
            
            if !(delegate?.shouldClusterAnnotation(pin.annotation) ?? true) {
                protectedAnnotations.append(pin.annotation)
                usedPins.append(pin)
                continue
            }
            if usedPins.contains(pin) {
                continue
            }
            
            let clustingPins = pin.nearby.filter { proposed in
                let taken = usedPins.contains(where: { $0.annotation.coordinate ==  proposed.annotation.coordinate })
                return proposed.distance < clusteringRange && !taken

            }
            
            if clustingPins.count <= minCountForClustering {
                singleAnnotations.append(pin.annotation)
                usedPins.append(pin)
                
                clustingPins.forEach {
                    singleAnnotations.append($0.annotation)
                }
            } else {
                let newGroup = AnnatationGroup()
                newGroup.annotations = clustingPins.map { $0.annotation } + [pin.annotation]
                usedPins.append(pin)
                clustingPins.forEach {
                    usedPins.append($0)
                    singleAnnotations.subtract([$0.annotation])
                }
                createdClusters.append(newGroup)
            }
        }
        
        return protectedAnnotations + singleAnnotations + createdClusters.map( { ClusterAnnotation(annotations: $0.annotations, coordinate: $0.coordinate()) })
    }
}

struct SortingPin: Equatable {
    static func == (lhs: SortingPin, rhs: SortingPin) -> Bool {
        lhs.annotation.isEqual(rhs.annotation)
    }
    
    let annotation: MKAnnotation
    let nearby: [SortingPin]
    let distance: Double
    
    init( annotation: MKAnnotation, nearby: [SortingPin] = [SortingPin](), distance: Double = .greatestFiniteMagnitude) {
        self.annotation = annotation
        self.nearby = nearby
        self.distance = distance
    }
}

class AnnatationGroup: Equatable {
    static func == (lhs: AnnatationGroup, rhs: AnnatationGroup) -> Bool {
        lhs.id == rhs.id
    }
    
    let id = UUID().uuidString
    var annotations =  [MKAnnotation]()

    
    func coordinate() -> CLLocationCoordinate2D {
                   let coordinates = annotations.map { $0.coordinate }
                   let totals = coordinates.reduce((latitude: 0.0, longitude: 0.0)) { ($0.latitude + $1.latitude, $0.longitude + $1.longitude) }
                   return CLLocationCoordinate2D(latitude: totals.latitude / Double(coordinates.count), longitude: totals.longitude / Double(coordinates.count))
           }
    
}
