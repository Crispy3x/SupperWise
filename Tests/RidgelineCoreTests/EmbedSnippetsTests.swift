import XCTest
@testable import RidgelineCore

final class EmbedSnippetsTests: XCTestCase {
    private let token = "AbCdEfGhIjKlMnOpQrStUv01"

    func testScriptSnippetsPointAtTheServer() {
        XCTAssertEqual(EmbedSnippets.script(portalBaseURL: " https://plow.example.com/ "),
                       "<div data-ridgeline></div>\n<script src=\"https://plow.example.com/embed.js\" async></script>")
        XCTAssertEqual(EmbedSnippets.script(portalBaseURL: "https://plow.example.com", mode: .tips),
                       "<div data-ridgeline data-mode=\"tips\"></div>\n<script src=\"https://plow.example.com/embed.js\" async></script>")
    }

    func testIframeFallback() {
        XCTAssertEqual(EmbedSnippets.iframe(portalBaseURL: "https://plow.example.com"),
                       "<iframe src=\"https://plow.example.com/embed/tracker\" title=\"Track your service\" loading=\"lazy\" referrerpolicy=\"no-referrer\" style=\"width:100%;height:640px;border:0\"></iframe>")
        XCTAssertTrue(EmbedSnippets.iframe(portalBaseURL: "https://plow.example.com", mode: .tips)?.contains("/embed/tips") == true)
    }

    func testOnlyHttpsServersGiveSnippets() {
        XCTAssertNil(EmbedSnippets.script(portalBaseURL: ""))
        XCTAssertNil(EmbedSnippets.script(portalBaseURL: "http://plow.example.com"))
        XCTAssertNil(EmbedSnippets.script(portalBaseURL: "plow.example.com"))
        XCTAssertNil(EmbedSnippets.script(portalBaseURL: "https://plow.example.com/?x=1"))
        XCTAssertNil(EmbedSnippets.script(portalBaseURL: "https://plow.example.com/\"><script>"))
        XCTAssertNil(EmbedSnippets.iframe(portalBaseURL: "https://user:pw@plow.example.com"))
    }

    func testClientLinkToTheOwnersWebsitePage() {
        XCTAssertEqual(EmbedSnippets.clientLink(websitePage: "https://ridgeplow.com/track", token: token),
                       "https://ridgeplow.com/track?code=\(token)")
        XCTAssertEqual(EmbedSnippets.clientLink(websitePage: "https://ridgeplow.com/?page_id=12", token: token),
                       "https://ridgeplow.com/?page_id=12&code=\(token)")
        XCTAssertEqual(EmbedSnippets.clientLink(websitePage: "https://ridgeplow.com/track?code=old", token: token),
                       "https://ridgeplow.com/track?code=\(token)")
        XCTAssertNil(EmbedSnippets.clientLink(websitePage: nil, token: token))
        XCTAssertNil(EmbedSnippets.clientLink(websitePage: "http://ridgeplow.com/track", token: token))
        XCTAssertNil(EmbedSnippets.clientLink(websitePage: "https://ridgeplow.com/track", token: "short"))
        XCTAssertNil(EmbedSnippets.clientLink(websitePage: "https://ridgeplow.com/track#x", token: token))
    }

    func testWebsitePageValidation() {
        XCTAssertEqual(EmbedSnippets.cleanWebsitePage("  https://ridgeplow.com/track "), "https://ridgeplow.com/track")
        XCTAssertNil(EmbedSnippets.cleanWebsitePage("ridgeplow.com/track"))
        XCTAssertNil(EmbedSnippets.cleanWebsitePage("javascript:alert(1)"))
        XCTAssertNil(EmbedSnippets.websitePageProblem(""))
        XCTAssertNil(EmbedSnippets.websitePageProblem("https://ridgeplow.com/track"))
        XCTAssertEqual(EmbedSnippets.websitePageProblem("http://ridgeplow.com"), "Use the https:// address of the page.")
        XCTAssertNotNil(EmbedSnippets.websitePageProblem("ridgeplow"))
    }

    func testSeasonEmailUsesTheWebsitePageWhenSet() {
        var data = AppData()
        data.broadcastSettings.portalBaseURL = "https://plow.example.com"
        data.profile.websiteTrackingPage = "https://ridgeplow.com/track"
        XCTAssertEqual(data.clientPageLink(token: token), "https://ridgeplow.com/track?code=\(token)")
        data.profile.websiteTrackingPage = nil
        XCTAssertEqual(data.clientPageLink(token: token), "https://plow.example.com/c/\(token)")
        data.broadcastSettings.portalBaseURL = ""
        XCTAssertNil(data.clientPageLink(token: token))
    }
}
