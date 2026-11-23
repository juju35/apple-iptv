import Foundation

/// Search over item names that forgives what a remote or a phone keyboard makes hard to type: case,
/// accents, punctuation, spacing and word order ("spider man" finds "Spider-Man", "pokemon" finds
/// "Pokémon", "lete" finds "L'Été"). Best matches come first, so a capped list keeps them.
@MainActor
enum MediaSearch {
    /// A name as searched, built once per item: folding thousands of names on every keystroke made
    /// typing lag on Apple TV.
    private struct Key {
        let name: String
        let text: String
        let words: [Substring]
        let compact: String

        init(_ name: String) {
            self.name = name
            text = MediaSearch.normalize(name)
            words = text.split(separator: " ")
            compact = text.replacingOccurrences(of: " ", with: "")
        }
    }

    private static var keys: [String: Key] = [:]
    /// Several providers' catalogs over a session: start over rather than grow without end.
    private static let maxKeys = 300_000

    /// The items whose name matches `query`, best first (whole title, title start, word starts, anywhere).
    static func results(_ items: [MediaItem], matching query: String, limit: Int? = nil) -> [MediaItem] {
        let text = normalize(query)
        guard !text.isEmpty else { return limit.map { Array(items.prefix($0)) } ?? items }
        let tokens = text.split(separator: " ")
        let compact = text.replacingOccurrences(of: " ", with: "")
        if keys.count > maxKeys { keys.removeAll() }
        // Index in the catalog by score, so ties keep the catalog's order.
        var scored: [(score: Int, index: Int)] = []
        for (index, item) in items.enumerated() {
            if let score = score(key(for: item), text: text, tokens: tokens, compact: compact) {
                scored.append((score, index))
            }
        }
        scored.sort { ($0.score, $0.index) < ($1.score, $1.index) }
        let matches = scored.map { items[$0.index] }
        return limit.map { Array(matches.prefix($0)) } ?? matches
    }

    private static func key(for item: MediaItem) -> Key {
        if let key = keys[item.id], key.name == item.name { return key }
        let key = Key(item.name)
        keys[item.id] = key
        return key
    }

    private static func score(_ key: Key, text: String, tokens: [Substring], compact: String) -> Int? {
        if key.text == text { return 0 }
        if key.text.hasPrefix(text) || key.text.contains(" " + text) { return 1 }
        if tokens.allSatisfy({ token in key.words.contains { $0.hasPrefix(token) } }) { return 2 }
        if tokens.allSatisfy({ key.text.contains($0) }) { return 3 }
        if key.compact.contains(compact) { return 4 }
        return nil
    }

    /// Lowercased, without accents, ligatures spelled out, every run of other characters a single space.
    nonisolated static func normalize(_ string: String) -> String {
        let folded = string
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "ß", with: "ss")
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace && !result.isEmpty { result.append(" ") }
                result.append(scalar)
                pendingSpace = false
            } else {
                pendingSpace = true
            }
        }
        return String(result)
    }
}
