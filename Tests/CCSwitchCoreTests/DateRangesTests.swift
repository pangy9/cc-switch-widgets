import Foundation
import XCTest
@testable import CCSwitchCore

final class DateRangesTests: XCTestCase {
    func testBuildsCalendarAlignedBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 10, hour: 20, minute: 30
        )))

        let ranges = UsageDateRanges(now: now, calendar: calendar)

        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: ranges.todayStart),
                       DateComponents(year: 2026, month: 7, day: 10))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: ranges.yesterdayStart),
                       DateComponents(year: 2026, month: 7, day: 9))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: ranges.averageStart),
                       DateComponents(year: 2026, month: 7, day: 3))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: ranges.trendStart),
                       DateComponents(year: 2026, month: 6, day: 11))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: ranges.monthStart),
                       DateComponents(year: 2026, month: 7, day: 1))
    }

    func testHeatmapGridStartsOnMondayBeforeExactSixMonthBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 14, hour: 12
        )))

        let ranges = UsageDateRanges(now: now, calendar: calendar)

        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: ranges.heatmapStart),
                       DateComponents(year: 2026, month: 1, day: 14))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: ranges.heatmapGridStart),
                       DateComponents(year: 2026, month: 1, day: 12))
        XCTAssertEqual(calendar.component(.weekday, from: ranges.heatmapGridStart), 2)
    }
}
