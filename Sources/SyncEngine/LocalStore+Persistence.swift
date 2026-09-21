import Foundation

extension LocalStore {
    /// The encoder used when none is supplied.
    ///
    /// Keys are sorted so the same contents always encode to the same bytes — Foundation's
    /// default key order is not stable across encodes on Linux.
    public static var defaultEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Every record in the store, as a plain array.
    ///
    /// Equivalent to ``all()``, named for the persistence round trip it pairs with.
    public func snapshot() -> [SyncRecord] {
        all()
    }

    /// Replace the store's contents with a snapshot.
    ///
    /// - Parameter records: The records to restore. Existing contents are discarded.
    public func restore(from records: [SyncRecord]) {
        clear()
        putAll(records)
    }

    /// Encode the whole store as JSON.
    ///
    /// Records are sorted by id, and ``defaultEncoder`` sorts keys, so the same contents always
    /// encode to the same bytes — which makes a written file diffable and lets callers skip a
    /// no-op write.
    ///
    /// - Parameter encoder: The encoder to use. Defaults to ``defaultEncoder``.
    /// - Returns: The encoded records.
    /// - Throws: Any error thrown by the encoder.
    public func encoded(using encoder: JSONEncoder = LocalStore.defaultEncoder) throws -> Data {
        try encoder.encode(all().sorted { $0.id < $1.id })
    }

    /// Replace the store's contents from JSON produced by ``encoded(using:)``.
    ///
    /// The store is only cleared once decoding succeeds, so malformed data leaves it untouched.
    ///
    /// - Parameters:
    ///   - data: The encoded records.
    ///   - decoder: The decoder to use. Defaults to a plain `JSONDecoder`.
    /// - Throws: Any error thrown by the decoder.
    public func decode(from data: Data, using decoder: JSONDecoder = JSONDecoder()) throws {
        let records = try decoder.decode([SyncRecord].self, from: data)
        restore(from: records)
    }

    /// Write the store to a file as JSON.
    ///
    /// The write is atomic, so an interrupted save cannot leave a half-written file behind.
    ///
    /// - Parameters:
    ///   - url: Destination file URL.
    ///   - encoder: The encoder to use. Defaults to ``defaultEncoder``.
    /// - Throws: Any encoding or file-system error.
    public func save(to url: URL, using encoder: JSONEncoder = LocalStore.defaultEncoder) throws {
        try encoded(using: encoder).write(to: url, options: .atomic)
    }

    /// Replace the store's contents from a file written by ``save(to:using:)``.
    ///
    /// - Parameters:
    ///   - url: Source file URL.
    ///   - decoder: The decoder to use. Defaults to a plain `JSONDecoder`.
    /// - Throws: Any decoding or file-system error.
    public func load(from url: URL, using decoder: JSONDecoder = JSONDecoder()) throws {
        try decode(from: Data(contentsOf: url), using: decoder)
    }
}
