//
//  PDFService.swift
//  droppie
//
//  Created by Artur Anissimov on 07.11.2025.
//

import Vapor
import Foundation

final class PDFService: @unchecked Sendable {
    private let app: Application
    private let binaryPath: String?
    
    init(app: Application) {
        self.app = app

        if let configuredPath = Environment.get("WKHTMLTOPDF_PATH"), FileManager.default.isExecutableFile(atPath: configuredPath) {
            self.binaryPath = configuredPath
            return
        }

        let candidatePaths: [String] = [
            "/opt/homebrew/bin/wkhtmltopdf",
            "/usr/local/bin/wkhtmltopdf",
            "/usr/bin/wkhtmltopdf",
            "/app/vendor/wkhtmltopdf/bin/wkhtmltopdf"
        ]

        self.binaryPath = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
    
    /// Генерация PDF из HTML
    func generate(fromHTML html: String) async throws -> Data {
        guard let binaryPath else {
            app.logger.error("wkhtmltopdf binary is not configured or not executable.")
            throw Abort(.serviceUnavailable, reason: "PDF generation is unavailable because wkhtmltopdf is not installed.")
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let htmlPath = tmpDir.appendingPathComponent(UUID().uuidString + ".html")
        let pdfPath = tmpDir.appendingPathComponent(UUID().uuidString + ".pdf")
        
        try html.write(to: htmlPath, atomically: true, encoding: .utf8)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [htmlPath.path, pdfPath.path]
        
        let stderr = Pipe()
        process.standardError = stderr
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw Abort(.internalServerError, reason: "wkhtmltopdf failed: \(errText)")
        }
        
        let pdfData = try Data(contentsOf: pdfPath)
        
        try? FileManager.default.removeItem(at: htmlPath)
        try? FileManager.default.removeItem(at: pdfPath)
        
        return pdfData
    }
    
    /// Генерация PDF из Leaf-шаблона
    func generate(fromLeaf view: String, context: [String: any Encodable], using req: Request) async throws -> Data {
        let rendered = try await req.view.render(view, LeafContext(context)).get()
        let html = String(buffer: rendered.data)
        return try await generate(fromHTML: html)
    }
}
