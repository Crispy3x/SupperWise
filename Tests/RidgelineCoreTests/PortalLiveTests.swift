import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RidgelineCore

private final class Recorder: HTTPClient, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) { requests.append(request); return (Data("{}".utf8), 200) }
}

final class PortalLiveTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func world(sites: Int = 3) -> (AppData, [Site], StormEvent) {
        var d = AppData()
        d.companyName = "Ridge Plow"
        var made: [Site] = []
        for i in 0..<sites {
            let c = Customer(name: "Client \(i)", emailConsent: true)
            let s = Site(customerID: c.id, address: "\(i + 1) Elm Ave", latitude: 44.97812345 + Double(i), longitude: -93.26512345, priority: 3, triggerInches: 2)
            d.customers.append(c); d.sites.append(s); made.append(s)
        }
        d.ensurePortalLinks(now: t0)
        return (d, made, StormEvent(name: "Nov 18", start: t0, forecastInches: 4))
    }

    private func build(_ d: AppData, _ storm: StormEvent, served: Set<UUID>, offsets: [UUID: Double] = [:], weather: PortalWeather? = nil) -> PortalSnapshot {
        PortalSnapshotBuilder.build(data: d, storm: storm, forecastInches: 4, servedSiteIDs: served, visitStormName: "Nov 18",
                                    routeStart: t0, arrivalOffsets: offsets, weather: weather, now: t0, timeZone: TimeZone(identifier: "UTC")!)
    }

    func testEachPageGetsItsPlaceOnTheMapRoundedToAboutOneHundredMetres() {
        let (d, sites, storm) = world(sites: 1)
        let s = build(d, storm, served: [sites[0].id]).sites[0]
        XCTAssertEqual(s.siteLocation?.latitude, 44.978)
        XCTAssertEqual(s.siteLocation?.longitude, -93.265)
    }

    func testASiteWithoutAMapLocationSendsNone() {
        var (d, sites, storm) = world(sites: 1)
        d.sites[0].latitude = nil; d.sites[0].longitude = nil
        XCTAssertNil(build(d, storm, served: [sites[0].id]).sites[0].siteLocation)
    }

    func testStopsAheadCountsTheStopsBeforeEachProperty() {
        let (d, sites, storm) = world(sites: 3)
        let offsets: [UUID: Double] = [sites[0].id: 600, sites[1].id: 1800, sites[2].id: 3000]
        let snap = build(d, storm, served: Set(sites.map(\.id)), offsets: offsets)
        let byLabel = Dictionary(uniqueKeysWithValues: snap.sites.map { ($0.label, $0.stopsAhead) })
        XCTAssertEqual(byLabel["1 Elm Ave"]!, 0)
        XCTAssertEqual(byLabel["2 Elm Ave"]!, 1)
        XCTAssertEqual(byLabel["3 Elm Ave"]!, 2)
        XCTAssertNil(build(d, storm, served: Set(sites.map(\.id))).sites[0].stopsAhead)           // no route yet, no count
        let notServed = build(d, storm, served: [sites[0].id], offsets: offsets)
        XCTAssertNil(notServed.sites.first { $0.label == "2 Elm Ave" }?.stopsAhead)              // only properties waiting for service
    }

    func testWeatherIsAPlainSentenceAndAlertsAreLimitedToThree() {
        let f = WeatherWindowSummary(snowfallInches: 4.04, peakSnowRateInPerHour: 1, temperatureF: 28, minTemperatureF: 23.6, maxWindMph: 18.2)
        func alert(_ h: String) -> WinterAlert { WinterAlert(event: "e", severity: "s", headline: h, onset: nil, ends: nil) }
        let w = PortalWeather.make(from: f, alerts: [alert("A"), alert("B"), alert("C"), alert("D"), alert("")])!
        XCTAssertEqual(w.summary, "Snow expected: about 4.0 in over the next 24 hours. Low 24 F, wind up to 18 mph.")
        XCTAssertEqual(w.alerts, ["A", "B", "C"])
        let calm = WeatherWindowSummary(snowfallInches: 0, peakSnowRateInPerHour: 0, minTemperatureF: 34, maxWindMph: 4)
        XCTAssertEqual(PortalWeather.make(from: calm, alerts: [])?.summary, "No significant snow expected in the next 24 hours. Low 34 F.")
        XCTAssertNil(PortalWeather.make(from: nil, alerts: []))
        XCTAssertEqual(PortalWeather.make(from: nil, alerts: [alert("Warning")])?.alerts, ["Warning"])
    }

    func testTipLinksAreSentOnlyWhenTheyPassTheSafetyCheck() {
        var (d, sites, storm) = world(sites: 1)
        XCTAssertNil(build(d, storm, served: [sites[0].id]).tips)
        d.profile.venmoLink = "https://venmo.com/ridgeplow"
        d.profile.paypalLink = "https://evil.example.com/pay"
        let tips = build(d, storm, served: [sites[0].id]).tips
        XCTAssertEqual(tips?.venmoURL, "https://venmo.com/ridgeplow")
        XCTAssertNil(tips?.paypalURL)
        d.profile.venmoLink = "http://venmo.com/x"
        XCTAssertNil(build(d, storm, served: [sites[0].id]).tips)
    }

    func testSnapshotJSONCarriesTheNewFieldsAndNoContactDetails() throws {
        var (d, sites, storm) = world(sites: 1)
        d.profile.cashAppLink = "https://cash.app/$ridgeplow"
        let snap = build(d, storm, served: [sites[0].id], offsets: [sites[0].id: 600], weather: PortalWeather(summary: "Snow", alerts: ["Warning"]))
        let json = String(data: try JSONEncoder().encode(snap), encoding: .utf8)!
        for key in ["siteLocation", "stopsAhead", "weather", "cashappURL"] { XCTAssertTrue(json.contains(key), key) }
        XCTAssertFalse(json.contains("Client 0")); XCTAssertFalse(json.contains("@"))             // names and emails never leave the phone
    }

    func testTrucksAreSentToTheTrucksEndpoint() async throws {
        let http = Recorder()
        let client = PortalClient(baseURL: URL(string: "https://example.com")!, token: "t", client: http)
        try await client.publishTrucks([PortalTruck(label: "Truck 1", latitude: 44.98, longitude: -93.27)])
        try await client.publishTrucks([], remove: ["Truck 1"])
        try await client.publishTrucks([])
        XCTAssertEqual(http.requests[0].httpMethod, "PUT")
        XCTAssertEqual(http.requests[0].url?.path, "/v1/portal/trucks")
        let body = String(data: http.requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("\"label\":\"Truck 1\"")); XCTAssertTrue(body.contains("latitude"))
        let removal = try JSONDecoder().decode([String: JSONValue].self, from: http.requests[1].httpBody!)
        XCTAssertEqual(removal["remove"], .array([.string("Truck 1")])); XCTAssertEqual(removal["trucks"], .array([]))
        XCTAssertEqual(String(data: http.requests[2].httpBody!, encoding: .utf8), "{\"trucks\":[]}")
    }
}
