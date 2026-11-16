import Foundation

public enum RoutingError: Error, Equatable {
    case badResponse(String)
    case invalidMatrix
}

/// Seconds to drive between every pair of points. Filled by Google (server-side batch), Apple (on-device ETAs),
/// or the offline estimate.
public struct DriveTimeMatrix: Equatable, Sendable {
    public let points: [Coordinate]
    public let seconds: [[Double]]

    public init(points: [Coordinate], seconds: [[Double]]) {
        self.points = points
        self.seconds = seconds
    }

    public var isValid: Bool {
        seconds.count == points.count && seconds.allSatisfy { $0.count == points.count && $0.allSatisfy { $0.isFinite && $0 >= 0 } }
    }
}

/// Reads times from a matrix when both points are in it, otherwise from a fallback.
public struct MatrixProvider: DriveTimeProvider {
    private let matrix: DriveTimeMatrix
    private let index: [Coordinate: Int]
    private let fallback: DriveTimeProvider

    public init(matrix: DriveTimeMatrix, fallback: DriveTimeProvider = HaversineDriveTime()) {
        self.matrix = matrix
        self.fallback = fallback
        var idx: [Coordinate: Int] = [:]
        for (i, p) in matrix.points.enumerated() where idx[p] == nil { idx[p] = i }
        self.index = idx
    }

    public func seconds(from: Coordinate, to: Coordinate) -> Double {
        if let i = index[from], let j = index[to], matrix.isValid { return matrix.seconds[i][j] }
        return fallback.seconds(from: from, to: to)
    }
}

public protocol MatrixSource: Sendable {
    func matrix(for points: [Coordinate]) async throws -> DriveTimeMatrix
}

/// Builds a matrix from any synchronous provider (the offline estimate).
public struct ProviderMatrixSource: MatrixSource {
    public let provider: DriveTimeProvider
    public init(provider: DriveTimeProvider = HaversineDriveTime()) { self.provider = provider }
    public func matrix(for points: [Coordinate]) async throws -> DriveTimeMatrix {
        DriveTimeMatrix(points: points, seconds: points.map { a in points.map { b in a == b ? 0 : provider.seconds(from: a, to: b) } })
    }
}

/// Tries the primary source (for example Google traffic-aware) and falls back if it throws or returns junk.
public struct FallbackMatrixSource: MatrixSource {
    public let primary: MatrixSource
    public let secondary: MatrixSource
    public init(primary: MatrixSource, secondary: MatrixSource) {
        self.primary = primary
        self.secondary = secondary
    }
    public func matrix(for points: [Coordinate]) async throws -> DriveTimeMatrix {
        if let m = try? await primary.matrix(for: points), m.isValid, m.points == points { return m }
        return try await secondary.matrix(for: points)
    }
}

/// Splits a big matrix into blocks that respect an API's element limit (origins x destinations per request).
public enum MatrixChunker {
    public struct Block: Equatable, Sendable {
        public let origins: Range<Int>
        public let destinations: Range<Int>
    }

    public static func blocks(count: Int, maxElements: Int) -> [Block] {
        guard count > 0, maxElements > 0 else { return [] }
        let side = max(1, Int(Double(maxElements).squareRoot()))
        var out: [Block] = []
        for o in stride(from: 0, to: count, by: side) {
            for d in stride(from: 0, to: count, by: side) {
                out.append(Block(origins: o..<min(o + side, count), destinations: d..<min(d + side, count)))
            }
        }
        return out
    }
}
