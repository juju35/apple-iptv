import Foundation

/// Streams an XMLTV guide (`<programme start="20261029120000 +0100" stop="…" channel="tf1.fr">`
/// with `<title>` / `<desc>`) into entries per XMLTV channel id, keeping only programmes that
/// overlap `window` so a multi-day guide stays small.
final class XMLTVParser: NSObject, XMLParserDelegate {
    private let window: ClosedRange<Date>
    private(set) var programmes: [String: [EPGEntry]] = [:]

    private var channel: String?
    private var start: Date?
    private var stop: Date?
    private var title = ""
    private var desc = ""
    private var text = ""
    private var count = 0

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss Z"
        return formatter
    }()

    init(window: ClosedRange<Date>) {
        self.window = window
    }

    /// Parses `data`; entries are sorted by start time.
    static func parse(_ data: Data, window: ClosedRange<Date>) -> [String: [EPGEntry]] {
        let delegate = XMLTVParser(window: window)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.programmes.mapValues { $0.sorted { $0.start < $1.start } }
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        // Some guides omit the offset ("20261029120000"): read it as UTC.
        return formatter.date(from: value) ?? formatter.date(from: value + " +0000")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "programme":
            channel = attributeDict["channel"]
            start = Self.date(attributeDict["start"])
            stop = Self.date(attributeDict["stop"])
            title = ""
            desc = ""
        case "title", "desc":
            text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "title" where title.isEmpty:
            title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "desc" where desc.isEmpty:
            desc = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "programme":
            if let channel, let start, let stop, stop > window.lowerBound, start < window.upperBound {
                count += 1
                programmes[channel, default: []].append(EPGEntry(
                    id: "\(channel)-\(count)",
                    title: title.isEmpty ? "—" : title,
                    start: start,
                    end: stop,
                    description: desc.isEmpty ? nil : desc
                ))
            }
            channel = nil
        default:
            break
        }
    }
}
