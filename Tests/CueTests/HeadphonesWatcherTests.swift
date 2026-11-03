import Foundation
import Testing

@testable import Cue

/// Headphones arriving: what they are, and how full.
@MainActor
struct HeadphonesWatcherTests {
    private typealias Battery = HeadphonesWatcher.Battery

    /// The shape `system_profiler -json SPBluetoothDataType` reports.
    private let report = Data("""
        {"SPBluetoothDataType": [{
          "device_connected": [
            {"Alan’s AirPods Pro": {
              "device_batteryLevelCase": "6%",
              "device_batteryLevelLeft": "99%",
              "device_batteryLevelRight": "52%",
              "device_minorType": "Headphones"}}
          ],
          "device_not_connected": [
            {"MX Master 3S": {"device_minorType": "Mouse"}},
            {"Studio Headphones": {"device_batteryLevelMain": "70%"}}
          ]
        }]}
        """.utf8)

    @Test func `AirPods levels come out of the system's report`() {
        let battery = HeadphonesWatcher.battery(fromReport: report, deviceName: "Alan’s AirPods Pro")

        #expect(battery == Battery(left: 99, right: 52, single: nil, caseLevel: 6))
    }

    @Test func `the ring shows the emptier ear`() {
        #expect(Battery(left: 99, right: 52).shown == 52)
        #expect(Battery(single: 70).shown == 70)
    }

    @Test func `over-ear headphones have one level`() {
        let battery = HeadphonesWatcher.battery(fromReport: report, deviceName: "Studio Headphones")
        #expect(battery?.shown == 70)
    }

    @Test func `a device with no levels gives none`() {
        #expect(HeadphonesWatcher.battery(fromReport: report, deviceName: "MX Master 3S") == nil)
        #expect(HeadphonesWatcher.battery(fromReport: report, deviceName: "Nobody's") == nil)
        #expect(HeadphonesWatcher.battery(fromReport: Data("not json".utf8), deviceName: "x") == nil)
    }

    @Test func `the name says which AirPods`() {
        #expect(HeadphonesWatcher.Kind(name: "Alan’s AirPods Pro") == .airPodsPro)
        #expect(HeadphonesWatcher.Kind(name: "AirPods Max") == .airPodsMax)
        #expect(HeadphonesWatcher.Kind(name: "Kitchen AirPods") == .airPods)
        #expect(HeadphonesWatcher.Kind(name: "Beats Studio Pro") == .beats)
        #expect(HeadphonesWatcher.Kind(name: "soundcore Select 3") == .headphones)
    }
}
