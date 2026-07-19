import Foundation

public struct CaptureSource: Codable, Equatable, Sendable {
    public var applicationName: String
    public var windowTitle: String?

    public init(applicationName: String, windowTitle: String?) {
        self.applicationName = Self.cleaned(applicationName)
        self.windowTitle = windowTitle.flatMap(Self.cleanedOptional)
    }

    public var displayLabel: String {
        let title = normalizedWindowTitle
        if let title, let host = Self.explicitURLHost(in: title) {
            return Self.join(applicationName, host)
        }
        if let title,
           !title.isEmpty,
           title.compare(applicationName, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame {
            return Self.join(applicationName, title)
        }
        return applicationName
    }

    private var normalizedWindowTitle: String? {
        guard var title = windowTitle.flatMap(Self.cleanedOptional) else { return nil }
        let suffixes = [" - ", " — ", " – ", " | "]
        for separator in suffixes {
            let suffix = separator + applicationName
            if let range = title.range(
                of: suffix,
                options: [.caseInsensitive, .diacriticInsensitive, .backwards, .anchored]
            ) {
                title.removeSubrange(range)
                title = Self.cleaned(title)
                break
            }
        }
        return title.isEmpty ? nil : title
    }

    private static func join(_ applicationName: String, _ detail: String) -> String {
        guard !applicationName.isEmpty else { return detail }
        guard !detail.isEmpty else { return applicationName }
        return "\(applicationName) · \(detail)"
    }

    private static func explicitURLHost(in text: String) -> String? {
        let punctuation = CharacterSet(charactersIn: "()[]{}<>,;\"'\n\r")
        for token in text.components(separatedBy: .whitespacesAndNewlines) {
            let candidate = token.trimmingCharacters(in: punctuation)
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  var host = url.host?.lowercased(),
                  !host.isEmpty else { continue }
            if host.hasPrefix("www.") {
                host.removeFirst(4)
            }
            return host
        }
        return nil
    }

    private static func cleanedOptional(_ value: String) -> String? {
        let result = cleaned(value)
        return result.isEmpty ? nil : result
    }

    private static func cleaned(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
