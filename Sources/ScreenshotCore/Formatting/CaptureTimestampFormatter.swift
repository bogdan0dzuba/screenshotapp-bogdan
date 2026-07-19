import Foundation

public enum CaptureTimestampFormatter {
    public static func historyTitle(
        for date: Date,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ru_RU")
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMMM, HH:mm"
        return formatter.string(from: date)
    }

    public static func string(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let age = max(0, now.timeIntervalSince(date))
        if age <= 23 * 3_600 {
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        }

        let days = max(1, Int(age / 86_400))
        return "\(days) \(dayWord(for: days))"
    }

    private static func dayWord(for days: Int) -> String {
        let lastTwoDigits = days % 100
        if 11...14 ~= lastTwoDigits { return "дней" }

        switch days % 10 {
        case 1: return "день"
        case 2...4: return "дня"
        default: return "дней"
        }
    }
}
