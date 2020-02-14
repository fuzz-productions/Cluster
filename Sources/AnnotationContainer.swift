//
//  AnnotationContainer.swift
//  Cluster
//
//  Created by Nick Trienens on 2/14/20.
//  Copyright © 2020 efremidze. All rights reserved.
//

import Foundation
import MapKit

protocol AnnotationsContainer {
    func add(_ annotation: MKAnnotation) -> Bool
    func remove(_ annotation: MKAnnotation) -> Bool
    func annotations(in rect: MKMapRect) -> [MKAnnotation]
}
