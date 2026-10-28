import Foundation

/// Language and quality tags that providers put in category and channel names
/// ("FR | Sport", "|UK| BBC One FHD", "One Piece (VOSTFR)", "TF1 4K").
enum ContentTags {
    /// A tag found in the catalog, with how many items carry it.
    struct Option: Identifiable, Hashable {
        let tag: String
        let count: Int
        var id: String { tag }
    }

    /// Language tag: a leading country/language code ("FR | …", "[UK] …", "|AR| …", "DE: …"),
    /// else a French release tag anywhere in the name (VOSTFR, VFF, VFQ, MULTI…).
    static func language(of name: String) -> String? {
        if let match = name.firstMatch(of: leadingCode) {
            return String(match.1)
        }
        if let match = name.firstMatch(of: releaseTag) {
            let tag = match.1.uppercased()
            return tag.hasPrefix("MULTI") ? "MULTI" : tag
        }
        return nil
    }

    /// Quality tag of a channel name, normalized: 8K, 4K, FHD, HD, SD or HEVC.
    static func quality(of name: String) -> String? {
        let tokens = name.uppercased().split { !$0.isLetter && !$0.isNumber && $0 != "+" }.map(String.init)
        // Highest quality wins when a name carries several tags ("FHD HEVC").
        for (quality, aliases) in qualityAliases where tokens.contains(where: aliases.contains) {
            return quality
        }
        return nil
    }

    /// Two or three capital letters opening the name, followed by a separator.
    private static let leadingCode = /^\s*[\[\(|]?\s*([A-Z]{2,3})\s*(?:[\]\)|:•]|\s-\s)/
    private static let releaseTag = /(?i)\b(VOSTFR|VOST|VFF|VFQ|VFI|VF|VO|MULTI(?:SUBS)?)\b/

    private static let qualityAliases: [(String, Set<String>)] = [
        ("8K", ["8K", "4320P"]),
        ("4K", ["4K", "UHD", "2160P"]),
        ("FHD", ["FHD", "1080P", "FULLHD"]),
        ("HD", ["HD", "HD+", "720P"]),
        ("SD", ["SD", "480P", "576P"]),
        ("HEVC", ["HEVC", "H265"]),
    ]

    /// `name` without each of `removals` (case-insensitive), then without the separators and spaces
    /// left at its ends: "FR | Sport" minus "FR" gives "Sport". The original name if nothing is left.
    static func cleanedName(_ name: String, removing removals: [String]) -> String {
        var result = name
        for removal in removals where !removal.isEmpty {
            // Whole words only where the text starts / ends with a letter or digit: "FR" leaves "FRANCE" alone.
            let isWordy: (Character?) -> Bool = { $0?.isLetter == true || $0?.isNumber == true }
            let pattern = (isWordy(removal.first) ? "(?<![\\p{L}\\p{N}])" : "")
                + NSRegularExpression.escapedPattern(for: removal)
                + (isWordy(removal.last) ? "(?![\\p{L}\\p{N}])" : "")
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                    withTemplate: " ")
        }
        let edges = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "|-:•·/[]()"))
        result = result.trimmingCharacters(in: edges)
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return result.isEmpty ? name : result
    }

    /// Distinct tags with their number of occurrences, most common first.
    static func options(_ tags: [String]) -> [Option] {
        var counts: [String: Int] = [:]
        for tag in tags {
            counts[tag, default: 0] += 1
        }
        return counts.map { Option(tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }
}
