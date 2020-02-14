//
//  Cluster.swift
//  Cluster
//
//  Created by Lasha Efremidze on 4/13/17.
//  Copyright © 2017 efremidze. All rights reserved.
//

import CoreLocation
import MapKit

public protocol ClusterManagerDelegate: class {
    /**
     The size of each cell on the grid (The larger the size, the better the performance) at a given zoom level.
     
     - Parameters:
        - zoomLevel: The zoom level of the visible map region.
     
     - Returns: The cell size at the given zoom level. If you return nil, the cell size will automatically adjust to the zoom level.
     */
    func cellSize(for zoomLevel: Double) -> Double?
    
    /**
     Whether to cluster the given annotation.
     
     - Parameters:
        - annotation: An annotation object. The object must conform to the MKAnnotation protocol.

     - Returns: `true` to clusterize the given annotation.
     */
    func shouldClusterAnnotation(_ annotation: MKAnnotation) -> Bool
}

public extension ClusterManagerDelegate {
    func cellSize(for zoomLevel: Double) -> Double? {
        return nil
    }
    
    func shouldClusterAnnotation(_ annotation: MKAnnotation) -> Bool {
        return true
    }
}

open class ClusterManager {
    var grouper = AnnotationGrouper()
    
    /**
     The minimum number of annotations for a cluster.
     
     The default is 2.
     */
    open var minCountForClustering: Int = 2
    
    /**
     Whether to remove invisible annotations.
     
     The default is true.
     */
    open var shouldRemoveInvisibleAnnotations: Bool = true
    
    /**
     The position of the cluster annotation.
     */
    public enum ClusterPosition {
        /**
         Placed on the computed average of the coordinates of all annotations in a cluster.
         */
        case average
    }
    
    /**
     The position of the cluster annotation. The default is `.average`.
     */
    open var clusterPosition: ClusterPosition = .average
    
    /**
     The list of annotations associated.
     
     The objects in this array must adopt the MKAnnotation protocol. If no annotations are associated with the cluster manager, the value of this property is an empty array.
     */
    open var annotations: [MKAnnotation] {
        return dispatchQueue.sync {
            grouper.annotations(in: .world)
        }
    }
    
    /**
     The list of visible annotations associated.
     */
    open var visibleAnnotations = [MKAnnotation]()
    
    /**
     The list of nested visible annotations associated.
     */
    open var visibleNestedAnnotations: [MKAnnotation] {
        return dispatchQueue.sync {
            visibleAnnotations.reduce([MKAnnotation](), { $0 + (($1 as? ClusterAnnotation)?.annotations ?? [$1]) })
        }
    }
    
    let operationQueue = OperationQueue.serial
    let dispatchQueue = DispatchQueue(label: "com.cluster.concurrentQueue", attributes: .concurrent)
    
    open weak var delegate: ClusterManagerDelegate?
    
    public init() {}
    
    /**
     Adds an annotation object to the cluster manager.
     
     - Parameters:
        - annotation: An annotation object. The object must conform to the MKAnnotation protocol.
     */
    open func add(_ annotation: MKAnnotation) {
        operationQueue.cancelAllOperations()
        dispatchQueue.async(flags: .barrier) { [weak self] in
            self?.grouper.add(annotation)
        }
    }
    
    /**
     Adds an array of annotation objects to the cluster manager.
     
     - Parameters:
        - annotations: An array of annotation objects. Each object in the array must conform to the MKAnnotation protocol.
     */
    open func add(_ annotations: [MKAnnotation]) {
        operationQueue.cancelAllOperations()
        dispatchQueue.async(flags: .barrier) { [weak self] in
            for annotation in annotations {
                self?.grouper.add(annotation)
            }
        }
    }
    
    /**
     Removes an annotation object from the cluster manager.
     
     - Parameters:
        - annotation: An annotation object. The object must conform to the MKAnnotation protocol.
     */
    open func remove(_ annotation: MKAnnotation) {
        operationQueue.cancelAllOperations()
        dispatchQueue.async(flags: .barrier) { [weak self] in
            self?.grouper.remove(annotation)
        }
    }
    
