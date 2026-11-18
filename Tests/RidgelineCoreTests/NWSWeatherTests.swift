import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RidgelineCore

private final class ScriptedHTTP: HTTPClient, @unchecked Sendable {
    var responses: [String: (Int, Data)] = [:]
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        requests.append(request)
        let key = request.url?.absoluteString ?? ""
        guard let r = responses.first(where: { key.hasPrefix($0.key) })?.value else { return (Data(), 404) }
        return (r.1, r.0)
    }
}

final class NWSParsingTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(NWSParsing.parseDuration("PT2H"), 7200)
        XCTAssertEqual(NWSParsing.parseDuration("PT30M"), 1800)
        XCTAssertEqual(NWSParsing.parseDuration("P1DT12H"), 129_600)
        XCTAssertEqual(NWSParsing.parseDuration("P2D"), 172_800)
        XCTAssertEqual(NWSParsing.parseDuration("PT1H30M"), 5400)
        XCTAssertNil(NWSParsing.parseDuration("P1M"))      // months are not accepted
        XCTAssertNil(NWSParsing.parseDuration("2H"))
        XCTAssertNil(NWSParsing.parseDuration("PT"))
        XCTAssertNil(NWSParsing.parseDuration("PTH"))
    }

    func testInterval() throws {
        let i = try XCTUnwrap(NWSParsing.parseInterval("2026-11-17T12:00:00+00:00/PT6H"))
        XCTAssertEqual(i.end.timeIntervalSince(i.start), 21_600)
        XCTAssertNil(NWSParsing.parseInterval("garbage"))
        XCTAssertNil(NWSParsing.parseInterval("2026-11-17T12:00:00+00:00/nope"))
    }

    /// Real response shape (values copied from a live gridpoint response, shortened).
    private let realShape = """
    {"properties":{
      "snowfallAmount":{"uom":"wmoUnit:mm","values":[{"validTime":"2026-11-17T10:00:00+00:00/PT2H","value":0},{"validTime":"2026-11-17T12:00:00+00:00/PT6H","value":0}]},
      "temperature":{"uom":"wmoUnit:degC","values":[{"validTime":"2026-11-17T10:00:00+00:00/PT1H","value":6.666666666666667},{"validTime":"2026-11-17T11:00:00+00:00/PT5H","value":7.777777777777778}]},
      "windSpeed":{"uom":"wmoUnit:km_h-1","values":[{"validTime":"2026-11-17T10:00:00+00:00/PT2H","value":14.816}]},
      "windGust":{"uom":"wmoUnit:km_h-1","values":[{"validTime":"2026-11-17T10:00:00+00:00/PT1H","value":24.076}]},
      "visibility":{"uom":"wmoUnit:m","values":[{"validTime":"2026-11-17T10:00:00+00:00/P1DT12H","value":16093.44}]}
    }}
    """

    func testReadsRealShape() throws {
        let f = try NWSForecast(gridpointJSON: Data(realShape.utf8))
        XCTAssertEqual(f.snowfallMM.count, 2)
        XCTAssertEqual(f.temperatureC.count, 2)
        XCTAssertEqual(f.visibilityM[0].durationSeconds, 129_600)
        let start = f.snowfallMM[0].start
        let s = f.summary(from: start, to: start.addingTimeInterval(8 * 3600))
        XCTAssertEqual(s.snowfallInches, 0, accuracy: 1e-9)
        XCTAssertEqual(s.minVisibilityMiles!, 10, accuracy: 0.01)
        XCTAssertEqual(s.maxWindMph!, 14.816 / 1.609344, accuracy: 0.001)
    }

    func testNullValuesAndMissingSeriesAreTolerated() throws {
        let json = """
        {"properties":{"snowfallAmount":{"values":[{"validTime":"2026-11-17T10:00:00+00:00/PT2H","value":null},{"validTime":"bad","value":3}]}}}
        """
        let f = try NWSForecast(gridpointJSON: Data(json.utf8))
        XCTAssertTrue(f.snowfallMM.isEmpty)
        XCTAssertTrue(f.temperatureC.isEmpty)
        XCTAssertThrowsError(try NWSForecast(gridpointJSON: Data("[]".utf8)))
        XCTAssertThrowsError(try NWSForecast(gridpointJSON: Data("nope".utf8)))
    }

    private func forecast(snowMM: Double, hours: Int, tempC: Double = -3, windKmh: Double = 16.09344) -> NWSForecast {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let end = t0.addingTimeInterval(Double(hours) * 3600)
        return NWSForecast(snowfallMM: [TimedValue(start: t0, end: end, value: snowMM)],
                           temperatureC: [TimedValue(start: t0, end: end, value: tempC)],
                           windSpeedKmh: [TimedValue(start: t0, end: end, value: windKmh)],
                           windGustKmh: [], visibilityM: [])
    }

    func testSnowfallIsSharedInProportionToOverlap() {
        let f = forecast(snowMM: 25.4, hours: 6)
        let t0 = f.snowfallMM[0].start
        XCTAssertEqual(f.summary(from: t0, to: t0.addingTimeInterval(6 * 3600)).snowfallInches, 1.0, accuracy: 1e-9)
        XCTAssertEqual(f.summary(from: t0.addingTimeInterval(3 * 3600), to: t0.addingTimeInterval(6 * 3600)).snowfallInches, 0.5, accuracy: 1e-9)
        XCTAssertEqual(f.summary(from: t0.addingTimeInterval(-10 * 3600), to: t0.addingTimeInterval(20 * 3600)).snowfallInches, 1.0, accuracy: 1e-9)
        XCTAssertEqual(f.summary(from: t0.addingTimeInterval(7 * 3600), to: t0.addingTimeInterval(9 * 3600)).snowfallInches, 0)
    }

    func testPeakRateTemperatureAndUnits() {
        let f = forecast(snowMM: 25.4, hours: 2, tempC: 0)     // 1 inch in 2 hours = 0.5 in/hr
        let t0 = f.snowfallMM[0].start
        let s = f.summary(from: t0, to: t0.addingTimeInterval(2 * 3600))
        XCTAssertEqual(s.peakSnowRateInPerHour, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.temperatureF!, 32, accuracy: 1e-9)
        XCTAssertEqual(s.maxWindMph!, 10, accuracy: 1e-6)
        let c = s.conditions
        XCTAssertEqual(c.accumulationInches, 1, accuracy: 1e-9)
        XCTAssertEqual(c.temperatureF, 32, accuracy: 1e-9)
    }

    func testEmptyOrBackwardsWindow() {
        let f = forecast(snowMM: 25.4, hours: 2)
        let t0 = f.snowfallMM[0].start
        XCTAssertEqual(f.summary(from: t0, to: t0).snowfallInches, 0)
        XCTAssertEqual(f.summary(from: t0.addingTimeInterval(100), to: t0).snowfallInches, 0)
        XCTAssertEqual(NWSForecast(snowfallMM: [], temperatureC: [], windSpeedKmh: [], windGustKmh: [], visibilityM: [])
                        .summary(from: t0, to: t0.addingTimeInterval(3600)).conditions, WeatherConditions())
    }

    func testHeavierSnowForecastSlowsTheRoute() {
        let light = forecast(snowMM: 10, hours: 6)
        let heavy = forecast(snowMM: 150, hours: 6)
        let t0 = light.snowfallMM[0].start
        let end = t0.addingTimeInterval(6 * 3600)
        let m = ConditionsModel()
        XCTAssertLessThan(m.speedFactor(heavy.summary(from: t0, to: end).conditions),
                          m.speedFactor(light.summary(from: t0, to: end).conditions))
    }

    func testWinterAlertsFilteredAndSorted() throws {
        let json = """
        {"features":[
          {"properties":{"event":"Winter Weather Advisory","severity":"Minor","headline":"Advisory text","onset":"2026-11-18T00:00:00-06:00","ends":"2026-11-18T12:00:00-06:00"}},
          {"properties":{"event":"Winter Storm Warning","severity":"Severe","headline":"Warning text"}},
          {"properties":{"event":"Heat Advisory","severity":"Moderate","headline":"Hot"}},
          {"properties":{"severity":"Severe"}}
        ]}
        """
        let alerts = try NWSAlerts.parseWinterAlerts(Data(json.utf8))
        XCTAssertEqual(alerts.map(\.event), ["Winter Storm Warning", "Winter Weather Advisory"])
        XCTAssertNotNil(alerts[1].onset)
        XCTAssertNil(alerts[0].onset)
        XCTAssertEqual(try NWSAlerts.parseWinterAlerts(Data(#"{"features":[]}"#.utf8)).count, 0)
        XCTAssertThrowsError(try NWSAlerts.parseWinterAlerts(Data("x".utf8)))
    }

    func testClientFollowsPointsToGridAndSendsUserAgent() async throws {
        let http = ScriptedHTTP()
        http.responses["https://api.weather.gov/points/44.98,-93.27"] =
            (200, Data(#"{"properties":{"forecastGridData":"https://api.weather.gov/gridpoints/MPX/108,72"}}"#.utf8))
        http.responses["https://api.weather.gov/gridpoints/MPX/108,72"] = (200, Data(realShape.utf8))
        let client = NWSClient(client: http, userAgent: "RidgelineOpsTest")
        let f = try await client.forecast(near: Coordinate(latitude: 44.9778, longitude: -93.2650))
        XCTAssertEqual(f.snowfallMM.count, 2)
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "User-Agent"), "RidgelineOpsTest")
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "Accept"), "application/geo+json")
        XCTAssertEqual(http.requests[0].url?.path, "/points/44.98,-93.27")   // location rounded, not exact
    }

    func testClientRefusesLinksToOtherHosts() async {
        let http = ScriptedHTTP()
        http.responses["https://api.weather.gov/points/"] =
            (200, Data(#"{"properties":{"forecastGridData":"https://evil.example.com/gridpoints/X"}}"#.utf8))
        let client = NWSClient(client: http, userAgent: "t")
        do {
            _ = try await client.forecast(near: Coordinate(latitude: 1, longitude: 2))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(http.requests.count, 1)   // never fetched the foreign link
        }
    }

    func testClientErrorsAndAlerts() async throws {
        let http = ScriptedHTTP()
        let client = NWSClient(client: http, userAgent: "t")
        do { _ = try await client.forecast(near: Coordinate(latitude: 1, longitude: 2)); XCTFail() } catch {}
        http.responses["https://api.weather.gov/alerts/active"] =
            (200, Data(#"{"features":[{"properties":{"event":"Blizzard Warning","severity":"Extreme"}}]}"#.utf8))
        let alerts = try await client.activeWinterAlerts(near: Coordinate(latitude: 44.9778, longitude: -93.265))
        XCTAssertEqual(alerts.first?.event, "Blizzard Warning")
        XCTAssertTrue(http.requests.last?.url?.absoluteString.contains("point=44.98,-93.27") ?? false)
    }
}
