import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RidgelineCore

private final class FakeHTTP: HTTPClient, @unchecked Sendable {
    var status = 200
    var body = Data()
    var shouldThrow = false
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        requests.append(request)
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return (body, status)
    }
}

final class ProxyMatrixSourceTests: XCTestCase {
    private let base = URL(string: "https://routes.example.com")!
    private let start = Coordinate(latitude: 45, longitude: -93)
    private func pts() -> [Coordinate] {
        [start, Coordinate(latitude: 45.01, longitude: -93), Coordinate(latitude: 45.02, longitude: -93)]
    }

    func testSendsTokenAndPointsAndReadsMatrix() async throws {
        let http = FakeHTTP()
        http.body = Data(#"{"seconds":[[0,100,250],[110,0,120],[260,130,0]],"cached":false,"elements":9}"#.utf8)
        let m = try await ProxyMatrixSource(baseURL: base, token: "abc", client: http).matrix(for: pts())
        XCTAssertEqual(m.seconds[0][2], 250)
        XCTAssertEqual(m.seconds[1][0], 110)
        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.url?.path, "/v1/matrix")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(req.httpBody)) as? [String: Any]
        XCTAssertEqual((sent?["points"] as? [Any])?.count, 3)
    }

    func testNullsAreFilledFromOfflineEstimate() async throws {
        let http = FakeHTTP()
        http.body = Data(#"{"seconds":[[0,null,250],[110,0,120],[260,130,0]]}"#.utf8)
        let m = try await ProxyMatrixSource(baseURL: base, token: "t", client: http).matrix(for: pts())
        XCTAssertEqual(m.seconds[0][1], HaversineDriveTime().seconds(from: pts()[0], to: pts()[1]), accuracy: 0.001)
        XCTAssertTrue(m.isValid)
    }

    func testErrorsThrow() async {
        let http = FakeHTTP()
        let source = ProxyMatrixSource(baseURL: base, token: "t", client: http)
        http.status = 401
        await XCTAssertThrowsAsync(try await source.matrix(for: pts()))
        http.status = 200
        http.body = Data("not json".utf8)
        await XCTAssertThrowsAsync(try await source.matrix(for: pts()))
        http.body = Data(#"{"seconds":[[0,1],[1,0]]}"#.utf8)   // 2x2 for 3 points
        await XCTAssertThrowsAsync(try await source.matrix(for: pts()))
        http.shouldThrow = true
        await XCTAssertThrowsAsync(try await source.matrix(for: pts()))
    }

    func testFallbackSourceCoversServerOutage() async throws {
        let http = FakeHTTP()
        http.shouldThrow = true
        let source = FallbackMatrixSource(primary: ProxyMatrixSource(baseURL: base, token: "t", client: http),
                                          secondary: ProviderMatrixSource())
        let m = try await source.matrix(for: pts())
        XCTAssertTrue(m.isValid)
        XCTAssertGreaterThan(m.seconds[0][1], 0)
    }

    func testEndToEndPlannerUsesServerTimesThenWeather() async {
        let http = FakeHTTP()
        // Server says every leg takes 600 s.
        http.body = Data(#"{"seconds":[[0,600,600],[600,0,600],[600,600,0]]}"#.utf8)
        let planner = RoutePlanner(matrixSource: FallbackMatrixSource(primary: ProxyMatrixSource(baseURL: base, token: "t", client: http),
                                                                      secondary: ProviderMatrixSource()))
        let stops = [Stop(id: UUID(), name: "a", coordinate: pts()[1], priority: 1, serviceMinutes: 0),
                     Stop(id: UUID(), name: "b", coordinate: pts()[2], priority: 1, serviceMinutes: 0)]
        let clear = await planner.plan(stops: stops, start: start, conditions: .clear)
        XCTAssertEqual(clear.totalDriveSeconds, 1200, accuracy: 0.001)         // two legs of 600 s from the server
        let snow = await planner.plan(stops: stops, start: start, conditions: WeatherConditions(snowfallRateInPerHour: 1, accumulationInches: 6))
        XCTAssertGreaterThan(snow.totalDriveSeconds, 1200)
        XCTAssertEqual(http.requests.count, 2)
    }
}

private func XCTAssertThrowsAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
