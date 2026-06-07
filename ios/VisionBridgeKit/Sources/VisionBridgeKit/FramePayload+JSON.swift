import Foundation

extension FramePayload {
    /// Encodes this payload as JSON (snake_case keys, shared with `docs/contract.example.json`).
    public func jsonData(prettyPrinted: Bool = false) throws -> Data {
        let enc = JSONEncoder()
        if prettyPrinted {
            enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        }
        return try enc.encode(self)
    }

    /// UTF-8 JSON string for debugging, dashboards, or logging to the Python bridge team.
    public func jsonString(prettyPrinted: Bool = false) throws -> String {
        let data = try jsonData(prettyPrinted: prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
