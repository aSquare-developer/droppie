//
//  RoutePDFModel.swift
//  droppie
//
//  Created by Artur Anissimov on 07.11.2025.
//

import Foundation

struct RoutePDFModel: Encodable {
    let date: String
    let description: String
    let startOdometer: String
    let endOdometer: String
    let distance: String
}
