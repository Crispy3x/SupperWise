import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP seam so the client can be tested without a network.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Gets traffic-aware drive times from the Ridgeline routing server (`server/`), which holds the Google key.
/// The app never sees the Google key. Keep the server token in the Keychain, not in code or `AppData`.
/// Pairs the server could not route come back as `null` and are filled with the offline estimate.
public struct ProxyMatrixSource: MatrixSource {
    public let baseURL: URL
    public let token: String
    public let client: HTTPClient
    public let timeout: TimeInterval
    public let fallback: DriveTimeProvider

    public init(baseURL: URL, token: String, client: HTTPClient = URLSessionHTTPClient(),
                timeout: TimeInterval = 15, fallback: DriveTimeProvider = HaversineDriveTime()) {
        self.baseURL = baseURL
        self.token = token
        self.client = client
        self.timeout = timeout
        self.fallback = fallback
    }

    private struct WirePoint: Codable { let latitude: Double; let longitude: Double }
    private struct WireRequest: Codable { let points: [WirePoint] }
    private struct WireResponse: Codable { let seconds: [[Double?]] }

    public func matrix(for points: [Coordinate]) async throws -> DriveTimeMatrix {
        guard points.count >= 2 else {
            // Nothing to ask for; the server needs at least two points.
            return DriveTimeMatrix(points: points, seconds: points.map { _ in [0.0] })
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/matrix"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(WireRequest(points: points.map { WirePoint(latitude: $0.latitude, longitude: $0.longitude) }))

        let (data, status) = try await client.send(request)
        guard status == 200 else { throw RoutingError.badResponse("Routing server returned HTTP \(status)") }
        guard let wire = try? JSONDecoder().decode(WireResponse.self, from: data) else {
            throw RoutingError.badResponse("Routing server sent an unreadable response")
        }
        let n = points.count
        guard wire.seconds.count == n, wire.seconds.allSatisfy({ $0.count == n }) else { throw RoutingError.invalidMatrix }

        let seconds = (0..<n).map { i in
            (0..<n).map { j -> Double in
                if i == j { return 0 }
                return wire.seconds[i][j] ?? fallback.seconds(from: points[i], to: points[j])
            }
        }
        let matrix = DriveTimeMatrix(points: points, seconds: seconds)
        guard matrix.isValid else { throw RoutingError.invalidMatrix }
        return matrix
    }
}

public enum RoutingServerSettings {
    /// The server address the app may use. Anything but https is refused, except a server on this same device
    /// for testing, because the access token travels with every request.
    public static func validatedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        return nil
    }
}
