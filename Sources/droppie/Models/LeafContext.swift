//
//  File.swift
//  droppie
//
//  Created by Artur Anissimov on 07.11.2025.
//

import Foundation

struct LeafContext: Encodable {
    private let data: [String: any Encodable]

    init(_ data: [String: any Encodable]) {
        self.data = data
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in data {
            try container.encode(EncodableWrapper(value: value), forKey: DynamicCodingKey(stringValue: key))
        }
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        init(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    private struct EncodableWrapper: Encodable {
        let value: any Encodable
        func encode(to encoder: any Encoder) throws {
            try value.encode(to: encoder)
        }
    }
}