    /**
     Removes an array of annotation objects from the cluster manager.
     
     - Parameters:
        - annotations: An array of annotation objects. Each object in the array must conform to the MKAnnotation protocol.
     */
    open func remove(_ annotations: [MKAnnotation]) {
        operationQueue.cancelAllOperations()
        dispatchQueue.async(flags: .barrier) { [weak self] in
            for annotation in annotations {
                self?.grouper.remove(annotation)
            }
        }
    }
    
    /**
     Removes all the annotation objects from the cluster manager.
     */
    open func removeAll() {
        operationQueue.cancelAllOperations()
        dispatchQueue.async(flags: .barrier) { [weak self] in
            self?.grouper = AnnotationGrouper()
        }
    }

    /**
     Reload the annotations on the map view.
     
     - Parameters:
        - mapView: The map view object to reload.
        - completion: A closure to be executed when the reload finishes. The closure has no return value and takes a single Boolean argument that indicates whether or not the reload actually finished before the completion handler was called.
     */
    open func reload(mapView: MKMapView, completion: @escaping (Bool) -> Void = { finished in }) {
        let mapBounds = mapView.bounds
        let visibleMapRect = mapView.visibleMapRect
        let visibleMapRectWidth = visibleMapRect.size.width
        let zoomScale = Double(mapBounds.width) / visibleMapRectWidth
        operationQueue.cancelAllOperations()
        operationQueue.addBlockOperation { [weak self, weak mapView] operation in
            guard let self = self, let mapView = mapView else { return completion(false) }
            autoreleasepool {
                let (toAdd, toRemove) = self.clusteredAnnotations(zoomScale: zoomScale, visibleMapRect: visibleMapRect, operation: operation)
                DispatchQueue.main.async { [weak self, weak mapView] in
                    guard let self = self, let mapView = mapView else { return completion(false) }
                      self.display(mapView: mapView, toAdd: toAdd, toRemove: toRemove)
                    completion(true)
                }
            }
        }
    }
    
    open func clusteredAnnotations(zoomScale: Double, visibleMapRect: MKMapRect, operation: Operation? = nil) -> (toAdd: [MKAnnotation], toRemove: [MKAnnotation]) {
        var isCancelled: Bool { return operation?.isCancelled ?? false }
        
        guard !isCancelled else { return (toAdd: [], toRemove: []) }
                
        let allAnnotations = dispatchQueue.sync {
            grouper.clusteredAnnotations(zoomScale: zoomScale, minCountForClustering: minCountForClustering, delegate: delegate)
        }
        guard !isCancelled else { return (toAdd: [], toRemove: []) }
        
        let before = visibleAnnotations
        let after = allAnnotations

        var toRemove = before.subtracted(after)
        let toAdd = after.subtracted(before)

        if !shouldRemoveInvisibleAnnotations {
            let toKeep = toRemove.filter { !visibleMapRect.contains($0.coordinate) }
            toRemove.subtract(toKeep)
        }
        
       dispatchQueue.async(flags: .barrier) { [weak self] in
                 self?.visibleAnnotations.subtract(toRemove)
                 self?.visibleAnnotations.add(toAdd)
             }
        
        return (toAdd: toAdd, toRemove: toRemove)
    }
  
    open func display(mapView: MKMapView, toAdd: [MKAnnotation], toRemove: [MKAnnotation]) {
        assert(Thread.isMainThread, "This function must be called from the main thread.")
        mapView.removeAnnotations(toRemove)
        mapView.addAnnotations(toAdd)
    }
    
    func cellSize(for zoomLevel: Double) -> Double {
        if let cellSize = delegate?.cellSize(for: zoomLevel) {
            return cellSize
        }
        switch zoomLevel {
        case 13...15:
            return 64
        case 16...18:
            return 32
        case 19...:
            return 16
        default:
            return 88
        }
    }
    
}
