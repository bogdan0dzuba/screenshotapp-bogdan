import Foundation

public enum CaptureFileName {
    public static func baseStem(
        for date: Date,
        applicationName: String?,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ru_RU")
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMMM, HH.mm"
        let timestamp = formatter.string(from: date)
        guard let applicationName = sanitizedApplicationName(applicationName) else {
            return timestamp
        }
        return "\(timestamp) - \(applicationName)"
    }

    public static func availableStem(baseStem: String, occupiedStems: Set<String>) -> String {
        guard occupiedStems.contains(baseStem) else { return baseStem }
        var suffix = 2
        while occupiedStems.contains("\(baseStem) (\(suffix))") {
            suffix += 1
        }
        return "\(baseStem) (\(suffix))"
    }

    private static func sanitizedApplicationName(_ value: String?) -> String? {
        guard let value else { return nil }
        let forbidden = CharacterSet(charactersIn: "/:\\?*<>|\"").union(.controlCharacters)
        let separated = value.components(separatedBy: forbidden).joined(separator: " ")
        let compact = separated.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
        return compact.isEmpty ? nil : compact
    }
}
