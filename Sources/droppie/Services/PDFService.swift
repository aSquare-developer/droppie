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
    private let binaryPath: String
    
    init(app: Application) {
        self.app = app
        
        // Определяем путь к wkhtmltopdf под macOS и Linux
#if os(macOS)
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/wkhtmltopdf") {
            self.binaryPath = "/opt/homebrew/bin/wkhtmltopdf"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/wkhtmltopdf") {
            self.binaryPath = "/usr/local/bin/wkhtmltopdf"
        } else {
            self.binaryPath = "/usr/bin/env" // fallback
        }
#else
        // Для Heroku (Linux)
        self.binaryPath = "/app/vendor/wkhtmltopdf/bin/wkhtmltopdf"
#endif
    }
    
    /// Генерация PDF из HTML
    func generate(fromHTML html: String) async throws -> Data {
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
