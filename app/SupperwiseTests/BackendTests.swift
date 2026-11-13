import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Supperwise

/// A fake Supabase: records each request and answers with a canned reply.
final class FakeServer: URLProtocol {
    nonisolated(unsafe) static var replies: [(String, Int, String)] = []   // (path suffix, status, body)
    nonisolated(unsafe) static var seen: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seen.append(request)
        var body = request.httpBody ?? Data()
        if body.isEmpty, let s = request.httpBodyStream {
            s.open(); defer { s.close() }
            var buf = [UInt8](repeating: 0, count: 65536)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; body.append(buf, count: n) }
        }
        Self.bodies.append(body)
        let path = request.url?.path ?? ""
        let r = Self.replies.first { path.hasSuffix($0.0) } ?? ("", 404, "{}")
        let resp = HTTPURLResponse(url: request.url!, statusCode: r.1, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(r.2.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class BackendTests: XCTestCase {
    func backend(_ store: SessionStore = MemorySessionStore()) -> Backend {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeServer.self]
        FakeServer.seen = []; FakeServer.bodies = []
        return Backend(base: URL(string: "https://test.supabase.co")!, anonKey: "anon", session: URLSession(configuration: config), store: store)
    }

    let sessionJSON = #"{"access_token":"tok","refresh_token":"ref","expires_in":3600,"user":{"id":"u1","email":"a@b.co"}}"#

    func testSignInWithCodeKeepsTheSession() async throws {
        FakeServer.replies = [("/auth/v1/otp", 200, "{}"), ("/auth/v1/verify", 200, sessionJSON)]
        let store = MemorySessionStore()
        let b = backend(store)
        try await b.sendCode(to: "a@b.co")
        try await b.verify(email: "a@b.co", code: "123456")
        XCTAssertTrue(b.isSignedIn)
        XCTAssertEqual(store.value?.userID, "u1")
        XCTAssertEqual(FakeServer.seen.last?.value(forHTTPHeaderField: "apikey"), "anon")
        let sent = try JSONSerialization.jsonObject(with: FakeServer.bodies.last!) as? [String: Any]
        XCTAssertEqual(sent?["token"] as? String, "123456")
        b.signOut()
        XCTAssertNil(store.value)
    }

    func testSubmitIsPendingAndUsesTheUsersToken() async throws {
        let s = try Backend.parseSession(Data(sessionJSON.utf8))
        FakeServer.replies = [("/rest/v1/community_recipes", 201, "")]
        let b = backend(MemorySessionStore(s))
        let r = Recipe(id: "community_x", name: "Nonna's soup", side: "Bread.", cuisine: "Italian", minutes: 40, difficulty: "Easy",
                       protein: "legumes", allergens: [.gluten], equipment: [.stovetop], spice: 0,
                       ingredients: [RecipeIngredient(ingredient: "white_beans", amount: 2, text: "2 cans", note: "")],
                       steps: ["Simmer.", "Season.", "Serve."], photo: nil, vegetarian: true, pescatarian: true,
                       mildNote: nil, vegetarianSwap: nil, servings: 4, source: "Community")
        try await b.submit(r, authorName: "Rosa", photoJPEG: nil)
        let req = try XCTUnwrap(FakeServer.seen.last)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let row = try XCTUnwrap(try JSONSerialization.jsonObject(with: FakeServer.bodies.last!) as? [String: Any])
        XCTAssertNil(row["status"])                                   // the server sets pending; the app can't choose
        XCTAssertEqual((row["recipe"] as? [String: Any])?["name"] as? String, "Nonna's soup")
    }

    func testApprovedListDecodes() async throws {
        let row = #"[{"id":"r1","author_name":"Rosa","status":"approved","photo_path":"u1/p.jpg","reject_reason":null,"created_at":"2026-11-13T10:00:00.123456+00:00","recipe":{"id":"community_x","name":"Nonna's soup","side":"Bread.","cuisine":"Italian","minutes":40,"difficulty":"Easy","protein":"legumes","allergens":["gluten"],"equipment":["stovetop"],"spice":0,"ingredients":[{"ingredient":"white_beans","amount":2,"text":"2 cans","note":""}],"steps":["a","b","c"],"photo":null,"vegetarian":true,"pescatarian":true,"mildNote":null,"vegetarianSwap":null,"servings":4}}]"#
        FakeServer.replies = [("/rest/v1/community_recipes", 200, row)]
        let list = try await backend().approvedRecipes(search: "soup")
        XCTAssertEqual(list.first?.recipe.name, "Nonna's soup")
        XCTAssertEqual(list.first?.photoURL?.absoluteString, "https://YOUR-PROJECT.supabase.co/storage/v1/object/public/recipe-photos/u1/p.jpg")
        let q = FakeServer.seen.last?.url?.query ?? ""
        XCTAssertTrue(q.contains("status=eq.approved"))
        XCTAssertTrue(q.contains("ilike"))
    }

    func testFoodScanScoresLikeEverythingElse() throws {
        let reply = #"{"remaining":97,"result":{"kind":"meal","name":"Cheeseburger and fries","portion":"1 burger, medium fries","ingredients":[{"name":"beef patty","visible":true},{"name":"frying oil","visible":false}],"nutrition":{"kcal":1100,"proteinG":35,"fiberG":6,"addedSugarG":10,"saturatedFatG":18,"sodiumMg":1800},"allergens":["gluten","dairy","sesame"],"ultraProcessed":true,"fried":true,"confidence":"medium","notes":"Portion of fries is hard to judge."}}"#
        let (scan, left) = try Backend.parseScan(Data(reply.utf8))
        XCTAssertEqual(left, 97)
        XCTAssertLessThan(scan.score, 30)                              // fried, ultra-processed, 1,100 kcal
        XCTAssertEqual(scan.householdAllergens, [.gluten, .dairy, .sesame])
        XCTAssertEqual(scan.notVegetarian, ["beef patty"])
        let salad = #"{"remaining":5,"result":{"kind":"meal","name":"Lentil salad","portion":"2 cups","ingredients":[{"name":"lentils","visible":true}],"nutrition":{"kcal":420,"proteinG":22,"fiberG":14,"addedSugarG":2,"saturatedFatG":2,"sodiumMg":380},"allergens":[],"ultraProcessed":false,"confidence":"high","notes":""}}"#
        XCTAssertGreaterThanOrEqual(try Backend.parseScan(Data(salad.utf8)).0.score, 75)
    }

    func testErrorsAreReadable() {
        XCTAssertEqual(Backend.error(code: 429, data: Data(#"{"error":"That's all 100 scans for this month."}"#.utf8)),
                       .overLimit("That's all 100 scans for this month."))
        XCTAssertEqual(Backend.error(code: 401, data: Data()), .signedOut)
        XCTAssertFalse(BackendConfig.isConfigured)                     // placeholders until the project exists
    }
}
