import Foundation

/// A JSON document you can walk without knowing its shape.
///
/// `Codable` is the right tool when a response has a contract. The internal
/// YouTube Music endpoints have no contract: they return several hundred
/// kilobytes of nested "renderers" whose structure changes without notice, and
/// modelling that as Swift types would mean a `Decodable` conformance that
/// fails wholesale the first week Google inserts a wrapper. This walks it
/// instead, and a missing key is `nil` rather than a thrown error that loses
/// the ninety-nine results that *were* fine.
enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Parsing

    init(data: Data) throws {
        let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        self = JSONValue(raw)
    }

    init(_ raw: Any) {
        switch raw {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            // `NSNumber` is how `JSONSerialization` represents both booleans
            // and numbers, and the only way to tell them apart is the ObjC
            // type encoding. Getting this wrong turns every `true` into `1`.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as [Any]:
            self = .array(value.map(JSONValue.init))
        case let value as [String: Any]:
            self = .object(value.mapValues(JSONValue.init))
        default:
            self = .null
        }
    }

    // MARK: - Access

    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let elements) = self, elements.indices.contains(index) else { return nil }
        return elements[index]
    }

    /// Follows a path, stopping at the first missing or wrongly-typed step.
    ///
    /// The alternative is four levels of `if let`, at every one of a hundred
    /// call sites, in a parser whose whole job is that any of those levels may
    /// have been renamed since Tuesday.
    subscript(path: String...) -> JSONValue? {
        var current: JSONValue? = self
        for step in path {
            if let index = Int(step) {
                current = current?[index]
            } else {
                current = current?[step]
            }
            if current == nil { return nil }
        }
        return current
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var int: Int? {
        switch self {
        case .number(let value): Int(value)
        case .string(let value): Int(value)
        default: nil
        }
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Every value in the tree stored under `key`, at any depth, in document
    /// order.
    ///
    /// This is the heart of how Cue survives an endpoint nobody documents.
    /// Search results arrive inside a `musicShelfRenderer` inside a
    /// `sectionListRenderer` inside a `tabRenderer` inside a
    /// `tabbedSearchResultsRenderer`; the library arrives inside a
    /// `gridRenderer` inside a `singleColumnBrowseResultsRenderer`; the home
    /// feed uses carousels. All three change. What has stayed put for years is
    /// the name of the leaf renderer that describes one row — so Cue looks for
    /// those by name and ignores everything wrapped around them. When Google
    /// adds another layer, nothing here notices.
    func collect(_ key: String) -> [JSONValue] {
        var found: [JSONValue] = []
        collect(key, into: &found)
        return found
    }

    private func collect(_ key: String, into found: inout [JSONValue]) {
        switch self {
        case .object(let members):
            // Deterministic order matters: these become a list the user reads,
            // and dictionary iteration order is not stable between runs.
            if let match = members[key] { found.append(match) }
            for name in members.keys.sorted() {
                members[name]?.collect(key, into: &found)
            }
        case .array(let elements):
            for element in elements { element.collect(key, into: &found) }
        default:
            break
        }
    }

    /// The first value in the tree stored under `key`, at any depth.
    func firstValue(forKey key: String) -> JSONValue? {
        switch self {
        case .object(let members):
            if let match = members[key] { return match }
            for name in members.keys.sorted() {
                if let match = members[name]?.firstValue(forKey: key) { return match }
            }
            return nil
        case .array(let elements):
            for element in elements {
                if let match = element.firstValue(forKey: key) { return match }
            }
            return nil
        default:
            return nil
        }
    }

    /// The concatenated text of a YouTube `runs` array — the shape every piece
    /// of user-visible text on the service arrives in, split at every point
    /// where a word happened to be a link.
    var runsText: String? {
        guard let runs = self["runs"]?.array else { return string }
        let text = runs.compactMap { $0["text"]?.string }.joined()
        return text.isEmpty ? nil : text
    }
}
