import Foundation

public struct UsageDateRanges: Sendable {
    public let now: Date
    public let todayStart: Date
    public let yesterdayStart: Date
    public let averageStart: Date
    public let trendStart: Date
    public let extendedTrendStart: Date
    public let heatmapStart: Date
    public let heatmapGridStart: Date
    public let monthStart: Date

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        todayStart = calendar.startOfDay(for: now)
        yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        averageStart = calendar.date(byAdding: .day, value: -7, to: todayStart)!
        trendStart = calendar.date(byAdding: .day, value: -29, to: todayStart)!
        extendedTrendStart = calendar.date(byAdding: .day, value: -59, to: todayStart)!
        heatmapStart = calendar.date(byAdding: .month, value: -6, to: todayStart)!
        let heatmapWeekday = (calendar.component(.weekday, from: heatmapStart) + 5) % 7
        heatmapGridStart = calendar.date(byAdding: .day, value: -heatmapWeekday, to: heatmapStart)!
        monthStart = calendar.dateInterval(of: .month, for: now)!.start
    }
}
