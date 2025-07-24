import Foundation

extension String {
    func normalizedRouteComponent() -> String {
        self
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: ",", with: "")
    }
}
