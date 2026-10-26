import Foundation

/// Ready by stores when you *leave*. People think in when they must *arrive*, so the editor can take an arrival time plus a
/// travel time and convert. Weekdays are 1 = Sunday ... 7 = Saturday, and a trip that crosses midnight moves the weekday.
public enum LeaveTime {
    public static let maxTravelMinutes = 240
    private static let day = 1440, week = 7 * 1440

    public static func clampTravel(_ m: Int) -> Int { min(max(m, 0), maxTravelMinutes) }

    private static func shift(_ weekday: Int, _ hour: Int, _ minute: Int, by minutes: Int) -> (weekday: Int, hour: Int, minute: Int) {
        let index = ((weekday - 1) * day + hour * 60 + minute + minutes) % week
        let t = index < 0 ? index + week : index
        return (t / day + 1, t % day / 60, t % 60)
    }

    /// The moment to leave for an arrival at `weekday hour:minute` after `travel` minutes on the road.
    public static func leave(arriveWeekday w: Int, hour h: Int, minute m: Int, travel: Int) -> (weekday: Int, hour: Int, minute: Int) {
        shift(w, h, m, by: -clampTravel(travel))
    }

    /// The arrival time shown for a stored leave time.
    public static func arrive(leaveWeekday w: Int, hour h: Int, minute m: Int, travel: Int) -> (weekday: Int, hour: Int, minute: Int) {
        shift(w, h, m, by: clampTravel(travel))
    }
}
