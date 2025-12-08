//
//  Application+PDFService.swift
//  droppie
//
//  Created by Artur Anissimov on 07.11.2025.
//

import Vapor

extension Application {
    private struct PDFServiceKey: StorageKey {
        typealias Value = PDFService
    }

    var pdfService: PDFService {
        get {
            if let existing = self.storage[PDFServiceKey.self] {
                return existing
            } else {
                let new = PDFService(app: self)
                self.storage[PDFServiceKey.self] = new
                return new
            }
        }
        set {
            self.storage[PDFServiceKey.self] = newValue
        }
    }
}

