import Foundation

/// The working day the Today page measures: a start and an end, in minutes after midnight.
///
/// Working hours rather than the whole day, because "62% of the day" at three in the afternoon is a fact
/// about the clock; "62% of your day" is a fact about what is left of the work. Before the start there is no
/// progress to show yet, and after the end the day is done.
nonisolated struct Workday: Equatable, Sendable {
    var start: Int
    var end: Int

    static let standard = Workday(start: 9 * 60, end: 18 * 60)

    enum Progress: Equatable, Sendable {
        /// Not started yet: it starts at this many minutes after midnight.
        case before(starts: Int)
        /// Under way: this share of it gone, ending at this many minutes after midnight.
        case during(fraction: Double, ends: Int)
        case after
    }

    /// Where `now` falls in the working day.
    func progress(at now: Date, calendar: Calendar = .current) -> Progress {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: now)
        let minute = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        // A day that ends before it starts, or not at all, has nothing to measure.
        guard end > start else { return .after }
        if minute < Double(start) { return .before(starts: start) }
        if minute >= Double(end) { return .after }
        return .during(fraction: (minute - Double(start)) / Double(end - start), ends: end)
    }

    /// "9:00", "18:30", in the Mac's own 12- or 24-hour style.
    static func time(_ minutes: Int, calendar: Calendar = .current) -> String {
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        let date = calendar.date(from: parts) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
